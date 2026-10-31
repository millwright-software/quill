import AppKit
import ApplicationServices
import SwiftUI

/// A small floating bubble at the text cursor while listening: the live words and where they'll go.
@MainActor
final class Bubble {
    final class Model: ObservableObject {
        @Published var target = ""
        @Published var text = ""
        @Published var status: Status = .listening
    }

    enum Status { case listening, transcribing, held }

    private let model = Model()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(target: String) {
        hideTask?.cancel()
        model.target = target
        model.text = ""
        model.status = .listening
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        resize()
    }

    func update(text: String) {
        model.text = text
        resize()
    }

    func transcribing() { model.status = .transcribing }

    func held() {
        model.status = .held
        resize()
        hide(after: .seconds(5))
    }

    func hide(after delay: Duration = .zero) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    // MARK: Window

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: BubbleView(model: model))
        return panel
    }

    private func resize() {
        // After SwiftUI has laid out the new text.
        DispatchQueue.main.async { [weak self] in self?.fit() }
    }

    private func fit() {
        guard let panel, let view = panel.contentView else { return }
        let size = view.fittingSize
        var frame = panel.frame
        frame.origin.y += frame.height - size.height   // grow downward from the top edge
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    /// Just below the text cursor if the app reports it, else below the focused field, else the mouse.
    private func place(_ panel: NSPanel) {
        let anchor = Self.caretRect() ?? Self.focusedElementRect()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        var origin: NSPoint
        if let anchor {
            origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 6)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        }
        // Keep it on screen.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 4), v.maxX - size.width - 4)
            if origin.y < v.minY + 4, let anchor { origin.y = anchor.maxY + 6 }   // flip above the caret
            origin.y = min(max(origin.y, v.minY + 4), v.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Accessibility geometry (AX uses top-left screen coordinates; AppKit uses bottom-left)

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func caretRect() -> NSRect? {
        guard let element = focusedElement() else { return nil }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width >= 0, rect.height > 0 else { return nil }
        return flip(rect)
    }

    private static func focusedElementRect() -> NSRect? {
        guard let element = focusedElement() else { return nil }
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        guard extent.width > 0, extent.height > 0 else { return nil }
        // Anchor at the field's bottom-left corner, as a zero-height line.
        let flipped = flip(CGRect(origin: point, size: extent))
        return NSRect(x: flipped.minX + 8, y: flipped.minY, width: 0, height: 0)
    }

    private static func flip(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct BubbleView: View {
    @ObservedObject var model: Bubble.Model
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
                .scaleEffect(model.status == .listening && pulse ? 1.08 : 1)
                .opacity(model.status == .transcribing ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            if !line.isEmpty {
                // One line; the newest words stay in view and older ones slide off the left.
                Text(line)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(model.status == .held ? .secondary : .primary)
                    .frame(width: 380, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .onAppear { pulse = true }
    }

    private var line: String {
        model.status == .held
            ? "Held: focus left \(model.target), not pasted. Quill menu → Paste or Copy."
            : model.text
    }
}
