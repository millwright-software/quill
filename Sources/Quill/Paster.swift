import AppKit
import CoreGraphics

/// Puts text at the cursor: save the clipboard, paste, put the clipboard back.
enum Paster {
    private static let restoreDelay: Duration = .milliseconds(500)   // Hex's figure; 100 ms races slow apps
    private static let vKeyCode: CGKeyCode = 9

    @MainActor
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ask clipboard managers not to record it (nspasteboard.org convention).
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount

        postCommandV()

        // Returns once Cmd-V is posted; the clipboard comes back in the background.
        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            // Only restore if nothing else has written to the clipboard since.
            if pasteboard.changeCount == ours {
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
