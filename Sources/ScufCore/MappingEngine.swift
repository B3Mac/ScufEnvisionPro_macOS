import Foundation

/// A press or release of a physical input, with the action it was bound to when pressed.
public enum EngineEvent: Equatable, Sendable {
    case pressed(ControllerButton, Action)
    case released(ControllerButton, Action)
}

/// The state of the virtual gamepad. Sticks are -1...1 with Y positive = down, triggers 0...1.
public struct PadState: Equatable, Sendable {
    public var buttons: Set<PadButton> = []
    public var leftX = 0.0
    public var leftY = 0.0
    public var rightX = 0.0
    public var rightY = 0.0
    public var leftTrigger = 0.0
    public var rightTrigger = 0.0

    public init() {}

    /// Folds in extra held buttons (from macros); mapped triggers count as fully pulled.
    public func merging(_ extra: Set<PadButton>) -> PadState {
        var copy = self
        copy.buttons.formUnion(extra)
        if copy.buttons.contains(.lt) { copy.leftTrigger = 1 }
        if copy.buttons.contains(.rt) { copy.rightTrigger = 1 }
        return copy
    }
}

public struct EngineOutput: Equatable, Sendable {
    /// Non-gamepad work to do (keys, macros, scripts...). Gamepad actions are folded into `pad`.
    public var events: [EngineEvent]
    public var pad: PadState
    /// True while something time-based (turbo) needs `process` to be called again soon.
    public var needsTicks: Bool
}

/// Turns controller snapshots into actions and a virtual-pad state for one profile.
public struct MappingEngine: Sendable {
    public private(set) var profile: Profile

    private var held: Set<ControllerButton> = []
    private var heldActions: [ControllerButton: Action] = [:]
    private var pressTime: [ControllerButton: Double] = [:]
    private var ltDown = false
    private var rtDown = false
    private var lastState = ControllerState()

    public init(profile: Profile) {
        self.profile = profile
    }

    /// Inputs currently held, as the active profile sees them (including LT/RT past their threshold).
    public var heldInputs: Set<ControllerButton> { held }

    /// Switches profile. Releases everything bound under the old profile; inputs still physically
    /// held stay inert until released, so the button that switched profiles doesn't fire again.
    public mutating func setProfile(_ newProfile: Profile) -> [EngineEvent] {
        var events: [EngineEvent] = []
        for input in held.sorted(by: { $0.order < $1.order }) {
            if let action = heldActions[input] { events.append(.released(input, action)) }
        }
        heldActions.removeAll()
        pressTime.removeAll()
        profile = newProfile
        return events
    }

    /// Releases everything (for example when the controller disconnects).
    public mutating func releaseAll() -> [EngineEvent] {
        let events = held.sorted(by: { $0.order < $1.order }).compactMap { input -> EngineEvent? in
            heldActions[input].map { .released(input, $0) }
        }
        held.removeAll()
        heldActions.removeAll()
        pressTime.removeAll()
        ltDown = false
        rtDown = false
        lastState = ControllerState()
        return events
    }

    /// Re-evaluates the last snapshot (for turbo timing).
    public mutating func tick(now: Double) -> EngineOutput {
        process(lastState, now: now)
    }

    public mutating func process(_ state: ControllerState, now: Double) -> EngineOutput {
        lastState = state

        let lt = profile.leftTrigger.apply(state.leftTrigger)
        let rt = profile.rightTrigger.apply(state.rightTrigger)
        let ltThreshold = profile.leftTrigger.pressThreshold
        let rtThreshold = profile.rightTrigger.pressThreshold
        ltDown = ltDown ? lt > max(0.01, ltThreshold - 0.05) : lt >= ltThreshold
        rtDown = rtDown ? rt > max(0.01, rtThreshold - 0.05) : rt >= rtThreshold

        var current = state.buttons
        current.remove(.lt)
        current.remove(.rt)
        if ltDown { current.insert(.lt) }
        if rtDown { current.insert(.rt) }

        var events: [EngineEvent] = []
        for input in held.subtracting(current).sorted(by: { $0.order < $1.order }) {
            held.remove(input)
            pressTime[input] = nil
            if let action = heldActions.removeValue(forKey: input) {
                events.append(.released(input, action))
            }
        }
        for input in current.subtracting(held).sorted(by: { $0.order < $1.order }) {
            held.insert(input)
            let action = profile.binding(for: input)
            heldActions[input] = action
            pressTime[input] = now
            events.append(.pressed(input, action))
        }

        var pad = PadState()
        var needsTicks = false
        for (input, action) in heldActions {
            guard case let .gamepad(button, turbo) = action else { continue }
            // A trigger bound to its own pad trigger is passed through as analog below.
            if (input == .lt && button == .lt) || (input == .rt && button == .rt) { continue }
            if turbo {
                needsTicks = true
                let elapsed = now - (pressTime[input] ?? now)
                let phase = Int((elapsed * max(1, profile.turboHz) * 2).rounded(.down))
                if phase % 2 == 1 { continue }
            }
            pad.buttons.insert(button)
        }

        if profile.leftTriggerIsAnalog { pad.leftTrigger = lt }
        if profile.rightTriggerIsAnalog { pad.rightTrigger = rt }
        if pad.buttons.contains(.lt) { pad.leftTrigger = 1 }
        if pad.buttons.contains(.rt) { pad.rightTrigger = 1 }

        let left = profile.leftStick.apply(x: state.leftX, y: state.leftY)
        let right = profile.rightStick.apply(x: state.rightX, y: state.rightY)
        route(left, to: profile.leftStick.output, into: &pad)
        route(right, to: profile.rightStick.output, into: &pad)

        let actionEvents = events.filter { event in
            switch event {
            case .pressed(_, let action), .released(_, let action): return !action.isGamepad
            }
        }
        return EngineOutput(events: actionEvents, pad: pad, needsTicks: needsTicks)
    }

    private func route(_ value: (x: Double, y: Double), to output: StickOutput, into pad: inout PadState) {
        switch output {
        case .leftStick:
            pad.leftX = max(-1, min(1, pad.leftX + value.x))
            pad.leftY = max(-1, min(1, pad.leftY + value.y))
        case .rightStick:
            pad.rightX = max(-1, min(1, pad.rightX + value.x))
            pad.rightY = max(-1, min(1, pad.rightY + value.y))
        case .off:
            break
        }
    }
}
