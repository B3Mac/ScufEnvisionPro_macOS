import Foundation

/// Converts virtual-pad state into held keys for games that only accept a keyboard.
public struct KeyboardModeMapper: Sendable {
    public private(set) var down: Set<UInt16> = []
    private var latched: [String: Bool] = [:]

    public init() {}

    /// Returns the keys to press and release so the keyboard matches `pad`.
    public mutating func update(pad: PadState, map: KeyboardMap) -> (press: [UInt16], release: [UInt16]) {
        var want = Set<UInt16>()
        for button in pad.buttons {
            if let key = map.buttons[button] { want.insert(key) }
        }
        if pad.leftTrigger >= 0.5, let key = map.buttons[.lt] { want.insert(key) }
        if pad.rightTrigger >= 0.5, let key = map.buttons[.rt] { want.insert(key) }

        let threshold = max(0.1, min(0.95, map.stickThreshold))
        func direction(_ id: String, _ amount: Double, _ key: UInt16?) {
            guard let key = key else { return }
            let wasOn = latched[id] ?? false
            let isOn = wasOn ? amount > threshold - 0.1 : amount >= threshold
            latched[id] = isOn
            if isOn { want.insert(key) }
        }
        direction("lu", -pad.leftY, map.leftStick.up)
        direction("ld", pad.leftY, map.leftStick.down)
        direction("ll", -pad.leftX, map.leftStick.left)
        direction("lr", pad.leftX, map.leftStick.right)
        direction("ru", -pad.rightY, map.rightStick.up)
        direction("rd", pad.rightY, map.rightStick.down)
        direction("rl", -pad.rightX, map.rightStick.left)
        direction("rr", pad.rightX, map.rightStick.right)

        let press = want.subtracting(down).sorted()
        let release = down.subtracting(want).sorted()
        down = want
        return (press, release)
    }

    public mutating func releaseAll() -> [UInt16] {
        let keys = down.sorted()
        down.removeAll()
        latched.removeAll()
        return keys
    }
}
