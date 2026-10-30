import CoreGraphics
import Foundation

/// Watches for Right Option held alone, through a session event tap.
/// Any other key, modifier or mouse click during the hold cancels it (Hex's rule).
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private static let rightOptionKeyCode: Int64 = 61
    private static let rightOptionDeviceMask: UInt64 = 0x40   // NX_DEVICERALTKEYMASK

    private var tap: CFMachPort?
    private var holding = false

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
            if keyCode == Self.rightOptionKeyCode {
                let down = event.flags.rawValue & Self.rightOptionDeviceMask != 0
                if down && !holding {
                    holding = true
                    onPress?()
                } else if !down && holding {
                    holding = false
                    onRelease?()
                }
            } else if holding {
                holding = false
                onCancel?()
            }
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if holding {
                holding = false
                onCancel?()
            }
        default:
            break
        }
    }
}
