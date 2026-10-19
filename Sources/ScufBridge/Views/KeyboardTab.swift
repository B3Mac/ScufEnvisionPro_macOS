import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScufCore

struct KeyboardTab: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section {
                Text("When this profile's output is **Keyboard mode**, gamepad buttons and stick directions press these keys. The defaults match Astris's (Ryujinx's) default keyboard layout, so set Astris → Settings → Input → Player 1 → Input Device to **Keyboard** and it just works. Sticks become 8-way digital.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset to Astris / Ryujinx Defaults") {
                    profile.keyboardMap = .ryujinxDefault
                }
            }

            Section("Buttons") {
                ForEach(PadButton.allCases, id: \.self) { button in
                    OptionalKeyPicker(
                        title: "\(button.displayName)   (Switch \(button.switchName))",
                        code: Binding(
                            get: { profile.keyboardMap.buttons[button] },
                            set: { profile.keyboardMap.buttons[button] = $0 }
                        )
                    )
                }
            }

            Section("Left stick") {
                OptionalKeyPicker(title: "Up", code: $profile.keyboardMap.leftStick.up)
                OptionalKeyPicker(title: "Down", code: $profile.keyboardMap.leftStick.down)
                OptionalKeyPicker(title: "Left", code: $profile.keyboardMap.leftStick.left)
                OptionalKeyPicker(title: "Right", code: $profile.keyboardMap.leftStick.right)
            }

            Section("Right stick") {
                OptionalKeyPicker(title: "Up", code: $profile.keyboardMap.rightStick.up)
                OptionalKeyPicker(title: "Down", code: $profile.keyboardMap.rightStick.down)
                OptionalKeyPicker(title: "Left", code: $profile.keyboardMap.rightStick.left)
                OptionalKeyPicker(title: "Right", code: $profile.keyboardMap.rightStick.right)
            }

            Section {
                LabeledSlider(title: "Stick deflection that presses a direction", value: $profile.keyboardMap.stickThreshold, range: 0.2...0.9)
            }
        }
        .formStyle(.grouped)
    }
}

struct ProfileSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
                Picker("Output", selection: $profile.output) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text(outputHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Use when no linked app is in front (fallback profile)", isOn: Binding(
                    get: { model.config.fallbackProfileID == profile.id },
                    set: { if $0 { model.config.fallbackProfileID = profile.id } }
                ))
                Button("Make Active Now") { model.activate(profile.id) }
                    .disabled(model.config.activeProfileID == profile.id)
            }

            Section {
                if profile.linkedApps.isEmpty {
                    Text("No linked apps.").foregroundStyle(.secondary)
                }
                ForEach(profile.linkedApps, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(appName(bundleID))
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            profile.linkedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                                link(app.bundleIdentifier)
                            }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…") { link(chooseAppBundleID()) }
                }
            } header: {
                Text("Linked apps")
            } footer: {
                Text("When a linked app comes to the front, this profile turns on (if auto-switching is on in the menu bar).")
            }
        }
        .formStyle(.grouped)
    }

    private var outputHelp: String {
        switch profile.output {
        case .virtualGamepad:
            switch model.virtualPadStatus {
            case .active: return "Games see a virtual Xbox-layout controller with full analog sticks and triggers."
            case .starting: return "Starting the virtual gamepad…"
            case .unavailable(let reason): return reason
            }
        case .keyboard:
            return "Gamepad buttons and stick directions press the keys on the Keyboard Mode tab. Use this for Astris until the virtual gamepad is available."
        case .actionsOnly:
            return "Only key, macro, script, app, media, mouse and profile actions run. Gamepad mappings do nothing."
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func link(_ bundleID: String?) {
        guard let bundleID = bundleID, !profile.linkedApps.contains(bundleID) else { return }
        profile.linkedApps.append(bundleID)
    }

    private func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func chooseAppBundleID() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
