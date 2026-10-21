import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImportError: Error, Equatable {
    case notPlayable
    case copyFailed

    public var frenchMessage: String {
        switch self {
        case .notPlayable: "Ce fichier n'est pas une vidéo lisible."
        case .copyFailed: "La copie de la vidéo a échoué."
        }
    }
}

/// Copies videos into Lumen's storage and reads what the UI needs about them.
public struct VideoImporter: Sendable {
    public let paths: LumenPaths
    /// Shorter videos are rejected: they cannot loop meaningfully and can break playback.
    public let minimumDuration: Double

    private static let chunkSize = 4 * 1024 * 1024

    public init(paths: LumenPaths, minimumDuration: Double = 0.1) {
        self.paths = paths
        self.minimumDuration = minimumDuration
    }

    public func fileURL(for video: Video) -> URL {
        paths.videos.appendingPathComponent(video.fileName)
    }

    public func thumbnailURL(for id: UUID) -> URL {
        paths.thumbnails.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Validates the source, copies it (reporting progress from 0 to 1), then reads
    /// metadata and writes a thumbnail. Leaves nothing behind on failure.
    public func importVideo(from source: URL, progress: @Sendable (Double) -> Void) async throws -> Video {
        let sourceAsset = AVURLAsset(url: source)
        guard (try? await sourceAsset.load(.isPlayable)) == true,
              let tracks = try? await sourceAsset.loadTracks(withMediaType: .video),
              !tracks.isEmpty,
              let sourceDuration = try? await sourceAsset.load(.duration).seconds,
              sourceDuration.isFinite, sourceDuration >= minimumDuration else {
            throw ImportError.notPlayable
        }

        try paths.createDirectories()
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"
        let destination = paths.videos.appendingPathComponent(fileName)
        let thumbnail = thumbnailURL(for: id)

        do {
            let byteSize = try copy(from: source, to: destination, progress: progress)
            let asset = AVURLAsset(url: destination)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ImportError.notPlayable
            }
            let (naturalSize, transform, formats) = try await track.load(.naturalSize, .preferredTransform, .formatDescriptions)
            let size = naturalSize.applying(transform)
            let duration = try await asset.load(.duration).seconds
            let isHEVC = formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC }
            // The thumbnail is cosmetic: a playable video is kept even if it cannot be made.
            do {
                try await writeThumbnail(for: asset, duration: duration, to: thumbnail)
            } catch {
                try? FileManager.default.removeItem(at: thumbnail)
            }

            return Video(
                id: id,
                name: source.deletingPathExtension().lastPathComponent,
                fileName: fileName,
                duration: duration,
                width: Int(abs(size.width).rounded()),
                height: Int(abs(size.height).rounded()),
                byteSize: byteSize,
                isHEVC: isHEVC,
                importedAt: Date()
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: thumbnail)
            throw (error as? ImportError) ?? ImportError.copyFailed
        }
    }

    public func deleteFiles(for video: Video) throws {
        let fileManager = FileManager.default
        for url in [fileURL(for: video), thumbnailURL(for: video.id)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func copy(from source: URL, to destination: URL, progress: @Sendable (Double) -> Void) throws -> Int64 {
        let fileManager = FileManager.default
        let total = (try fileManager.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard fileManager.createFile(atPath: destination.path, contents: nil) else { throw ImportError.copyFailed }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }

        var copied: Int64 = 0
        progress(0)
        while let chunk = try reader.read(upToCount: Self.chunkSize), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            if total > 0 {
                progress(min(Double(copied) / Double(total), 1))
            }
        }
        progress(1)
        return copied
    }

    private func writeThumbnail(for asset: AVURLAsset, duration: Double, to url: URL) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let time = CMTime(seconds: max(duration * 0.1, 0), preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImportError.copyFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.copyFailed }
    }
}
