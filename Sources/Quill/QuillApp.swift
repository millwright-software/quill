import AppKit
import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarIcon(model: model, meetings: model.meetings)
        }
        .menuBarExtraStyle(.menu)

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

    var body: some View {
        Image(nsImage: image)
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

    var body: some View {
        switch meetings.phase {
        case .recording(let since):
            Text("Recording meeting · \(Text(since, style: .timer))")
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
        Button("Open Meetings Folder") { meetings.openFolder() }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.state.label)
        if let timing = model.lastTiming {
            Text(timing)
        }
        Divider()
        Button("Paste Last Transcript") { model.pasteLast() }
            .disabled(model.lastText == nil)
        Button("Copy Last Transcript") { model.copyLast() }
            .disabled(model.lastText == nil)
        Button("Re-transcribe Last Recording") { model.retranscribeLast() }
            .disabled(model.lastAudio == nil)
        if let text = model.lastText {
            Text(text.count > 60 ? String(text.prefix(60)) + "…" : text)
        }
        Toggle("Live Preview While Talking", isOn: $model.livePreview)
        Divider()
        MeetingMenu(meetings: model.meetings)
        Divider()
        if !model.accessibilityTrusted {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !model.microphoneGranted {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }
        Text("Hold \(model.hotkeyKey.name) to talk")
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        Button("About Quill") { About.show() }
        Button("Open Log") { NSWorkspace.shared.open(Log.url) }
        Button("Quit Quill") {
            if model.meetings.isRecording { model.meetings.stop() }   // never lose a meeting to Quit
            NSApp.terminate(nil)
        }
            .keyboardShortcut("q")
    }
}
