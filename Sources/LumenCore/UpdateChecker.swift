import Foundation

/// Asks GitHub whether a newer Lumen release exists. One anonymous request to the public API.
public struct UpdateChecker: Sendable {
    public struct Release: Equatable, Sendable {
        /// Version without the leading "v", e.g. "0.4.0".
        public let version: String
        /// The release page, where the dmg can be downloaded.
        public let pageURL: URL
    }

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/clepix21/lumen/releases/latest")!

    private let fetch: @Sendable (URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data = UpdateChecker.download) {
        self.fetch = fetch
    }

    /// The latest release if it is newer than `currentVersion`; `nil` when up to date or offline.
    public func newerRelease(than currentVersion: String) async -> Release? {
        guard let data = try? await fetch(Self.latestReleaseURL),
              let release = Self.release(from: data),
              Self.isVersion(release.version, newerThan: currentVersion) else { return nil }
        return release
    }

    public static func release(from data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: stripped(tag), pageURL: page)
    }

    /// Compares dotted versions number by number ("0.10.0" is newer than "0.9.9").
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    @Sendable public static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func stripped(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private static func numbers(_ version: String) -> [Int] {
        stripped(version).split(separator: ".").map { Int($0) ?? 0 }
    }
}
