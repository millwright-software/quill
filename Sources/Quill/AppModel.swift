import AppKit
import Foundation

enum QuillState: Equatable {
    case loading(String)
    case idle
    case listening
    case transcribing
    case held        // transcript ready, but the target app lost focus: not pasted
    case failed(String)

    /// The feather mark for this state, from Resources/menubar (drawn by scripts/make-icons.swift).
    var iconName: String {
        switch self {
        case .loading, .idle: "quill-idle"
        case .listening: "quill-listening"
        case .transcribing: "quill-writing"
        case .held: "quill-held"
        case .failed: "quill-error"
        }
    }

    var menuBarImage: NSImage {
        let image = NSImage(named: iconName) ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Quill")!
        image.isTemplate = true
        return image
    }

    var label: String {
        switch self {
        case .loading(let what): "Loading: \(what)"
        case .idle: "Ready"
        case .listening: "Listening…"
        case .transcribing: "Transcribing…"
        case .held: "Held: focus moved, not pasted. Use Paste or Copy below."
        case .failed(let why): "Error: \(why)"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: QuillState = .loading("starting")
    @Published var lastText: String?
    @Published var lastTiming: String?
    @Published var accessibilityTrusted = false
    @Published var microphoneGranted = false
    /// Live words in the bubble while holding; off = the bubble shows only where the paste will go.
    @Published var livePreview = UserDefaults.standard.object(forKey: "livePreview") as? Bool ?? true {
        didSet { UserDefaults.standard.set(livePreview, forKey: "livePreview") }
    }

    /// The held modifier that starts dictation; applied to the running monitor at once.
    @Published var hotkeyKey = HotkeyKey.saved {
        didSet {
            UserDefaults.standard.set(hotkeyKey.rawValue, forKey: "hotkey")
            hotkey?.key = hotkeyKey
            Log.write("hotkey set to \(hotkeyKey.name)")
        }
    }

    /// The last clip, kept in memory until its transcript is pasted into the app it was meant for.
    private(set) var lastAudio: [Float]?

    private let recorder = Recorder()
    private let bubble = Bubble()
    private var liveTask: Task<Void, Never>?
    private let transcriber = Transcriber()
    private var hotkey: HotkeyMonitor?
    private var targetPID: pid_t?
    private var pressedAt: Date?
    private var releasedAt: Date?

    init() {
        Log.write("launch")
        Task { await start() }
    }

    private func start() async {
        LoginItem.followMove()
        microphoneGranted = await Permissions.requestMicrophone()
        if microphoneGranted {
            do { try recorder.warmUp(); Log.write("mic warm") }
            catch { Log.write("mic warm-up failed: \(error)") }
        }
        accessibilityTrusted = Permissions.accessibility(prompt: true)
        startHotkeyWhenTrusted()

        state = .loading("speech model (first run downloads it)")
        do {
            let t0 = Date()
            try await transcriber.load()
            Log.write("model loaded in \(ms(since: t0)) ms")
            state = .idle
        } catch {
            Log.write("model load failed: \(error)")
            state = .failed("model: \(error.localizedDescription)")
        }
    }

    /// The tap needs Accessibility; poll until it's granted, then install it.
    private func startHotkeyWhenTrusted() {
        if Permissions.accessibility(prompt: false) {
            accessibilityTrusted = true
            let monitor = HotkeyMonitor()
            monitor.key = hotkeyKey
            monitor.onPress = { [weak self] in self?.press() }
            monitor.onRelease = { [weak self] in self?.release() }
            monitor.onCancel = { [weak self] in self?.cancel() }
            if monitor.start() {
                hotkey = monitor
                Log.write("hotkey tap installed")
            } else {
                Log.write("hotkey tap failed to install")
                state = .failed("could not watch the keyboard")
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.startHotkeyWhenTrusted()
            }
        }
    }

    /// Re-reads both permissions (the Settings window calls this while it is open).
    func refreshPermissions() {
        accessibilityTrusted = Permissions.accessibility(prompt: false)
        microphoneGranted = Permissions.microphoneGranted()
    }

    // MARK: Hold to talk

    private func press() {
        guard state == .idle || state == .held else { return }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        pressedAt = Date()
        do {
            try recorder.start()
            state = .listening
            bubble.show(target: appName(targetPID))
            if livePreview { startLiveText() }
            Log.write("press: recording (start took \(ms(since: pressedAt!)) ms), target \(appName(targetPID))")
        } catch {
            Log.write("recorder start failed: \(error)")
            state = .failed("microphone: \(error.localizedDescription)")
        }
    }

    private func cancel() {
        guard state == .listening else { return }
        stopLiveText()
        bubble.hide()
        _ = recorder.stop()
        state = lastText != nil && lastWasHeld ? .held : .idle
        Log.write("cancelled (another key or a click in the first 0.5 s)")
    }

    private var lastWasHeld = false

    private func release() {
        guard state == .listening, let pressedAt else { return }
        stopLiveText()
        let samples = recorder.stop()
        let held = Date().timeIntervalSince(pressedAt)
        if held < 0.3 {
            bubble.hide()
            state = lastWasHeld ? .held : .idle
            Log.write("tap under 0.3 s, discarded")
            return
        }
        releasedAt = Date()
        let seconds = Double(samples.count) / Recorder.sampleRate
        Log.write(String(format: "release: %.2f s of audio", seconds))
        lastAudio = samples
        transcribeAndPaste(samples, target: targetPID)
    }

    private func transcribeAndPaste(_ samples: [Float], target: pid_t?) {
        state = .transcribing
        bubble.transcribing()
        let startedAt = releasedAt ?? Date()
        Task {
            do {
                let text = try await transcriber.transcribe(samples)
                let tText = ms(since: startedAt)
                guard !text.isEmpty else {
                    Log.write("empty transcript after \(tText) ms")
                    bubble.hide()
                    state = .idle
                    return
                }
                lastText = text
                bubble.update(text: text)
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if let target, front == target {
                    Paster.paste(text)
                    let tPaste = ms(since: startedAt)
                    lastWasHeld = false
                    lastAudio = nil   // confirmed: Cmd-V went to the app it was meant for
                    lastTiming = "Last: \(tText) ms to text, \(tPaste) ms to Cmd-V"
                    Log.write("pasted into \(appName(front)): \(tText) ms to text, \(tPaste) ms to Cmd-V, \(text.count) chars")
                    state = .idle
                    bubble.hide()
                } else {
                    lastWasHeld = true
                    lastTiming = "Last: \(tText) ms to text (held)"
                    Log.write("HELD: target \(appName(target)) but front is \(appName(front)); not pasted, \(text.count) chars")
                    state = .held
                    bubble.held()
                    NSSound.beep()
                }
            } catch {
                Log.write("transcription failed: \(error)")
                state = .failed("transcription: \(error.localizedDescription)")
                bubble.hide()
            }
        }
    }

    // MARK: Live text

    /// While the key is held, re-transcribe the capture so far about every 0.4 s and show it in the
    /// bubble. A rough draft: the paste comes from one full pass on release.
    private func startLiveText() {
        liveTask?.cancel()
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                let audio = self.recorder.snapshot(lastSeconds: 20)
                guard audio.count > Int(Recorder.sampleRate * 0.4) else { continue }
                if let text = try? await self.transcriber.transcribe(audio),
                   !Task.isCancelled, self.state == .listening, !text.isEmpty {
                    self.bubble.update(text: text)
                }
            }
        }
    }

    private func stopLiveText() {
        liveTask?.cancel()
        liveTask = nil
    }

    // MARK: Menu

    func pasteLast() {
        guard let text = lastText else { return }
        Task {
            // Let the menu close so the paste lands in the app underneath.
            try? await Task.sleep(for: .milliseconds(250))
            Paster.paste(text)
            lastWasHeld = false
            lastAudio = nil
            state = .idle
            Log.write("pasted from menu into \(appName(NSWorkspace.shared.frontmostApplication?.processIdentifier))")
        }
    }

    func copyLast() {
        guard let text = lastText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Log.write("copied from menu")
    }

    func retranscribeLast() {
        guard let samples = lastAudio else { return }
        releasedAt = Date()
        // From the menu there's no key-press target: hold it, then Paste or Copy.
        transcribeAndPaste(samples, target: nil)
    }

    // MARK: Helpers

    private func ms(since date: Date) -> Int { Int(Date().timeIntervalSince(date) * 1000) }

    private func appName(_ pid: pid_t?) -> String {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return "none" }
        return app.localizedName ?? "pid \(pid)"
    }
}
