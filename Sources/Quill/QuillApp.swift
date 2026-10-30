import AppKit
import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.state.symbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

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
        Divider()
        if !model.accessibilityTrusted {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !model.microphoneGranted {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }
        Text("Hold Right Option to talk")
        Button("Open Log") { NSWorkspace.shared.open(Log.url) }
        Button("Quit Quill") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
