import AppKit
import IOKit.hid
import ScufCore

func scufLog(_ message: String) {
    NSLog("ScufBridge: %@", message as NSString)
}

/// Reads and writes ~/Library/Application Support/ScufBridge/config.json.
struct ConfigStore {
    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("ScufBridge", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent("config.json") }

    func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return .makeDefault() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let backup = directory.appendingPathComponent("config-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            scufLog("could not read config (\(error)); kept a copy at \(backup.path)")
            return .makeDefault()
        }
    }

    func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            scufLog("could not save config: \(error)")
        }
    }
}

enum Permissions {
    /// Needed to send keys, text, media keys and mouse clicks.
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Needed to record macros and to block the controller's built-in media keys.
    static var inputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    static func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
