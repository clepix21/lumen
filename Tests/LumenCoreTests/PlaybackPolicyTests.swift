import Testing
@testable import LumenCore

@Suite struct PlaybackPolicyTests {
    @Test func playsByDefault() {
        #expect(PlaybackPolicy.shouldPlay(PlaybackConditions(), settings: Settings()))
    }

    @Test func userPauseWins() {
        var conditions = PlaybackConditions()
        conditions.userPaused = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
    }

    @Test func screenAsleepPauses() {
        var conditions = PlaybackConditions()
        conditions.isScreenAsleep = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
    }

    @Test func screenLockedPauses() {
        var conditions = PlaybackConditions()
        conditions.isScreenLocked = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
    }

    @Test func inactiveSessionPauses() {
        var conditions = PlaybackConditions()
        conditions.isSessionActive = false
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
    }

    @Test func occlusionPausesOnlyWhenSettingOn() {
        var conditions = PlaybackConditions()
        conditions.isOccluded = true
        var settings = Settings()
        settings.pauseWhenOccluded = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: settings))
        settings.pauseWhenOccluded = false
        #expect(PlaybackPolicy.shouldPlay(conditions, settings: settings))
    }

    @Test func batteryPausesOnlyWhenSettingOn() {
        var conditions = PlaybackConditions()
        conditions.isOnBattery = true
        var settings = Settings()
        settings.pauseOnBattery = false
        #expect(PlaybackPolicy.shouldPlay(conditions, settings: settings))
        settings.pauseOnBattery = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: settings))
    }

    @Test func resumesAfterWake() {
        var conditions = PlaybackConditions()
        conditions.isScreenAsleep = true
        #expect(!PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
        conditions.isScreenAsleep = false
        #expect(PlaybackPolicy.shouldPlay(conditions, settings: Settings()))
    }
}
