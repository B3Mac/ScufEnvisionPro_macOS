import AppKit
import CoreGraphics
import ScufCore

/// Posts synthetic keyboard, media-key and mouse events. Needs Accessibility permission.
/// Thread-safe: called from the HID thread and from macro threads.
final class KeySender: @unchecked Sendable {
    static let shared = KeySender()

    private let source = CGEventSource(stateID: .hidSystemState)
    private let lock = NSLock()
    private var modifierCounts: [Modifier: Int] = [:]

    private func currentFlags() -> CGEventFlags {
        var flags = CGEventFlags()
        if (modifierCounts[.command] ?? 0) > 0 { flags.insert(.maskCommand) }
        if (modifierCounts[.shift] ?? 0) > 0 { flags.insert(.maskShift) }
        if (modifierCounts[.option] ?? 0) > 0 { flags.insert(.maskAlternate) }
        if (modifierCounts[.control] ?? 0) > 0 { flags.insert(.maskControl) }
        if (modifierCounts[.function] ?? 0) > 0 { flags.insert(.maskSecondaryFn) }
        return flags
    }

    func keyDown(_ code: UInt16) { post(code, down: true) }
    func keyUp(_ code: UInt16) { post(code, down: false) }

    private func post(_ code: UInt16, down: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        if let modifier = KeyCodes.modifierKeys[code] {
            let count = modifierCounts[modifier] ?? 0
            modifierCounts[modifier] = down ? count + 1 : max(0, count - 1)
            event.type = .flagsChanged
        }
        event.flags = currentFlags()
        event.post(tap: .cghidEventTap)
    }

    func comboDown(_ combo: KeyCombo) {
        for modifier in combo.orderedModifiers { keyDown(modifier.keyCode) }
        keyDown(combo.keyCode)
    }

    func comboUp(_ combo: KeyCombo) {
        keyUp(combo.keyCode)
        for modifier in combo.orderedModifiers.reversed() { keyUp(modifier.keyCode) }
    }

    func tap(_ combo: KeyCombo) {
        comboDown(combo)
        usleep(10_000)
        comboUp(combo)
    }

    /// Types text character by character, independent of keyboard layout.
    func type(_ text: String) {
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                units.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                event.post(tap: .cghidEventTap)
            }
            usleep(3_000)
        }
    }

    func media(_ key: MediaKey) {
        DispatchQueue.main.async {
            for down in [true, false] {
                let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
                let data1 = (key.nxKeyType << 16) | ((down ? 0xA : 0xB) << 8)
                let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: data1,
                    data2: -1
                )
                event?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    func mouse(_ button: MouseButton, down: Bool) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left:
            type = down ? .leftMouseDown : .leftMouseUp
            cgButton = .left
        case .right:
            type = down ? .rightMouseDown : .rightMouseUp
            cgButton = .right
        case .middle:
            type = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
        }
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton)?
            .post(tap: .cghidEventTap)
    }

    func click(_ button: MouseButton) {
        mouse(button, down: true)
        usleep(15_000)
        mouse(button, down: false)
    }
}
