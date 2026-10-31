import AppKit
import SwiftUI

@main
struct QuillApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: model.state.menuBarImage)
        }
        .menuBarExtraStyle(.menu)

        Window("Quill Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
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
        Button("Quit Quill") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
