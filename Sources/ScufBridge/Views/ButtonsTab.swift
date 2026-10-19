import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScufCore

struct ButtonsTab: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: Profile
    @State private var selected: ControllerButton? = .g1

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(ButtonGroup.allCases, id: \.self) { group in
                        Section(group.rawValue) {
                            ForEach(group.buttons, id: \.self) { input in
                                InputRow(
                                    input: input,
                                    summary: profile.binding(for: input).summary(profileName: model.profileName),
                                    customized: profile.bindings[input] != nil
                                )
                                .tag(input)
                            }
                        }
                    }
                }
                Divider()
                Toggle("Press a controller button to select it", isOn: $model.followController)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 300, idealWidth: 340)

            Group {
                if let input = selected {
                    BindingEditor(
                        input: input,
                        action: actionBinding(for: input),
                        isCustomized: profile.bindings[input] != nil,
                        reset: { profile.bindings[input] = nil }
                    )
                    .id(input)
                } else {
                    Text("Select an input").foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(FollowController(enabled: model.followController, selected: $selected))
    }

    private func actionBinding(for input: ControllerButton) -> Binding<Action> {
        Binding(
            get: { profile.binding(for: input) },
            set: { profile.bindings[input] = $0 }
        )
    }
}

/// Selects whichever input was last pressed on the controller.
private struct FollowController: View {
    @EnvironmentObject private var live: LiveModel
    let enabled: Bool
    @Binding var selected: ControllerButton?

    var body: some View {
        Color.clear
            .onChange(of: live.snapshot.pressSerial) { _, _ in
                if enabled, let pressed = live.snapshot.lastPressed {
                    selected = pressed
                }
            }
    }
}

/// Lights up while the input is held.
private struct PressedDot: View {
    @EnvironmentObject private var live: LiveModel
    let input: ControllerButton

    var body: some View {
        Circle()
            .fill(live.snapshot.held.contains(input) ? Color.green : Color.secondary.opacity(0.25))
            .frame(width: 8, height: 8)
    }
}

private struct InputRow: View {
    let input: ControllerButton
    let summary: String
    let customized: Bool

    var body: some View {
        HStack(spacing: 8) {
            PressedDot(input: input)
            Text(input.displayName)
            Spacer(minLength: 12)
            Text(summary)
                .font(.callout)
                .foregroundStyle(customized ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

struct BindingEditor: View {
    @EnvironmentObject private var model: AppModel
    let input: ControllerButton
    @Binding var action: Action
    let isCustomized: Bool
    let reset: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Action", selection: kindBinding) {
                    ForEach(ActionKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                if isCustomized {
                    Button("Reset to default (\(Profile.defaultBinding(for: input).summary(profileName: model.profileName)))", action: reset)
                }
            } header: {
                Text(input.displayName).font(.title2.weight(.semibold))
            }

            details
        }
        .formStyle(.grouped)
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { action.kind },
            set: { kind in
                if kind != action.kind { action = kind.defaultAction(for: input) }
            }
        )
    }

    @ViewBuilder
    private var details: some View {
        switch action {
        case .disabled:
            Section {
                Text("This input does nothing in this profile.").foregroundStyle(.secondary)
            }

        case .gamepad(let button, let turbo):
            Section {
                Picker("Pad button", selection: Binding(
                    get: { button },
                    set: { action = .gamepad(button: $0, turbo: turbo) }
                )) {
                    ForEach(PadButton.allCases, id: \.self) { pad in
                        Text("\(pad.displayName)   (Switch: \(pad.switchName))").tag(pad)
                    }
                }
                Toggle("Turbo", isOn: Binding(
                    get: { turbo },
                    set: { action = .gamepad(button: button, turbo: $0) }
                ))
            } footer: {
                Text("Sent to the virtual gamepad, or to the matching key in Keyboard Mode. Turbo speed is set on the Sticks & Triggers tab.")
            }

        case .key(let combo):
            Section {
                KeyComboField(combo: Binding(get: { combo }, set: { action = .key(combo: $0) }))
            } footer: {
                Text("The key stays down for as long as you hold the button.")
            }

        case .text(let string):
            Section {
                TextField("Text to type", text: Binding(get: { string }, set: { action = .text(string: $0) }), axis: .vertical)
                    .lineLimit(2...6)
            }

        case .macro(let macro):
            MacroEditor(macro: Binding(get: { macro }, set: { action = .macro(macro: $0) }))

        case .script(let script):
            ScriptEditor(script: Binding(get: { script }, set: { action = .script(script: $0) }))

        case .openApp(let path):
            Section {
                HStack {
                    TextField("Application", text: Binding(get: { path }, set: { action = .openApp(path: $0) }))
                    Button("Choose…") {
                        if let url = chooseApp() { action = .openApp(path: url.path) }
                    }
                }
            }

        case .openURL(let url):
            Section {
                TextField("URL", text: Binding(get: { url }, set: { action = .openURL(url: $0) }))
            } footer: {
                Text("Any URL works, including app links like spotify: or x-apple.systempreferences:.")
            }

        case .media(let key):
            Section {
                Picker("Media key", selection: Binding(get: { key }, set: { action = .media(key: $0) })) {
                    ForEach(MediaKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

        case .mouse(let button):
            Section {
                Picker("Mouse button", selection: Binding(get: { button }, set: { action = .mouse(button: $0) })) {
                    ForEach(MouseButton.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } footer: {
                Text("Clicks at the current pointer position and holds while the button is held.")
            }

        case .profile(let target):
            Section {
                Picker("Switch to", selection: Binding(get: { target }, set: { action = .profile(target: $0) })) {
                    Text("Next profile").tag(ProfileTarget.next)
                    Text("Previous profile").tag(ProfileTarget.previous)
                    Divider()
                    ForEach(model.config.profiles) { profile in
                        Text(profile.name).tag(ProfileTarget.specific(id: profile.id))
                    }
                }
            }
        }
    }

    private func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct ScriptEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var script: ScriptAction

    var body: some View {
        Section {
            TextEditor(text: $script.command)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
        } header: {
            Text("On press")
        } footer: {
            Text("Runs with zsh as a login shell. $SCUF_INPUT, $SCUF_EVENT and $SCUF_PROFILE are set.")
        }
        Section("On release (optional)") {
            TextEditor(text: $script.releaseCommand)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 50)
        }
        Section {
            HStack {
                Button("Test Run") { model.testScript(script.command) }
                    .disabled(script.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Open Script Log") { model.revealScriptLog() }
            }
            if !model.lastScriptOutput.isEmpty {
                ScrollView {
                    Text(model.lastScriptOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
    }
}
