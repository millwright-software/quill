import AppKit
import ApplicationServices
import SwiftUI

/// A small floating bubble at the text cursor while listening: the live words and where they'll go.
@MainActor
final class Bubble {
    /// The live words as a ticker tape running right to left at a steady pace. A word joins the
    /// tape once two live passes agree on it (a moving word can't be taken back), enters at the right
    /// edge, and fades out at the left. A pause in speech is a gap on the tape.
    final class Model: ObservableObject {
        @Published var target = ""
        @Published var status: Status = .listening
        @Published private(set) var words: [Word] = []
        /// How far the tape has run, in points; a word's x is `width - (tape - word.start)`.
        @Published private(set) var tape: CGFloat = 0
        /// The mic level, smoothed: rises fast with the voice, settles slowly.
        @Published private(set) var glow: CGFloat = 0

        func follow(level: CGFloat, over seconds: CGFloat) {
            let target = status == .listening ? level : 0
            let rate: CGFloat = target > glow ? 18 : 4
            glow += (target - glow) * min(1, rate * seconds)
        }

        static let width: CGFloat = 110                 // the last few words
        static let font = NSFont.systemFont(ofSize: 11)
        private static let space: CGFloat = 5
        private static let speed: CGFloat = 50          // points per second, constant (Eric 10/31)
        private static let maxLag: CGFloat = 90         // words waiting beyond this are skipped, to stay current

        private var tapeEnd: CGFloat = 0
        private var emitted = 0
        private var lastPartial: [String] = []
        private var nextID = 0

        func reset() {
            words = []; tape = 0; tapeEnd = 0; emitted = 0; lastPartial = []
        }

        /// A new live pass: put on the tape the words this pass and the last one agree on.
        func set(text: String) {
            let incoming = text.split(separator: " ").map(String.init)
            var stable = 0
            while stable < incoming.count, stable < lastPartial.count, incoming[stable] == lastPartial[stable] { stable += 1 }
            lastPartial = incoming
            if stable > emitted {
                for word in incoming[emitted..<stable] { enqueue(word) }
                emitted = stable
            }
        }

        private func enqueue(_ text: String) {
            // At a constant pace, fast speech would fall further and further behind. If the queue
            // is too long, drop the words that haven't entered yet: the tape shows what's current.
            if tapeEnd - tape > Self.maxLag {
                words.removeAll { $0.start > tape }
                tapeEnd = max(tape, words.last?.end ?? tape)   // after a word that's partly in view
            }
            let width = (text as NSString).size(withAttributes: [.font: Self.font]).width
            let start = max(tapeEnd, tape)   // after the last word, or at the right edge after a pause
            words.append(Word(id: nextID, text: text, start: start, end: start + width + Self.space))
            nextID += 1
            tapeEnd = start + width + Self.space
        }

        func advance(by seconds: CGFloat) {
            tape += Self.speed * seconds
            // Drop words well past the left edge.
            words.removeAll { Self.width - (tape - $0.start) < -200 }
        }
    }

    struct Word: Identifiable {
        let id: Int
        let text: String
        let start: CGFloat
        let end: CGFloat
    }

    enum Status { case listening, transcribing, held }

    private let model = Model()
    /// The mic level, read once per frame while the bubble is up.
    var levelSource: (() -> Float)?
    private var panel: NSPanel?
    private var ticker: CADisplayLink?
    private var tickTarget: TickTarget?
    private var hideTask: Task<Void, Never>?

    func show(target: String) {
        hideTask?.cancel()
        model.target = target
        model.reset()
        model.status = .listening
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        // Cut short a fade still running from the last dictation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        resize()
        startTicker()   // needs the panel's view for its display link
    }

    /// Live words only while the key is held; once it's up the tape just drifts and fades.
    func update(text: String) {
        guard model.status == .listening else { return }
        model.set(text: text)
    }

    func transcribing() {
        model.status = .transcribing
    }

