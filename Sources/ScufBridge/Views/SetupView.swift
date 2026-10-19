import AppKit
import SwiftUI
import ScufCore

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets ScufBridge send keys, typed text, media keys and mouse clicks (and Keyboard mode).",
                    granted: model.accessibilityGranted,
                    request: Permissions.requestAccessibility,
                    open: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Lets ScufBridge record macros and stop G2–G4 from changing the volume on their own.",
                    granted: model.inputMonitoringGranted,
                    request: Permissions.requestInputMonitoring,
                    open: Permissions.openInputMonitoringSettings
                )
            } header: {
                Text("Permissions")
            } footer: {
                Text("If a permission stays off after you allow it, quit and reopen ScufBridge. Rebuilding an unsigned copy can reset permissions; see the README.")
            }

            Section("Virtual gamepad") {
                switch model.virtualPadStatus {
                case .active:
                    Label("Active: games and emulators see a virtual Xbox-layout controller.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .starting:
                    Label("Starting…", systemImage: "hourglass")
                case .unavailable(let reason):
                    Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Until then, use a profile with **Keyboard mode** output for Astris. Every G-key, paddle, macro and script action works either way.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Switch profiles with the front app", isOn: $model.config.autoSwitch)
                if let front = model.frontAppBundleID {
                    LabeledContent("Last front app", value: front)
                }
                HStack {
                    Button("Show Config File") { model.revealConfig() }
                    Button("Open Script Log") { model.revealScriptLog() }
                }
            }

            Section {
                LabeledContent("Installed version", value: updates.currentVersion)
                Toggle("Check for updates once a day", isOn: $model.config.checkForUpdates)
                HStack {
                    Button("Check Now") { updates.check() }
                        .disabled(updates.state == .checking)
                    Button("All Releases") { NSWorkspace.shared.open(UpdateChecker.releasesPage) }
                    Spacer()
                    Text(updateStatus)
                        .foregroundStyle(.secondary)
                }
                if case .available = updates.state {
                    Button("Download the Update") { updates.openAvailableUpdate() }
                        .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("ScufBridge only asks GitHub for its release list. It never downloads or installs anything on its own.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup & Permissions")
        .onAppear { model.refreshPermissions() }
    }

    private var updateStatus: String {
        switch updates.state {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "You're up to date."
        case .available(let version, _): return "Version \(version) is available."
        case .failed(let reason): return "Couldn't check: \(reason)"
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Allow…") {
                    request()
                    open()
                }
            }
        }
    }
}
