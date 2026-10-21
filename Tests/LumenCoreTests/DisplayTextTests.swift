import Foundation
import Testing
@testable import LumenCore

@Suite struct DisplayTextTests {
    @Test func videoSummaryFormatsResolutionDurationAndSize() {
        var video = makeVideo()
        video.width = 3840
        video.height = 2160
        video.duration = 102.4
        video.byteSize = 84 * 1_000_000
        #expect(DisplayText.summary(for: video) == "3840×2160 · 1:42 · 84 Mo")
    }

    @Test func videoSummaryUsesGigabytesAboveOneThousandMegabytes() {
        var video = makeVideo()
        video.width = 1920
        video.height = 1080
        video.duration = 3725
        video.byteSize = 1_500_000_000
        #expect(DisplayText.summary(for: video) == "1920×1080 · 62:05 · 1,5 Go")
    }

    @Test func playlistPositionIsOneBased() {
        #expect(DisplayText.playlistPosition(name: "Soirée", position: 1, count: 5) == "Playlist « Soirée » · 2/5")
    }

    @Test func heroCaptionMentionsPlaylistWhenPresent() {
        #expect(DisplayText.heroCaption(playlistName: nil) == "EN COURS")
        #expect(DisplayText.heroCaption(playlistName: "Soirée") == "EN COURS · PLAYLIST « SOIRÉE »")
    }
}
