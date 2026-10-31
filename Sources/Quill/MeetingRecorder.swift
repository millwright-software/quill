import Foundation

/// One meeting: the mic (from the warm `Recorder`'s tap) and the Mac's audio output, each to its own
/// .m4a in ~/Desktop/Quill Meetings/<date time>/. If the system audio can't be captured, the mic
/// keeps recording and `systemAudioProblem` says why.
@MainActor
final class MeetingRecorder {
    private let recorder: Recorder
    private let system = SystemAudioRecorder()

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var folder: URL?
    /// Why the system track is missing, when it is; nil when both tracks are recording.
    private(set) var systemAudioProblem: String?

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    static var baseFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Quill Meetings")
    }

    /// Creates the folder and starts both tracks. Throws only if the mic track can't start.
    @discardableResult
    func start() throws -> URL {
        guard !isRecording else { throw CocoaError(.fileWriteFileExists) }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HHmm"
        let dir = Self.baseFolder.appendingPathComponent(stamp.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try recorder.startFile(url: dir.appendingPathComponent("mic.m4a"))
        do {
            try system.start(url: dir.appendingPathComponent("system.m4a"))
            systemAudioProblem = nil
        } catch {
            systemAudioProblem = "\(error)"
            Log.write("meeting: system audio not captured: \(error)")
        }
        folder = dir
        startedAt = Date()
        isRecording = true
        Log.write("meeting started, system audio \(systemAudioProblem == nil ? "on" : "off")")
        return dir
    }

    /// Stops both tracks. Returns the folder and the length of the recording.
    @discardableResult
    func stop() -> (folder: URL, duration: TimeInterval)? {
        guard isRecording, let folder, let startedAt else { return nil }
        recorder.stopFile()
        system.stop()
        isRecording = false
        self.startedAt = nil
        let duration = Date().timeIntervalSince(startedAt)
        Log.write("meeting stopped after \(Int(duration)) s")
        return (folder, duration)
    }
}
