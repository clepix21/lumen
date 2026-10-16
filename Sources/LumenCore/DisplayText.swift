import Foundation

/// French UI strings derived from the model.
public enum DisplayText {
    /// "3840×2160 · 1:42 · 84 Mo"
    public static func summary(for video: Video) -> String {
        "\(video.width)×\(video.height) · \(duration(video.duration)) · \(size(video.byteSize))"
    }

    /// "Playlist « Soirée » · 2/5" (`position` is zero-based).
    public static func playlistPosition(name: String, position: Int, count: Int) -> String {
        "Playlist « \(name) » · \(position + 1)/\(count)"
    }

    /// "EN COURS" or "EN COURS · PLAYLIST « SOIRÉE »"
    public static func heroCaption(playlistName: String?) -> String {
        guard let playlistName else { return "EN COURS" }
        return "EN COURS · PLAYLIST « \(playlistName.uppercased(with: Locale(identifier: "fr_FR"))) »"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "84 Mo", "1,5 Go"
    public static func size(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 1000 {
            return "\(Int(megabytes.rounded())) Mo"
        }
        let gigabytes = (megabytes / 1000 * 10).rounded() / 10
        let text = gigabytes.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(gigabytes))
            : String(gigabytes).replacingOccurrences(of: ".", with: ",")
        return "\(text) Go"
    }
}
