import Foundation
import Testing
@testable import LumenCore

@Suite struct PlaylistCursorTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func startsAtFirstInOrder() {
        let cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        #expect(cursor.current == a)
        #expect(cursor.position == 0)
        #expect(cursor.count == 3)
    }

    @Test func nextAdvancesAndWraps() {
        var cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        cursor.next()
        #expect(cursor.current == b)
        cursor.next()
        cursor.next()
        #expect(cursor.current == a)
    }

    @Test func previousWrapsBackwards() {
        var cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        cursor.previous()
        #expect(cursor.current == c)
    }

    @Test func shuffleIsPermutationAndDeterministic() {
        let ids = (0..<20).map { _ in UUID() }
        let first = PlaylistCursor(videoIDs: ids, shuffle: true, seed: 42)
        let second = PlaylistCursor(videoIDs: ids, shuffle: true, seed: 42)
        #expect(first.order == second.order)
        #expect(Set(first.order) == Set(ids))
        #expect(first.order.count == ids.count)
        #expect(first.order != ids)
    }

    @Test func shuffleReshufflesOnWrap() {
        let ids = (0..<20).map { _ in UUID() }
        var cursor = PlaylistCursor(videoIDs: ids, shuffle: true, seed: 7)
        let firstPass = cursor.order
        for _ in 0..<ids.count { cursor.next() }
        #expect(cursor.position == 0)
        #expect(Set(cursor.order) == Set(ids))
        #expect(cursor.order != firstPass)
    }

    @Test func removeCurrentMovesToFollowing() {
        var cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        cursor.next()
        cursor.remove(b)
        #expect(cursor.current == c)
        #expect(cursor.count == 2)
    }

    @Test func removeLastInOrderWrapsToFirst() {
        var cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        cursor.previous()
        cursor.remove(c)
        #expect(cursor.current == a)
    }

    @Test func removeOtherKeepsCurrent() {
        var cursor = PlaylistCursor(videoIDs: [a, b, c], shuffle: false, seed: 1)
        cursor.next()
        cursor.remove(a)
        #expect(cursor.current == b)
    }

    @Test func removeLastRemainingGivesNil() {
        var cursor = PlaylistCursor(videoIDs: [a], shuffle: false, seed: 1)
        cursor.remove(a)
        #expect(cursor.current == nil)
    }

    @Test func emptyCursorIsNil() {
        var cursor = PlaylistCursor(videoIDs: [], shuffle: false, seed: 1)
        #expect(cursor.current == nil)
        cursor.next()
        cursor.previous()
        #expect(cursor.current == nil)
    }
}
