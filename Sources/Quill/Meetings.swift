import AVFoundation
import AppKit

/// Meeting mode from the menu: record the mic and the Mac's audio as two tracks, then offer to
/// transcribe them with Whisper Large v3 Turbo. Dictation keeps working during a meeting.
@MainActor
final class Meetings: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case transcribing(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastFolder: URL?
    @Published private(set) var lastTranscript: URL?

    private let recorder: MeetingRecorder
    private let transcriber = MeetingTranscriber()

    init(recorder: Recorder) {
        self.recorder = MeetingRecorder(recorder: recorder)
    }

    var isRecording: Bool { if case .recording = phase { true } else { false } }
    var isTranscribing: Bool { if case .transcribing = phase { true } else { false } }

    func start() {
        do {
            let folder = try recorder.start()
            lastFolder = folder
            lastTranscript = nil
            phase = .recording(since: Date())
            Log.write("meeting recording started")
        } catch {
            Log.write("meeting start failed: \(error)")
            phase = .failed("couldn't start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let (folder, duration) = recorder.stop() else { return }
        phase = .idle
        let silent = Self.isSilent(folder.appendingPathComponent("system.m4a"))
        Log.write("meeting recording stopped after \(Int(duration)) s, system audio \(silent ? "silent" : "present")")
        offerTranscription(folder: folder, duration: duration, systemSilent: silent)
    }

    // MARK: Transcription

    private func offerTranscription(folder: URL, duration: TimeInterval, systemSilent: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Meeting saved (\(Self.clock(duration)))"
        var info = "Desktop › Quill Meetings › \(folder.lastPathComponent)\n\nTranscribe it now with Whisper Large v3 Turbo? About a minute per ten minutes of audio. The very first time, setting up the model takes 10–15 minutes more."
        if systemSilent {
            info += "\n\nThe Mac's audio track is silent. Fine for an in-person meeting; if this was a call, allow Quill in System Settings › Privacy & Security › Screen & System Audio Recording."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Transcribe")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Show in Finder")
        switch alert.runModal() {
        case .alertFirstButtonReturn: transcribe(folder: folder)
        case .alertThirdButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([folder])
        default: break
        }
    }

    func transcribeLast() {
        if let lastFolder { transcribe(folder: lastFolder) }
    }

    private func transcribe(folder: URL) {
        guard !isTranscribing else { return }
        phase = .transcribing("Starting…")
        Task {
            do {
                let transcript = try await transcriber.transcribe(folder: folder) { message in
                    Task { @MainActor [weak self] in
                        if self?.isTranscribing == true { self?.phase = .transcribing(message) }
                    }
                }
                lastTranscript = transcript
                phase = .idle
                NSSound(named: "Glass")?.play()
                openLastTranscript()
            } catch {
                Log.write("meeting transcription failed: \(error)")
                phase = .failed("transcription: \(error.localizedDescription)")
            }
        }
    }

    /// Opens the transcript without pulling focus from what he's doing.
    func openLastTranscript() {
        guard let lastTranscript else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(lastTranscript, configuration: config)
    }

    func openFolder() {
        let folder = lastFolder ?? MeetingRecorder.baseFolder
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: folder.path) ? folder
                                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
    }

    // MARK: Helpers

    /// A denied System Audio permission records silence rather than failing, so check the track.
    private static func isSilent(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000) else { return true }
        let channels = Int(file.processingFormat.channelCount)
        var peak: Float = 0
        var framesRead: AVAudioFramePosition = 0
        let limit = AVAudioFramePosition(file.processingFormat.sampleRate * 300)   // the first five minutes is enough
        while framesRead < min(file.length, limit) {
            do { try file.read(into: buffer) } catch { break }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            for c in 0..<channels {
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[c][i])) }
            }
            if peak > 0.001 { return false }
            framesRead += AVAudioFramePosition(buffer.frameLength)
        }
        return true
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
