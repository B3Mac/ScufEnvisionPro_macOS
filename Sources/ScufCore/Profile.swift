import Foundation

public enum OutputMode: String, CaseIterable, Codable, Hashable, Sendable {
    /// A virtual Xbox-layout gamepad that games and emulators see (needs the virtual-device entitlement).
    case virtualGamepad
    /// Gamepad buttons and stick directions become key presses (works everywhere, sticks are digital).
    case keyboard
    /// Only non-gamepad actions run (keys, macros, scripts...). Gamepad mappings do nothing.
    case actionsOnly

    public var displayName: String {
        switch self {
        case .virtualGamepad: return "Virtual gamepad"
        case .keyboard: return "Keyboard mode"
        case .actionsOnly: return "Actions only"
        }
    }
}

public struct DirectionKeys: Codable, Hashable, Sendable {
    public var up: UInt16?
    public var down: UInt16?
    public var left: UInt16?
    public var right: UInt16?

    public init(up: UInt16? = nil, down: UInt16? = nil, left: UInt16? = nil, right: UInt16? = nil) {
        self.up = up
        self.down = down
        self.left = left
        self.right = right
    }
}

/// Keys that gamepad buttons and stick directions press in keyboard mode.
public struct KeyboardMap: Codable, Hashable, Sendable {
    public var buttons: [PadButton: UInt16]
    public var leftStick: DirectionKeys
    public var rightStick: DirectionKeys
    /// Stick deflection (0...1) that presses a direction key.
    public var stickThreshold: Double

    public init(buttons: [PadButton: UInt16], leftStick: DirectionKeys, rightStick: DirectionKeys, stickThreshold: Double = 0.5) {
        self.buttons = buttons
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.stickThreshold = stickThreshold
    }

    /// Ryujinx's default keyboard layout, which Astris inherits. Face buttons are mapped by
    /// position, so the bottom button is Switch B, like a real Switch controller.
    public static let ryujinxDefault = KeyboardMap(
        buttons: [
            .a: 0x07,        // X key -> Switch B
            .b: 0x06,        // Z key -> Switch A
            .x: 0x09,        // V key -> Switch Y
            .y: 0x08,        // C key -> Switch X
            .lb: 0x0E,       // E -> L
            .rb: 0x20,       // U -> R
            .lt: 0x0C,       // Q -> ZL
            .rt: 0x1F,       // O -> ZR
            .l3: 0x03,       // F
            .r3: 0x04,       // H
            .view: 0x1B,     // - -> Minus
            .menu: 0x18,     // = -> Plus
            .dpadUp: KeyCodes.up,
            .dpadDown: KeyCodes.down,
            .dpadLeft: KeyCodes.left,
            .dpadRight: KeyCodes.right,
        ],
        leftStick: DirectionKeys(up: KeyCodes.w, down: KeyCodes.s, left: KeyCodes.a, right: KeyCodes.d),
        rightStick: DirectionKeys(up: KeyCodes.i, down: KeyCodes.k, left: KeyCodes.j, right: KeyCodes.l)
    )

    /// The default keyboard layout of the Wind Waker HD native port (ZeldaWWHDRecomp). Face buttons
    /// by position, matching the port's own default: the bottom button is the Wii U's B.
    public static let windWakerHDRecomp = KeyboardMap(
        buttons: [
            .a: 0x26,        // J -> B
            .b: 0x28,        // K -> A
            .x: 0x22,        // I -> Y
            .y: 0x25,        // L -> X
            .lb: 0x0C,       // Q -> L
            .rb: 0x0E,       // E -> R
            .lt: 0x38,       // Left Shift -> ZL (target)
            .rt: 0x08,       // C -> ZR
            .l3: 0x07,       // X -> left stick click
            .r3: 0x09,       // V -> right stick click
            .view: 0x30,     // Tab -> Minus
            .menu: 0x24,     // Return -> Plus
            .home: 0x04,     // H -> Home
            .dpadUp: 0x12,   // 1
            .dpadDown: 0x13, // 2
            .dpadLeft: 0x14, // 3
            .dpadRight: 0x15, // 4
        ],
        leftStick: DirectionKeys(up: KeyCodes.w, down: KeyCodes.s, left: KeyCodes.a, right: KeyCodes.d),
        rightStick: DirectionKeys(up: KeyCodes.up, down: KeyCodes.down, left: KeyCodes.left, right: KeyCodes.right)
    )
}

