import AVFoundation
import CoreVideo
import Foundation

/// Writes tiny solid-color clips for tests.
enum TestVideoFactory {
    struct WriterError: Error {}

    static func make(
        at url: URL, seconds: Double = 1, width: Int = 64, height: Int = 48,
        codec: AVVideoCodecType = .h264
    ) async throws {
        let fileType: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? WriterError() }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frameCount = Int(seconds * Double(fps))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw WriterError() }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw WriterError() }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!
            memset(base, Int32(frame * 4 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? WriterError() }
    }
}
