import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScufCore

struct ButtonsTab: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: Profile
    @StateObject private var selectedState = ViewState<ControllerButton?>(.g1)

    private var selected: ControllerButton? {
        get { selectedState.value }
        nonmutating set { selectedState.value = newValue }
    }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ControllerStage(
                        selected: $selectedState.value,
                        customized: Set(profile.bindings.keys),
                        summary: summary
                    )
                    InputChips(
                        selected: $selectedState.value,
                        customized: Set(profile.bindings.keys)
                    )
                    Toggle("Press a controller button to select it", isOn: $model.followController)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .padding(14)
            }
            .frame(minWidth: 500, idealWidth: 620)

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
        .background(FollowController(enabled: model.followController, selected: $selectedState.value))
    }

    private func summary(_ input: ControllerButton) -> String {
        profile.binding(for: input).summary(profileName: model.profileName)
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

/// Every input as a chip, grouped. Includes inputs not visible in the current photo.
private struct InputChips: View {
    @EnvironmentObject private var live: LiveModel
    @Binding var selected: ControllerButton?
    let customized: Set<ControllerButton>

    var body: some View {
        let held = live.snapshot.held.union(live.snapshot.state.buttons)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ButtonGroup.allCases, id: \.self) { group in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(group.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 118, alignment: .leading)
                    FlowLayout(spacing: 6) {
                        ForEach(group.buttons, id: \.self) { input in
                            InputChip(
                                title: input.shortName,
                                isSelected: input == selected,
                                isHeld: held.contains(input),
                                isCustomized: customized.contains(input)
                            )
                            .onTapGesture { selected = input }
                        }
                    }
                }
            }
        }
    }
}

private struct InputChip: View {
    let title: String
    let isSelected: Bool
    let isHeld: Bool
    let isCustomized: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isHeld ? Color.green : (isCustomized ? Color.accentColor : Color.secondary.opacity(0.35)))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.10))
        )
        .overlay(
            Capsule().strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.2)
        )
        .contentShape(Capsule())
        .animation(.easeOut(duration: 0.12), value: isHeld)
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
