import AppKit
import ScufCore

/// Checks GitHub Releases for a newer version. It never downloads or installs anything:
/// when an update exists, the menu offers to open its release page.
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    static let releasesURL = URL(string: "https://api.github.com/repos/B3Mac/ScufEnvisionPro_macOS/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/B3Mac/ScufEnvisionPro_macOS/releases")!

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Checks now, then once a day.
    func startAutomaticChecks() {
        guard timer == nil else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        guard state != .checking else { return }
        guard let current = AppVersion(currentVersion) else {
            state = .failed("This build has no version number.")
            return
        }
        state = .checking
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ScufBridge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: State
            if let error = error {
                result = .failed(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failed("GitHub returned HTTP \(http.statusCode).")
            } else if let data = data, let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) {
                if let found = UpdatePolicy.newest(from: releases, current: current),
                   let url = URL(string: found.release.htmlURL) {
                    result = .available(version: found.version.description, url: url)
                } else {
                    result = .upToDate
                }
            } else {
                result = .failed("Couldn't read GitHub's release list.")
            }
            DispatchQueue.main.async {
                self?.state = result
                self?.lastChecked = Date()
            }
        }.resume()
    }

    func openAvailableUpdate() {
        if case .available(_, let url) = state {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(Self.releasesPage)
        }
    }
}
