import CoreGraphics
import Foundation

/// A modifier that can be held to talk: its key code and the flag bit that says it is down.
/// Masks are the device-dependent NX_DEVICE*KEYMASK values from IOKit's IOLLEvent.h; Fn has no
/// per-side bit, so it uses NX_SECONDARYFNMASK (CGEventFlags.maskSecondaryFn).
enum HotkeyKey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, rightControl, leftOption, fn

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        case .leftOption: "Left Option"
        case .fn: "Fn"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        case .leftOption: 58
        case .fn: 63
        }
    }

    var downMask: UInt64 {
        switch self {
        case .rightOption: 0x40        // NX_DEVICERALTKEYMASK
        case .rightCommand: 0x10       // NX_DEVICERCMDKEYMASK
        case .rightControl: 0x2000     // NX_DEVICERCTLKEYMASK
        case .leftOption: 0x20         // NX_DEVICELALTKEYMASK
        case .fn: CGEventFlags.maskSecondaryFn.rawValue   // NX_SECONDARYFNMASK, 0x800000
        }
    }

    /// The saved choice, Right Option when none.
    static var saved: HotkeyKey {
        UserDefaults.standard.string(forKey: "hotkey").flatMap(HotkeyKey.init(rawValue:)) ?? .rightOption
    }
}

/// Watches for the chosen modifier held alone, through a session event tap.
/// Another key, modifier or mouse click in the first half second cancels it (an Option chord, not
/// dictation). After that the hold is committed: nothing but releasing the key ends it, so a click
/// or keystroke mid-dictation never throws the audio away (a 13.7 s dictation was lost that way 10/30).
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    /// The key to watch; changing it takes effect on the next event (a hold in progress is dropped).
    var key: HotkeyKey = .saved {
        didSet {
            guard key != oldValue, holding else { return }
            holding = false
            onCancel?()
        }
    }

    private var tap: CFMachPort?
    private static let cancelWindow: TimeInterval = 0.5

    private var holding = false
    private var pressedAt = Date()

    private func cancelIfEarly() {
        guard holding, Date().timeIntervalSince(pressedAt) < Self.cancelWindow else { return }
        holding = false
        onCancel?()
    }

    func start() -> Bool {
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == key.keyCode {
                let down = event.flags.rawValue & key.downMask != 0
                if down && !holding {
                    holding = true
                    pressedAt = Date()
                    onPress?()
                } else if !down && holding {
                    holding = false
                    onRelease?()
                }
            } else {
                cancelIfEarly()
            }
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancelIfEarly()
        default:
            break
        }
    }
}
