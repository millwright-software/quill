import AppKit

enum About {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The standard About panel, brought to the front.
    static func show() {
        let credits = """
        Local dictation for Eric. Speech: NVIDIA Parakeet TDT 0.6B v2 (CC-BY-4.0) via FluidAudio (Apache-2.0). Audio never leaves this Mac.

        a feather you write with: bird into words.
        """
        let attributed = NSAttributedString(string: credits, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Quill",
            .applicationVersion: version,
            .version: "",
            .credits: attributed,
        ])
    }
}