    /// Steps the tape once per screen refresh (a timer drifts against the display and judders).
    private func startTicker() {
        ticker?.invalidate()
        guard let view = panel?.contentView else { return }
        let target = TickTarget { [weak self] seconds in
            guard let self else { return }
            self.model.advance(by: seconds)
            self.model.follow(level: CGFloat(self.levelSource?() ?? 0), over: seconds)
        }
        let link = view.displayLink(target: target, selector: #selector(TickTarget.step(_:)))
        link.add(to: .main, forMode: .common)
        tickTarget = target
        ticker = link
    }

    func held() {
        model.status = .held
        resize()
        hide(after: .seconds(5))
    }

    private static let fadeOut: TimeInterval = 1.4

    func hide(after delay: Duration = .zero) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let panel = self?.panel else { return }
            // Fade out, the words still drifting, rather than vanish.
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOut
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            self?.ticker?.invalidate()
            self?.ticker = nil
            self?.tickTarget = nil
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
        panel.hasShadow = false   // the capsule draws its own glow
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
        let room = BubbleView.glowRoom   // the transparent margin that holds the glow
        if let anchor {
            origin = NSPoint(x: anchor.minX - room, y: anchor.minY - size.height - 6 + room)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x + 12 - room, y: mouse.y - size.height - 12 + room)
        }
        // Keep it on screen.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 4), v.maxX - size.width - 4)
            if origin.y + room < v.minY + 4, let anchor { origin.y = anchor.maxY + 6 - room }   // flip above the caret
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

/// The display link's target: hands each frame's elapsed time to the tape.
private final class TickTarget: NSObject {
    private let onStep: (CGFloat) -> Void
    private var last: CFTimeInterval?

    init(_ onStep: @escaping (CGFloat) -> Void) { self.onStep = onStep }

    @objc func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        if let last { MainActor.assumeIsolated { onStep(CGFloat(now - last)) } }
        last = now
    }
}

private struct BubbleView: View {
    @ObservedObject var model: Bubble.Model

    static let feather: Image = {
        if let image = NSImage(named: "quill-bubble") { image.isTemplate = true; return Image(nsImage: image) }
        return Image(nsImage: NSApp.applicationIconImage)
    }()

    var body: some View {
        HStack(spacing: 5) {
            // The feather writing: slowly back and forth along a faint baseline, tilting a little at
            // each turn. Driven by the clock, not implicit animation, so the layout never moves.
            TimelineView(.animation(paused: model.status != .listening)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = model.status == .listening ? sin(t * 2 * .pi / 2.4) : 0   // one pass = 1.2 s
                let ink = Color.white
                ZStack(alignment: .bottomLeading) {
                    Capsule()
                        .fill(ink.opacity(0.18))
                        .frame(width: 20, height: 1)
                        .offset(x: 1, y: -1.5)
                    Self.feather
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(ink.opacity(0.8))
                        .frame(width: 15, height: 15)
                        .rotationEffect(.degrees(-4 * cos(t * 2 * .pi / 2.4) * (model.status == .listening ? 1 : 0)),
                                        anchor: .bottomLeading)
                        .offset(x: 3 + 4 * phase, y: -1.5)
                        .opacity(model.status == .transcribing ? 0.5 : 1)
                }
                .frame(width: 26, height: 18, alignment: .bottomLeading)
            }
            .frame(width: 26, height: 18)
            stream
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        // A dark HUD in any appearance: subtle, never a white card.
        .background(Color.black.opacity(0.55), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.5)
        )
        .overlay(
            Capsule().strokeBorder(Self.glowColor.opacity(0.15 + 0.6 * model.glow), lineWidth: 0.5 + 0.7 * model.glow)
        )
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        // A soft warm glow that follows the voice, so the bubble is easy to find while talking.
        .shadow(color: Self.glowColor.opacity(0.1 + 0.55 * model.glow), radius: 3 + 9 * model.glow)
        .padding(Self.glowRoom)   // room inside the panel so the glow isn't clipped
    }

    static let glowRoom: CGFloat = 16
    static let glowColor = Color(red: 1.0, green: 0.88, blue: 0.62)   // warm white, a hint of candle

    /// The tape: soft grey words entering at the right edge and fading out at the left.
    @ViewBuilder private var stream: some View {
        let width = Bubble.Model.width
        if model.status == .held {
            Text("Held, not pasted: Quill menu → Paste")
                .font(Font(Bubble.Model.font))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        } else {
            ZStack(alignment: .leading) {
                ForEach(model.words) { word in
                    Text(word.text)
                        .font(Font(Bubble.Model.font))
                        .fixedSize()
                        .offset(x: width - (model.tape - word.start))
                }
            }
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(width: width, height: 14, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.3),
                                         .init(color: .black, location: 0.9),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
    }
}
