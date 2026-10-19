import Foundation

/// macOS virtual key codes (kVK_*), with display names.
public enum KeyCodes {
    public struct Key: Hashable, Sendable {
        public let code: UInt16
        public let name: String
    }

    public static let all: [Key] = [
        Key(code: 0x00, name: "A"), Key(code: 0x0B, name: "B"), Key(code: 0x08, name: "C"),
        Key(code: 0x02, name: "D"), Key(code: 0x0E, name: "E"), Key(code: 0x03, name: "F"),
        Key(code: 0x05, name: "G"), Key(code: 0x04, name: "H"), Key(code: 0x22, name: "I"),
        Key(code: 0x26, name: "J"), Key(code: 0x28, name: "K"), Key(code: 0x25, name: "L"),
        Key(code: 0x2E, name: "M"), Key(code: 0x2D, name: "N"), Key(code: 0x1F, name: "O"),
        Key(code: 0x23, name: "P"), Key(code: 0x0C, name: "Q"), Key(code: 0x0F, name: "R"),
        Key(code: 0x01, name: "S"), Key(code: 0x11, name: "T"), Key(code: 0x20, name: "U"),
        Key(code: 0x09, name: "V"), Key(code: 0x0D, name: "W"), Key(code: 0x07, name: "X"),
        Key(code: 0x10, name: "Y"), Key(code: 0x06, name: "Z"),
        Key(code: 0x1D, name: "0"), Key(code: 0x12, name: "1"), Key(code: 0x13, name: "2"),
        Key(code: 0x14, name: "3"), Key(code: 0x15, name: "4"), Key(code: 0x17, name: "5"),
        Key(code: 0x16, name: "6"), Key(code: 0x1A, name: "7"), Key(code: 0x1C, name: "8"),
        Key(code: 0x19, name: "9"),
        Key(code: 0x1B, name: "-"), Key(code: 0x18, name: "="), Key(code: 0x21, name: "["),
        Key(code: 0x1E, name: "]"), Key(code: 0x2A, name: "\\"), Key(code: 0x29, name: ";"),
        Key(code: 0x27, name: "'"), Key(code: 0x2B, name: ","), Key(code: 0x2F, name: "."),
        Key(code: 0x2C, name: "/"), Key(code: 0x32, name: "`"),
        Key(code: 0x24, name: "Return"), Key(code: 0x30, name: "Tab"), Key(code: 0x31, name: "Space"),
        Key(code: 0x33, name: "Delete"), Key(code: 0x75, name: "Forward Delete"), Key(code: 0x35, name: "Esc"),
        Key(code: 0x7E, name: "↑"), Key(code: 0x7D, name: "↓"), Key(code: 0x7B, name: "←"),
        Key(code: 0x7C, name: "→"),
        Key(code: 0x73, name: "Home"), Key(code: 0x77, name: "End"), Key(code: 0x74, name: "Page Up"),
        Key(code: 0x79, name: "Page Down"), Key(code: 0x72, name: "Help"),
        Key(code: 0x7A, name: "F1"), Key(code: 0x78, name: "F2"), Key(code: 0x63, name: "F3"),
        Key(code: 0x76, name: "F4"), Key(code: 0x60, name: "F5"), Key(code: 0x61, name: "F6"),
        Key(code: 0x62, name: "F7"), Key(code: 0x64, name: "F8"), Key(code: 0x65, name: "F9"),
        Key(code: 0x6D, name: "F10"), Key(code: 0x67, name: "F11"), Key(code: 0x6F, name: "F12"),
        Key(code: 0x69, name: "F13"), Key(code: 0x6B, name: "F14"), Key(code: 0x71, name: "F15"),
        Key(code: 0x6A, name: "F16"), Key(code: 0x40, name: "F17"), Key(code: 0x4F, name: "F18"),
        Key(code: 0x50, name: "F19"), Key(code: 0x5A, name: "F20"),
        Key(code: 0x52, name: "Keypad 0"), Key(code: 0x53, name: "Keypad 1"), Key(code: 0x54, name: "Keypad 2"),
        Key(code: 0x55, name: "Keypad 3"), Key(code: 0x56, name: "Keypad 4"), Key(code: 0x57, name: "Keypad 5"),
        Key(code: 0x58, name: "Keypad 6"), Key(code: 0x59, name: "Keypad 7"), Key(code: 0x5B, name: "Keypad 8"),
        Key(code: 0x5C, name: "Keypad 9"), Key(code: 0x41, name: "Keypad ."), Key(code: 0x43, name: "Keypad *"),
        Key(code: 0x45, name: "Keypad +"), Key(code: 0x4E, name: "Keypad -"), Key(code: 0x4B, name: "Keypad /"),
        Key(code: 0x4C, name: "Keypad Enter"), Key(code: 0x51, name: "Keypad ="), Key(code: 0x47, name: "Keypad Clear"),
        Key(code: 0x37, name: "Command"), Key(code: 0x36, name: "Right Command"),
        Key(code: 0x38, name: "Shift"), Key(code: 0x3C, name: "Right Shift"),
        Key(code: 0x3A, name: "Option"), Key(code: 0x3D, name: "Right Option"),
        Key(code: 0x3B, name: "Control"), Key(code: 0x3E, name: "Right Control"),
        Key(code: 0x3F, name: "Fn"), Key(code: 0x39, name: "Caps Lock"),
    ]

    private static let names: [UInt16: String] = Dictionary(all.map { ($0.code, $0.name) }, uniquingKeysWith: { a, _ in a })

    public static func name(for code: UInt16) -> String {
        names[code] ?? String(format: "Key 0x%02X", code)
    }

    /// Key codes that are modifier keys, with the modifier they set.
    public static let modifierKeys: [UInt16: Modifier] = [
        0x37: .command, 0x36: .command,
        0x38: .shift, 0x3C: .shift,
        0x3A: .option, 0x3D: .option,
        0x3B: .control, 0x3E: .control,
        0x3F: .function,
    ]

    public static func isModifier(_ code: UInt16) -> Bool { modifierKeys[code] != nil }

    // Common codes used by defaults.
    public static let w: UInt16 = 0x0D, a: UInt16 = 0x00, s: UInt16 = 0x01, d: UInt16 = 0x02
    public static let i: UInt16 = 0x22, j: UInt16 = 0x26, k: UInt16 = 0x28, l: UInt16 = 0x25
    public static let up: UInt16 = 0x7E, down: UInt16 = 0x7D, left: UInt16 = 0x7B, right: UInt16 = 0x7C
}
