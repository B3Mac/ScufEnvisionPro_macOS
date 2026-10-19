import Foundation

/// A semantic version such as `0.1.0`, `v1.2` or `0.2.0-beta.3`.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let numbers: [Int]
    public let prerelease: [String]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        // Build metadata ("+abc") never affects ordering.
        let withoutBuild = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let main = parts.first, !main.isEmpty else { return nil }
        let numbers = main.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.numbers = numbers.map { $0! }
        if parts.count > 1 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !identifiers.contains(where: \.isEmpty) else { return nil }
            prerelease = identifiers
        } else {
            prerelease = []
        }
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let a = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let b = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if a != b { return a < b }
        }
        // Same numbers: a pre-release sorts before the release.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false):
            for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
                switch (Int(a), Int(b)) {
                case let (x?, y?): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a < b
                }
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The fields we use from GitHub's "list releases" API.
public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: String
    public let draft: Bool
    public let prerelease: Bool

    public init(tagName: String, htmlURL: String, draft: Bool = false, prerelease: Bool = false) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

public struct UpdateCandidate: Sendable {
    public let release: GitHubRelease
    public let version: AppVersion
}

public enum UpdatePolicy {
    /// The newest release that is newer than `current`, if any. Pre-releases count only when the
    /// running build is itself a pre-release (beta testers keep getting betas).
    public static func newest(from releases: [GitHubRelease], current: AppVersion) -> UpdateCandidate? {
        let includePrereleases = current.isPrerelease
        return releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) }
            .compactMap { release in AppVersion(release.tagName).map { UpdateCandidate(release: release, version: $0) } }
            .filter { includePrereleases || !$0.version.isPrerelease }
            .filter { current < $0.version }
            .max { $0.version < $1.version }
    }
}