/// Ready-made keyboard layouts for games that only see the keyboard.
public enum KeyboardPreset: String, CaseIterable, Sendable {
    case ryujinx
    case windWakerHDRecomp

    public var displayName: String {
        switch self {
        case .ryujinx: return "Astris / Ryujinx"
        case .windWakerHDRecomp: return "Wind Waker HD (native port)"
        }
    }

    public var map: KeyboardMap {
        switch self {
        case .ryujinx: return .ryujinxDefault
        case .windWakerHDRecomp: return .windWakerHDRecomp
        }
    }
}

/// Starting points for new profiles.
public enum ProfileTemplate: String, CaseIterable, Sendable {
    case blank
    case astris
    case windWakerHDRecomp

    public var displayName: String {
        switch self {
        case .blank: return "Blank Profile"
        case .astris: return "Astris (keyboard mode)"
        case .windWakerHDRecomp: return "Wind Waker HD native port (keyboard mode)"
        }
    }

    public func makeProfile() -> Profile {
        switch self {
        case .blank:
            return Profile(name: "New Profile")
        case .astris:
            var profile = Profile(name: "Astris (keyboard mode)", output: .keyboard)
            profile.keyboardMap = .ryujinxDefault
            return profile
        case .windWakerHDRecomp:
            var profile = Profile(name: "Wind Waker HD (keyboard mode)", output: .keyboard)
            profile.keyboardMap = .windWakerHDRecomp
            return profile
        }
    }
}

