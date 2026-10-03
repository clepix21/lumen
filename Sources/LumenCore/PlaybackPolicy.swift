/// Everything outside Lumen that affects whether the wallpaper should play.
public struct PlaybackConditions: Equatable, Sendable {
    public var isOccluded = false
    public var isScreenAsleep = false
    public var isScreenLocked = false
    public var isSessionActive = true
    public var isOnBattery = false
    public var userPaused = false

    public init() {}
}

public enum PlaybackPolicy {
    /// Plays only when someone can see the wallpaper and no setting asks to save energy.
    public static func shouldPlay(_ conditions: PlaybackConditions, settings: Settings) -> Bool {
        if conditions.userPaused || conditions.isScreenAsleep || conditions.isScreenLocked {
            return false
        }
        if !conditions.isSessionActive {
            return false
        }
        if conditions.isOccluded && settings.pauseWhenOccluded {
            return false
        }
        if conditions.isOnBattery && settings.pauseOnBattery {
            return false
        }
        return true
    }
}
