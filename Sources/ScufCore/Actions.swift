import Foundation

public enum Modifier: String, CaseIterable, Codable, Hashable, Sendable {
    case control, option, shift, command, function

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn "
        }
    }

    /// The left-hand key code for this modifier.
    public var keyCode: UInt16 {
        switch self {
        case .control: return 0x3B
        case .option: return 0x3A
        case .shift: return 0x38
        case .command: return 0x37
        case .function: return 0x3F
        }
    }
}

public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Set<Modifier>

    public init(_ keyCode: UInt16, _ modifiers: Set<Modifier> = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Modifiers in the conventional macOS display order.
    public var orderedModifiers: [Modifier] {
        Modifier.allCases.filter { modifiers.contains($0) }
    }

    public var summary: String {
        orderedModifiers.map(\.symbol).joined() + KeyCodes.name(for: keyCode)
    }
}

public enum MediaKey: String, CaseIterable, Codable, Hashable, Sendable {
    case playPause, next, previous, volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// NX_KEYTYPE_* value used for system-defined media key events.
    public var nxKeyType: Int {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    public var displayName: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .next: return "Next track"
        case .previous: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        }
    }
}

public enum MouseButton: String, CaseIterable, Codable, Hashable, Sendable {
    case left, right, middle

    public var displayName: String { rawValue.capitalized + " click" }
}

public enum MacroStep: Codable, Hashable, Sendable {
    case tap(combo: KeyCombo)
    case keyDown(keyCode: UInt16)
    case keyUp(keyCode: UInt16)
    case text(string: String)
    case delay(ms: Int)
    case click(button: MouseButton)
    case padTap(button: PadButton)
    case padDown(button: PadButton)
    case padUp(button: PadButton)

    public var summary: String {
        switch self {
        case .tap(let combo): return "Tap \(combo.summary)"
        case .keyDown(let code): return "Hold \(KeyCodes.name(for: code))"
        case .keyUp(let code): return "Release \(KeyCodes.name(for: code))"
        case .text(let string): return "Type “\(string)”"
        case .delay(let ms): return "Wait \(ms) ms"
        case .click(let button): return button.displayName
        case .padTap(let button): return "Tap pad \(button.displayName)"
        case .padDown(let button): return "Hold pad \(button.displayName)"
        case .padUp(let button): return "Release pad \(button.displayName)"
        }
    }
}

public enum MacroMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// Plays once per press.
    case once
    /// Repeats while the button is held; stops on release.
    case whileHeld
    /// First press starts repeating, next press stops.
    case toggle

    public var displayName: String {
        switch self {
        case .once: return "Play once per press"
        case .whileHeld: return "Repeat while held"
        case .toggle: return "Toggle repeat on/off"
        }
    }
}

public struct Macro: Codable, Hashable, Sendable {
    public var steps: [MacroStep]
    public var mode: MacroMode
    /// Pause between repeats, in milliseconds.
    public var repeatGapMs: Int

    public init(steps: [MacroStep] = [], mode: MacroMode = .once, repeatGapMs: Int = 50) {
        self.steps = steps
        self.mode = mode
        self.repeatGapMs = repeatGapMs
    }
}

public struct ScriptAction: Codable, Hashable, Sendable {
    /// Shell command run with zsh when the button is pressed.
    public var command: String
    /// Optional command run when the button is released.
    public var releaseCommand: String

    public init(command: String = "", releaseCommand: String = "") {
        self.command = command
        self.releaseCommand = releaseCommand
    }
}

public enum ProfileTarget: Codable, Hashable, Sendable {
    case next
    case previous
    case specific(id: UUID)
}

/// What a physical input does.
public enum Action: Codable, Hashable, Sendable {
    case disabled
    case gamepad(button: PadButton, turbo: Bool)
    case key(combo: KeyCombo)
    case text(string: String)
    case macro(macro: Macro)
    case script(script: ScriptAction)
    case openApp(path: String)
    case openURL(url: String)
    case media(key: MediaKey)
    case mouse(button: MouseButton)
    case profile(target: ProfileTarget)

    public var kind: ActionKind {
        switch self {
        case .disabled: return .disabled
        case .gamepad: return .gamepad
        case .key: return .key
        case .text: return .text
        case .macro: return .macro
        case .script: return .script
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .media: return .media
        case .mouse: return .mouse
        case .profile: return .profile
        }
    }

    public var isGamepad: Bool {
        if case .gamepad = self { return true }
        return false
    }

    public func summary(profileName: (UUID) -> String? = { _ in nil }) -> String {
        switch self {
        case .disabled: return "Disabled"
        case .gamepad(let button, let turbo): return "Pad \(button.displayName)" + (turbo ? " (turbo)" : "")
        case .key(let combo): return "Key \(combo.summary)"
        case .text(let string): return string.isEmpty ? "Type text" : "Type “\(string)”"
        case .macro(let macro): return "Macro, \(macro.steps.count) step" + (macro.steps.count == 1 ? "" : "s")
        case .script(let script):
            let first = script.command.split(separator: "\n").first.map(String.init) ?? ""
            return first.isEmpty ? "Run script" : "Run: \(first)"
        case .openApp(let path):
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? "Open app" : "Open \(name)"
        case .openURL(let url): return url.isEmpty ? "Open URL" : "Open \(url)"
        case .media(let key): return key.displayName
        case .mouse(let button): return button.displayName
        case .profile(let target):
            switch target {
            case .next: return "Next profile"
            case .previous: return "Previous profile"
            case .specific(let id): return "Profile: \(profileName(id) ?? "?")"
            }
        }
    }
}

public enum ActionKind: String, CaseIterable, Hashable, Sendable {
    case disabled, gamepad, key, text, macro, script, openApp, openURL, media, mouse, profile

    public var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .gamepad: return "Gamepad button"
        case .key: return "Key / shortcut"
        case .text: return "Type text"
        case .macro: return "Macro"
        case .script: return "Run shell script"
        case .openApp: return "Open app"
        case .openURL: return "Open URL"
        case .media: return "Media key"
        case .mouse: return "Mouse click"
        case .profile: return "Switch profile"
        }
    }

    /// A starting value when the user switches an input to this kind.
    public func defaultAction(for input: ControllerButton) -> Action {
        switch self {
        case .disabled: return .disabled
        case .gamepad: return .gamepad(button: input.naturalPadButton ?? .a, turbo: false)
        case .key: return .key(combo: KeyCombo(KeyCodes.a))
        case .text: return .text(string: "")
        case .macro: return .macro(macro: Macro())
        case .script: return .script(script: ScriptAction())
        case .openApp: return .openApp(path: "")
        case .openURL: return .openURL(url: "https://")
        case .media: return .media(key: .playPause)
        case .mouse: return .mouse(button: .left)
        case .profile: return .profile(target: .next)
        }
    }
}