public struct Profile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Bundle identifiers of apps that switch to this profile when they come to the front.
    public var linkedApps: [String]
    public var output: OutputMode
    /// Overrides. Inputs missing here use `Profile.defaultBinding(for:)`.
    public var bindings: [ControllerButton: Action]
    public var leftStick: StickSettings
    public var rightStick: StickSettings
    public var leftTrigger: TriggerSettings
    public var rightTrigger: TriggerSettings
    public var keyboardMap: KeyboardMap
    /// Turbo presses per second.
    public var turboHz: Double

    public init(id: UUID = UUID(), name: String, output: OutputMode = .virtualGamepad, linkedApps: [String] = []) {
        self.id = id
        self.name = name
        self.linkedApps = linkedApps
        self.output = output
        self.bindings = [:]
        self.leftStick = StickSettings(output: .leftStick)
        self.rightStick = StickSettings(output: .rightStick)
        self.leftTrigger = TriggerSettings()
        self.rightTrigger = TriggerSettings()
        self.keyboardMap = .ryujinxDefault
        self.turboHz = 12
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profile"
        linkedApps = try c.decodeIfPresent([String].self, forKey: .linkedApps) ?? []
        output = try c.decodeIfPresent(OutputMode.self, forKey: .output) ?? .virtualGamepad
        bindings = try c.decodeIfPresent([ControllerButton: Action].self, forKey: .bindings) ?? [:]
        leftStick = try c.decodeIfPresent(StickSettings.self, forKey: .leftStick) ?? StickSettings(output: .leftStick)
        rightStick = try c.decodeIfPresent(StickSettings.self, forKey: .rightStick) ?? StickSettings(output: .rightStick)
        leftTrigger = try c.decodeIfPresent(TriggerSettings.self, forKey: .leftTrigger) ?? TriggerSettings()
        rightTrigger = try c.decodeIfPresent(TriggerSettings.self, forKey: .rightTrigger) ?? TriggerSettings()
        keyboardMap = try c.decodeIfPresent(KeyboardMap.self, forKey: .keyboardMap) ?? .ryujinxDefault
        turboHz = try c.decodeIfPresent(Double.self, forKey: .turboHz) ?? 12
    }

    public func binding(for input: ControllerButton) -> Action {
        bindings[input] ?? Profile.defaultBinding(for: input)
    }

    /// Mirrors the controller's factory onboard profile, so nothing changes until you remap.
    public static func defaultBinding(for input: ControllerButton) -> Action {
        switch input {
        case .p1: return .gamepad(button: .a, turbo: false)
        case .p2: return .gamepad(button: .y, turbo: false)
        case .p3: return .gamepad(button: .b, turbo: false)
        case .p4: return .gamepad(button: .x, turbo: false)
        case .saxLeft: return .gamepad(button: .lb, turbo: false)
        case .saxRight: return .gamepad(button: .rb, turbo: false)
        case .g2: return .media(key: .volumeDown)
        case .g3: return .media(key: .volumeUp)
        case .g4: return .media(key: .mute)
        case .profile: return .profile(target: .next)
        case .g1, .g5: return .disabled
        default:
            if let pad = input.naturalPadButton { return .gamepad(button: pad, turbo: false) }
            return .disabled
        }
    }

    /// True when the input's analog trigger value should pass straight through to the pad.
    public var leftTriggerIsAnalog: Bool {
        if case .gamepad(.lt, _) = binding(for: .lt) { return true }
        return false
    }

    public var rightTriggerIsAnalog: Bool {
        if case .gamepad(.rt, _) = binding(for: .rt) { return true }
        return false
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var profiles: [Profile]
    public var activeProfileID: UUID
    /// Profile used when auto-switching finds no linked app for the front app.
    public var fallbackProfileID: UUID
    public var autoSwitch: Bool
    /// Stop the controller's built-in volume keys (G2-G4) from reaching macOS directly,
    /// so those buttons only do what their mapping says.
    public var blockOnboardMediaKeys: Bool
    /// Remove the button that paddles/SAX echo from the onboard profile.
    public var stripMirroredButtons: Bool
    /// Check GitHub once a day for a newer release.
    public var checkForUpdates: Bool

    public init(profiles: [Profile], activeProfileID: UUID, fallbackProfileID: UUID) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.fallbackProfileID = fallbackProfileID
        self.autoSwitch = true
        self.blockOnboardMediaKeys = true
        self.stripMirroredButtons = true
        self.checkForUpdates = true
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        if profiles.isEmpty { profiles = AppConfig.makeDefault().profiles }
        self.profiles = profiles
        let active = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        activeProfileID = profiles.contains { $0.id == active } ? active! : profiles[0].id
        let fallback = try c.decodeIfPresent(UUID.self, forKey: .fallbackProfileID)
        fallbackProfileID = profiles.contains { $0.id == fallback } ? fallback! : profiles[0].id
        autoSwitch = try c.decodeIfPresent(Bool.self, forKey: .autoSwitch) ?? true
        blockOnboardMediaKeys = try c.decodeIfPresent(Bool.self, forKey: .blockOnboardMediaKeys) ?? true
        stripMirroredButtons = try c.decodeIfPresent(Bool.self, forKey: .stripMirroredButtons) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
    }

    public static func makeDefault() -> AppConfig {
        let desktop = Profile(name: "Default", output: .virtualGamepad)
        let astris = ProfileTemplate.astris.makeProfile()
        let windWaker = ProfileTemplate.windWakerHDRecomp.makeProfile()
        return AppConfig(profiles: [desktop, astris, windWaker], activeProfileID: desktop.id, fallbackProfileID: desktop.id)
    }

    public var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    public func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// The profile a target resolves to, relative to the active one.
    public func resolve(_ target: ProfileTarget) -> UUID {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return profiles[0].id }
        switch target {
        case .next: return profiles[(index + 1) % profiles.count].id
        case .previous: return profiles[(index - 1 + profiles.count) % profiles.count].id
        case .specific(let id): return profiles.contains { $0.id == id } ? id : activeProfileID
        }
    }

    /// The profile linked to an app, if any.
    public func profileID(forBundleID bundleID: String) -> UUID? {
        profiles.first { $0.linkedApps.contains(bundleID) }?.id
    }
}
