import AVFoundation
import CoreVideo
import Foundation

/// Writes tiny solid-color clips for tests.
enum TestVideoFactory {
    struct WriterError: Error {}

    static func make(
        at url: URL, seconds: Double = 1, width: Int = 64, height: Int = 48,
        codec: AVVideoCodecType = .h264, withAudio: Bool = false
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
        let audioInput = withAudio ? AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ]) : nil
        if let audioInput {
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
        }
        guard writer.startWriting() else { throw writer.error ?? WriterError() }
        writer.startSession(atSourceTime: .zero)
        if let audioInput {
            try await writeSilence(to: audioInput, seconds: seconds)
        }

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

    /// Appends `seconds` of silent 16-bit mono PCM, encoded to AAC by the writer.
    private static func writeSilence(to input: AVAssetWriterInput, seconds: Double) async throws {
        let sampleRate = 44_100
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw WriterError() }

        let chunk = 4096
        var written = 0
        let total = Int(seconds * Double(sampleRate))
        while written < total {
            let frames = min(chunk, total - written)
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: frames * 2,
                                               blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                               dataLength: frames * 2, flags: kCMBlockBufferAssureMemoryNowFlag,
                                               blockBufferOut: &block)
            guard let block else { throw WriterError() }
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: frames * 2)
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
                presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &sample
            )
            guard let sample else { throw WriterError() }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            input.append(sample)
            written += frames
        }
        input.markAsFinished()
    }
}
