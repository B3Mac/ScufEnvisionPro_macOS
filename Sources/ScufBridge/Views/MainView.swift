import SwiftUI
import ScufCore

enum SidebarItem: Hashable {
    case profile(UUID)
    case controller
    case setup
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SidebarItem? = .controller

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Profiles") {
                    ForEach(model.config.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == model.config.activeProfileID,
                            isFallback: profile.id == model.config.fallbackProfileID
                        )
                        .tag(SidebarItem.profile(profile.id))
                        .contextMenu {
                            Button("Make Active") { model.activate(profile.id) }
                            Button("Duplicate") {
                                if let id = model.duplicateProfile(profile.id) { selection = .profile(id) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { delete(profile.id) }
                                .disabled(model.config.profiles.count < 2)
                        }
                    }
                }
                Section("Device") {
                    Label("Controller", systemImage: "gamecontroller").tag(SidebarItem.controller)
                    Label("Setup & Permissions", systemImage: "checkmark.shield").tag(SidebarItem.setup)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 4) {
                    Button {
                        selection = .profile(model.addProfile())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New profile")
                    Button {
                        if case .profile(let id)? = selection { delete(id) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Delete profile")
                    .disabled(!isProfileSelected || model.config.profiles.count < 2)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            switch selection {
            case .profile(let id)?:
                if let binding = model.profileBinding(id) {
                    ProfileEditor(profile: binding)
                } else {
                    placeholder
                }
            case .controller?:
                MonitorView()
            case .setup?:
                SetupView()
            case nil:
                placeholder
            }
        }
    }

    private var isProfileSelected: Bool {
        if case .profile? = selection { return true }
        return false
    }

    private var placeholder: some View {
        Text("Select a profile").foregroundStyle(.secondary)
    }

    private func delete(_ id: UUID) {
        guard model.config.profiles.count > 1 else { return }
        model.deleteProfile(id)
        selection = .controller
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let isFallback: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                Text(profile.output.displayName + (isFallback ? " · fallback" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.green)
                    .help("Active profile")
            }
        }
    }
}

struct ProfileEditor: View {
    @Binding var profile: Profile

    var body: some View {
        TabView {
            ButtonsTab(profile: $profile)
                .tabItem { Text("Buttons") }
            SticksTab(profile: $profile)
                .tabItem { Text("Sticks & Triggers") }
            KeyboardTab(profile: $profile)
                .tabItem { Text("Keyboard Mode") }
            ProfileSettingsTab(profile: $profile)
                .tabItem { Text("Profile") }
        }
        .padding()
        .navigationTitle(profile.name)
    }
}
