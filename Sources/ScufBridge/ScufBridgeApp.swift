import AppKit
import SwiftUI
import ScufCore

@main
struct ScufBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
                .environmentObject(model.live)
        } label: {
            MenuBarLabel(live: model.live)
        }
        .menuBarExtraStyle(.menu)

        Window("ScufBridge", id: "main") {
            MainView()
                .environmentObject(model)
                .environmentObject(model.live)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1080, height: 720)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var live: LiveModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("didShowWelcome") private var didShowWelcome = false

    var body: some View {
        Image(systemName: live.snapshot.connected ? "gamecontroller.fill" : "gamecontroller")
            .onAppear {
                guard !didShowWelcome else { return }
                didShowWelcome = true
                DispatchQueue.main.async {
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
    }
}

private struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(live.snapshot.connected ? "SCUF Envision Pro connected" : "Controller not connected")
        Text(model.outputStatus.text)
        Divider()
        Picker("Profile", selection: $model.config.activeProfileID) {
            ForEach(model.config.profiles) { profile in
                Text(profile.name).tag(profile.id)
            }
        }
        Toggle("Switch profiles with the front app", isOn: $model.config.autoSwitch)
        Divider()
        Button("Open ScufBridge…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit ScufBridge") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
