import AppKit
import SwiftUI

@main
struct QuillApp: App {
    // @State, not @StateObject: the views below observe the model themselves. Observing it here
    // re-evaluated the scenes on every change, which reconfigured the MenuBarExtra while its
    // menu was open and could recurse until the main thread's stack ran out (crash 11/17).
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarIcon(model: model, meetings: model.meetings)
        }
        .menuBarExtraStyle(.menu)

        Window("Welcome to Quill", id: "welcome") {
            OnboardingView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Quill Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// Dictation's state wins while it's active; otherwise a meeting shows: recording, then writing.
struct MenuBarIcon: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meetings: Meetings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: image)
            .onAppear { FirstLaunch.openIfNeeded { openWindow(id: "welcome") } }
    }

    private var image: NSImage {
        let dictating = model.state == .listening || model.state == .transcribing || model.state == .held
        if !dictating {
            if meetings.isRecording, let mark = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording a meeting") {
                mark.isTemplate = true
                return mark
            }
            if meetings.isTranscribing { return QuillState.transcribing.menuBarImage }
        }
        return model.state.menuBarImage
    }
}

/// The meeting section of the menu.
struct MeetingMenu: View {
    @ObservedObject var meetings: Meetings
    var developer = false

    var body: some View {
        switch meetings.phase {
        case .recording(let since):
            // A start time, not a live timer: a ticking Text rebuilds the open menu every second.
            Text("Recording meeting since \(since, style: .time)")
            if let note = meetings.statusText { Text(note) }
            Button("Stop Meeting Recording") { meetings.stop() }
        case .transcribing(let progress):
            Text(progress)
        case .failed(let why):
            Text("Meeting: \(why)")
            Button("Start Meeting Recording") { meetings.start() }
        case .idle:
            Button("Start Meeting Recording") { meetings.start() }
        }
        if !meetings.isRecording, !meetings.isTranscribing, meetings.lastFolder != nil, meetings.lastTranscript == nil {
            Button("Transcribe Last Meeting") { meetings.transcribeLast() }
        }
        if meetings.lastTranscript != nil {
            Button("Open Last Transcript") { meetings.openLastTranscript() }
        }
        if developer || meetings.lastFolder != nil {
            Button("Open Meetings Folder") { meetings.openFolder() }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    /// Option held while opening the menu shows the developer items (timings, log, re-transcribe…).
    private var developer: Bool { model.developerMenu }

    var body: some View {
        // Only say something when there's something to say; "Ready" is the quiet default.
        if model.state != .idle || developer {
            Text(model.state.label)
        }
        if developer, let timing = model.lastTiming {
            Text(timing)
        }
        if !model.accessibilityTrusted {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !model.microphoneGranted {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }
        if model.lastText != nil {
            Button("Paste Last Transcript") { model.pasteLast() }
            Button("Copy Last Transcript") { model.copyLast() }
        }
        if developer {
            Button("Re-transcribe Last Recording") { model.retranscribeLast() }
                .disabled(model.lastAudio == nil)
            if let text = model.lastText {
                Text(text.count > 60 ? String(text.prefix(60)) + "…" : text)
            }
        }
        Divider()
        MeetingMenu(meetings: model.meetings, developer: developer)
        Divider()
        if developer {
            Text("Hold \(model.hotkeyKey.name) to talk")
            Toggle("Live Preview While Talking", isOn: $model.livePreview)
            Button("Welcome to Quill…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "welcome")
            }
            Button("Open Log") { NSWorkspace.shared.open(Log.url) }
            Divider()
        }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        Button("About Quill") { About.show() }
        Button("Quit Quill") {
            if model.meetings.isRecording { model.meetings.stop() }   // never lose a meeting to Quit
            NSApp.terminate(nil)
        }
            .keyboardShortcut("q")
    }
}
