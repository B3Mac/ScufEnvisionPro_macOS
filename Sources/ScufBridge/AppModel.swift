import AppKit
import Combine
import ServiceManagement
import SwiftUI
import ScufCore

/// Live controller state, kept separate so only the views that show it redraw 30 times a second.
final class LiveModel: ObservableObject {
    @Published var snapshot = LiveSnapshot()
}

/// App state shared by the menu bar and the settings window. Used from the main thread only.
final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            service.update(config: config)
            if config.checkForUpdates != oldValue.checkForUpdates { applyUpdateSetting() }
            scheduleSave()
        }
    }

    let live = LiveModel()
    let updates = UpdateChecker()
    @Published private(set) var virtualPadStatus: VirtualGamepad.Status = .starting
    @Published private(set) var accessibilityGranted = Permissions.accessibility
    @Published private(set) var inputMonitoringGranted = Permissions.inputMonitoring
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var frontAppBundleID: String?
    @Published var lastScriptOutput = ""
    /// Pressing a controller button selects it in the Buttons editor.
    @Published var followController = true

    let service: ControllerService
    private let store = ConfigStore()
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    private var pendingSave: DispatchWorkItem?

    init() {
        let loaded = ConfigStore().load()
        config = loaded
        service = ControllerService(config: loaded)

        service.onProfileRequest = { [weak self] target in
            DispatchQueue.main.async { self?.switchProfile(target) }
        }
        service.start()
        service.virtualPad.start { [weak self] status in
            DispatchQueue.main.async { self?.virtualPadStatus = status }
        }

        timers.append(Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.refreshLive()
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontAppChanged(note)
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.pendingSave?.cancel()
            self.store.save(self.config)
        })

        if !Permissions.accessibility { Permissions.requestAccessibility() }
        applyUpdateSetting()
    }

    private func applyUpdateSetting() {
        if config.checkForUpdates {
            updates.startAutomaticChecks()
        } else {
            updates.stopAutomaticChecks()
        }
    }

    // MARK: Live state

    private func refreshLive() {
        let snapshot = service.currentSnapshot()
        if snapshot != live.snapshot { live.snapshot = snapshot }
    }

    func refreshPermissions() {
        let accessibility = Permissions.accessibility
        let inputMonitoring = Permissions.inputMonitoring
        if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
        if inputMonitoring != inputMonitoringGranted { inputMonitoringGranted = inputMonitoring }
    }

    var outputStatus: (text: String, ok: Bool) {
        switch config.activeProfile.output {
        case .virtualGamepad:
            switch virtualPadStatus {
            case .active: return ("Virtual gamepad active", true)
            case .starting: return ("Starting virtual gamepad…", false)
            case .unavailable: return ("Virtual gamepad unavailable: gamepad mappings are off", false)
            }
        case .keyboard:
            return accessibilityGranted
                ? ("Keyboard mode", true)
                : ("Keyboard mode needs Accessibility permission", false)
        case .actionsOnly:
            return ("Actions only", true)
        }
    }

    // MARK: Profiles

    func profileBinding(_ id: UUID) -> Binding<Profile>? {
        guard config.profiles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.config.profiles.first { $0.id == id } ?? Profile(name: "Missing")
            },
            set: { [weak self] newValue in
                guard let self = self, let index = self.config.profiles.firstIndex(where: { $0.id == id }) else { return }
                self.config.profiles[index] = newValue
            }
        )
    }

    func profileName(_ id: UUID) -> String? {
        config.profile(id: id)?.name
    }

    func switchProfile(_ target: ProfileTarget) {
        config.activeProfileID = config.resolve(target)
    }

    func activate(_ id: UUID) {
        config.activeProfileID = id
    }

    @discardableResult
    func addProfile(_ template: ProfileTemplate = .blank) -> UUID {
        let profile = template.makeProfile()
        config.profiles.append(profile)
        return profile.id
    }

    @discardableResult
    func duplicateProfile(_ id: UUID) -> UUID? {
        guard var copy = config.profile(id: id) else { return nil }
        copy.id = UUID()
        copy.name += " copy"
        copy.linkedApps = []
        config.profiles.append(copy)
        return copy.id
    }

    func deleteProfile(_ id: UUID) {
        guard config.profiles.count > 1 else { return }
        var updated = config
        updated.profiles.removeAll { $0.id == id }
        if updated.activeProfileID == id { updated.activeProfileID = updated.profiles[0].id }
        if updated.fallbackProfileID == id { updated.fallbackProfileID = updated.profiles[0].id }
        config = updated
    }

    private func frontAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }
        frontAppBundleID = bundleID
        guard config.autoSwitch else { return }
        let target = config.profileID(forBundleID: bundleID) ?? config.fallbackProfileID
        if target != config.activeProfileID { config.activeProfileID = target }
    }

    // MARK: Misc

    func testScript(_ command: String) {
        lastScriptOutput = "Running…"
        ScriptRunner.capture(command) { [weak self] output in
            DispatchQueue.main.async { self?.lastScriptOutput = output }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            scufLog("launch at login: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func revealConfig() {
        store.save(config)
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    func revealScriptLog() {
        if !FileManager.default.fileExists(atPath: ScriptRunner.logURL.path) {
            FileManager.default.createFile(atPath: ScriptRunner.logURL.path, contents: nil)
        }
        NSWorkspace.shared.open(ScriptRunner.logURL)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = config
        let store = self.store
        let item = DispatchWorkItem { store.save(snapshot) }
        pendingSave = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
    }
}
