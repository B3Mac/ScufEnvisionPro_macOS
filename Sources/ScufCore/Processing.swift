import Foundation

/// Where a physical stick's motion goes on the virtual pad.
public enum StickOutput: String, CaseIterable, Codable, Hashable, Sendable {
    case leftStick, rightStick, off

    public var displayName: String {
        switch self {
        case .leftStick: return "Left stick"
        case .rightStick: return "Right stick"
        case .off: return "Off"
        }
    }
}

public struct StickSettings: Codable, Hashable, Sendable {
    /// Radial dead zone around the centre, 0...0.5.
    public var innerDeadzone: Double = 0.06
    /// Fraction of travel at the edge that already counts as full deflection, 0...0.3.
    public var outerDeadzone: Double = 0.03
    /// Response curve exponent. 1 = linear, above 1 = finer near the centre, below 1 = faster.
    public var curve: Double = 1.0
    public var invertX = false
    public var invertY = false
    public var output: StickOutput

    public init(output: StickOutput) {
        self.output = output
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        output = try c.decodeIfPresent(StickOutput.self, forKey: .output) ?? .leftStick
        innerDeadzone = try c.decodeIfPresent(Double.self, forKey: .innerDeadzone) ?? 0.06
        outerDeadzone = try c.decodeIfPresent(Double.self, forKey: .outerDeadzone) ?? 0.03
        curve = try c.decodeIfPresent(Double.self, forKey: .curve) ?? 1.0
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? false
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
    }

    /// Applies dead zones, curve and inversion. Input and output are -1...1.
    public func apply(x rawX: Double, y rawY: Double) -> (x: Double, y: Double) {
        let magnitude = (rawX * rawX + rawY * rawY).squareRoot()
        guard magnitude > innerDeadzone, magnitude > 0 else { return (0, 0) }
        let span = max(0.01, 1 - innerDeadzone - outerDeadzone)
        var scaled = min(1, (magnitude - innerDeadzone) / span)
        scaled = pow(scaled, max(0.2, curve))
        var x = rawX / magnitude * scaled
        var y = rawY / magnitude * scaled
        if invertX { x = -x }
        if invertY { y = -y }
        return (max(-1, min(1, x)), max(-1, min(1, y)))
    }
}

public struct TriggerSettings: Codable, Hashable, Sendable {
    /// Travel ignored at the start of the pull, 0...0.5.
    public var deadzone: Double = 0.04
    /// Travel at which the trigger counts as fully pulled, 0.5...1.
    public var maxPoint: Double = 0.96
    /// Response curve exponent. 1 = linear.
    public var curve: Double = 1.0
    /// How far the trigger must be pulled to count as a button press when it is mapped to an action.
    public var pressThreshold: Double = 0.35
    /// Any pull past the dead zone counts as a full pull.
    public var hairTrigger = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deadzone = try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? 0.04
        maxPoint = try c.decodeIfPresent(Double.self, forKey: .maxPoint) ?? 0.96
        curve = try c.decodeIfPresent(Double.self, forKey: .curve) ?? 1.0
        pressThreshold = try c.decodeIfPresent(Double.self, forKey: .pressThreshold) ?? 0.35
        hairTrigger = try c.decodeIfPresent(Bool.self, forKey: .hairTrigger) ?? false
    }

    /// Input and output are 0...1.
    public func apply(_ value: Double) -> Double {
        guard value > deadzone else { return 0 }
        if hairTrigger { return 1 }
        let span = max(0.01, maxPoint - deadzone)
        let scaled = min(1, (value - deadzone) / span)
        return pow(scaled, max(0.2, curve))
    }
}
