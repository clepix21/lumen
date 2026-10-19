import Foundation
import Testing
@testable import LumenCore

@Suite struct UpdateCheckerTests {
    func releaseJSON(tag: String) -> Data {
        Data("""
        {"tag_name": "\(tag)", "html_url": "https://github.com/clepix21/lumen/releases/tag/\(tag)",
         "draft": false, "prerelease": false, "name": "Lumen"}
        """.utf8)
    }

    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isVersion("0.4.0", newerThan: "0.3.0"))
        #expect(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.9"))
        #expect(UpdateChecker.isVersion("1.0", newerThan: "0.9.9"))
        #expect(UpdateChecker.isVersion("v0.4.0", newerThan: "0.3.0"))
        #expect(!UpdateChecker.isVersion("0.3.0", newerThan: "0.3.0"))
        #expect(!UpdateChecker.isVersion("0.3", newerThan: "0.3.0"))
        #expect(!UpdateChecker.isVersion("0.2.9", newerThan: "0.3.0"))
    }

    @Test func readsTheLatestRelease() throws {
        let release = try #require(UpdateChecker.release(from: releaseJSON(tag: "v0.4.0")))
        #expect(release.version == "0.4.0")
        #expect(release.pageURL.absoluteString == "https://github.com/clepix21/lumen/releases/tag/v0.4.0")
    }

    @Test func ignoresUnreadableResponses() {
        #expect(UpdateChecker.release(from: Data("{}".utf8)) == nil)
        #expect(UpdateChecker.release(from: Data("not json".utf8)) == nil)
    }

    @Test func reportsANewerRelease() async {
        let checker = UpdateChecker(fetch: { _ in releaseJSON(tag: "v0.4.0") })
        let release = await checker.newerRelease(than: "0.3.0")
        #expect(release?.version == "0.4.0")
    }

    @Test func staysQuietWhenUpToDate() async {
        let checker = UpdateChecker(fetch: { _ in releaseJSON(tag: "v0.3.0") })
        #expect(await checker.newerRelease(than: "0.3.0") == nil)
    }

    @Test func staysQuietWhenOffline() async {
        let checker = UpdateChecker(fetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await checker.newerRelease(than: "0.3.0") == nil)
    }

    @Test func asksGitHubForTheLatestRelease() async {
        let recorder = URLRecorder()
        let checker = UpdateChecker(fetch: { url in
            recorder.record(url)
            return releaseJSON(tag: "v0.3.0")
        })
        _ = await checker.newerRelease(than: "0.3.0")
        #expect(recorder.urls.map(\.absoluteString) == ["https://api.github.com/repos/clepix21/lumen/releases/latest"])
    }

    @Test func updateCheckIsOnByDefaultAndForOlderLibraries() throws {
        #expect(Settings().checkForUpdates == true)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"isMuted": true}"#.utf8))
        #expect(old.checkForUpdates == true)
    }
}

final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func record(_ url: URL) {
        lock.lock(); storage.append(url); lock.unlock()
    }

    var urls: [URL] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
