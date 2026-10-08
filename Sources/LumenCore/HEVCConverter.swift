import AVFoundation

/// Re-encodes a video to HEVC with the hardware encoder; the lock screen only plays HEVC reliably.
public enum HEVCConverter {
    public struct ExportUnavailable: Error {}

    /// Writes to a hidden partial file first, so `destination` only ever holds a complete video.
    public static func convert(_ source: URL, to destination: URL) async throws {
        let fileManager = FileManager.default
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent).partial.mov")
        try? fileManager.removeItem(at: partial)
        do {
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: source),
                                                     presetName: AVAssetExportPresetHEVCHighestQuality) else {
                throw ExportUnavailable()
            }
            try await session.export(to: partial, as: .mov)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }
}
