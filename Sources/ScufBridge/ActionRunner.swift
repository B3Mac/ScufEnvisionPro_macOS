import AppKit
import ScufCore

/// Carries out non-gamepad actions when inputs are pressed and released.
final class ActionRunner: @unchecked Sendable {
    let keys = KeySender.shared
    let macros: MacroPlayer

    /// Called (on the HID thread) when an input asks to switch profiles.
    var requestProfile: (ProfileTarget) -> Void = { _ in }

    init() {
        macros = MacroPlayer(keys: keys)
    }

    func handle(_ event: EngineEvent, profileName: String) {
        switch event {
        case let .pressed(input, action):
            pressed(input, action, profileName: profileName)
        case let .released(input, action):
            released(input, action, profileName: profileName)
        }
    }

    private func pressed(_ input: ControllerButton, _ action: Action, profileName: String) {
        switch action {
        case .disabled, .gamepad:
            break
        case .key(let combo):
            keys.comboDown(combo)
        case .text(let string):
            DispatchQueue.global(qos: .userInitiated).async { self.keys.type(string) }
        case .macro(let macro):
            macros.pressed(input, macro)
        case .script(let script):
            ScriptRunner.run(script.command, input: input, event: "press", profile: profileName)
        case .openApp(let path):
            guard !path.isEmpty else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(
                    at: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
        case .openURL(let string):
            guard let url = URL(string: string) else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        case .media(let key):
            keys.media(key)
        case .mouse(let button):
            keys.mouse(button, down: true)
        case .profile(let target):
            requestProfile(target)
        }
    }

    private func released(_ input: ControllerButton, _ action: Action, profileName: String) {
        switch action {
        case .key(let combo):
            keys.comboUp(combo)
        case .macro(let macro):
            macros.released(input, macro)
        case .script(let script):
            ScriptRunner.run(script.releaseCommand, input: input, event: "release", profile: profileName)
        case .mouse(let button):
            keys.mouse(button, down: false)
        default:
            break
        }
    }
}
