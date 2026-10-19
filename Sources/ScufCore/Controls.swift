import Foundation

/// Every physical input on the SCUF Envision Pro.
public enum ControllerButton: String, CaseIterable, Codable, Hashable, Sendable, CodingKeyRepresentable {
    case a, b, x, y
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case lb, rb, lt, rt
    case l3, r3
    case view, menu, home, profile
    case g1, g2, g3, g4, g5
    case p1, p2, p3, p4
    case saxLeft, saxRight

    public var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        case .lb: return "LB"
        case .rb: return "RB"
        case .lt: return "LT"
        case .rt: return "RT"
        case .l3: return "L3 (left stick click)"
        case .r3: return "R3 (right stick click)"
        case .view: return "View"
        case .menu: return "Menu"
        case .home: return "SCUF Home"
        case .profile: return "Profile button"
        case .g1: return "G1"
        case .g2: return "G2"
        case .g3: return "G3"
        case .g4: return "G4"
        case .g5: return "G5"
        case .p1: return "P1 paddle"
        case .p2: return "P2 paddle"
        case .p3: return "P3 paddle"
        case .p4: return "P4 paddle"
        case .saxLeft: return "SAX left"
        case .saxRight: return "SAX right"
        }
    }

    /// A compact label for chips and hotspots.
    public var shortName: String {
        switch self {
        case .dpadUp: return "D-pad ↑"
        case .dpadDown: return "D-pad ↓"
        case .dpadLeft: return "D-pad ←"
        case .dpadRight: return "D-pad →"
        case .l3: return "L3"
        case .r3: return "R3"
        case .home: return "Home"
        case .profile: return "Profile"
        case .p1: return "P1"
        case .p2: return "P2"
        case .p3: return "P3"
        case .p4: return "P4"
        case .saxLeft: return "SAX L"
        case .saxRight: return "SAX R"
        default: return displayName
        }
    }

    public var group: ButtonGroup {
        switch self {
        case .g1, .g2, .g3, .g4, .g5: return .gKeys
        case .p1, .p2, .p3, .p4, .saxLeft, .saxRight: return .paddles
        case .a, .b, .x, .y: return .face
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: return .dpad
        case .lb, .rb, .lt, .rt: return .shoulders
        case .l3, .r3: return .sticks
        case .view, .menu, .home, .profile: return .system
        }
    }

    /// The gamepad button this input produces when left at its default (nil for the extra inputs).
    public var naturalPadButton: PadButton? {
        switch self {
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .dpadUp: return .dpadUp
        case .dpadDown: return .dpadDown
        case .dpadLeft: return .dpadLeft
        case .dpadRight: return .dpadRight
        case .lb: return .lb
        case .rb: return .rb
        case .lt: return .lt
        case .rt: return .rt
        case .l3: return .l3
        case .r3: return .r3
        case .view: return .view
        case .menu: return .menu
        case .home: return .home
        case .profile, .g1, .g2, .g3, .g4, .g5, .p1, .p2, .p3, .p4, .saxLeft, .saxRight: return nil
        }
    }

    /// Stable ordering index, used to make event ordering deterministic.
    public var order: Int { ControllerButton.allCases.firstIndex(of: self) ?? 0 }
}

public enum ButtonGroup: String, CaseIterable, Sendable {
    case gKeys = "G-Keys"
    case paddles = "Paddles & SAX"
    case face = "Face Buttons"
    case dpad = "D-pad"
    case shoulders = "Bumpers & Triggers"
    case sticks = "Stick Clicks"
    case system = "System"

    public var buttons: [ControllerButton] { ControllerButton.allCases.filter { $0.group == self } }
}

/// Buttons on the virtual gamepad (Xbox layout) that any physical input can be mapped to.
public enum PadButton: String, CaseIterable, Codable, Hashable, Sendable, CodingKeyRepresentable {
    case a, b, x, y
    case lb, rb, lt, rt
    case l3, r3
    case view, menu, home
    case dpadUp, dpadDown, dpadLeft, dpadRight

    public var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .lb: return "LB"
        case .rb: return "RB"
        case .lt: return "LT"
        case .rt: return "RT"
        case .l3: return "L3"
        case .r3: return "R3"
        case .view: return "View"
        case .menu: return "Menu"
        case .home: return "Home"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        }
    }

    /// What a Switch game (and Astris) calls this button, by position.
    public var switchName: String {
        switch self {
        case .a: return "B"
        case .b: return "A"
        case .x: return "Y"
        case .y: return "X"
        case .lb: return "L"
        case .rb: return "R"
        case .lt: return "ZL"
        case .rt: return "ZR"
        case .l3: return "L-stick click"
        case .r3: return "R-stick click"
        case .view: return "−"
        case .menu: return "+"
        case .home: return "Home"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        }
    }
}

/// A decoded snapshot of the physical controller.
/// Sticks are -1...1 with Y positive = down (HID convention). Triggers are 0...1.
public struct ControllerState: Equatable, Sendable {
    public var buttons: Set<ControllerButton> = []
    public var leftX = 0.0
    public var leftY = 0.0
    public var rightX = 0.0
    public var rightY = 0.0
    public var leftTrigger = 0.0
    public var rightTrigger = 0.0

    public init() {}
}
