import AVFoundation
import ScreenCaptureKit

struct RecordingOptions: Sendable {
    var frameRate: Int
    var quality: VideoQuality
    var codec: VideoCodec
    var container: VideoContainer
    var showsCursor: Bool
    var captureSystemAudio: Bool
    var captureMicrophone: Bool
    var microphoneID: String?

    /// Encoded output size for a source of the given native pixel size (even, within encoder limits).
    func outputSize(for native: CGSize) -> CGSize {
        var width = native.width * quality.resolutionScale
        var height = native.height * quality.resolutionScale

        let maxDimension: CGFloat = codec == .h264 ? 4096 : 8192
        let maxPixels: CGFloat = codec == .h264 ? 4096 * 2304 : 8192 * 4320
        var scale = min(1, maxDimension / max(width, height))
        scale = min(scale, sqrt(maxPixels / max(width * height, 1)))
        width *= scale
        height *= scale

        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded(.down) * 2) }
        return CGSize(width: even(width), height: even(height))
    }

    func bitrate(for size: CGSize) -> Int {
        let bps = size.width * size.height * Double(frameRate) * quality.bitsPerPixel * codec.bitrateFactor
        return Int(min(max(bps, 2_000_000), 240_000_000))
    }
}

enum RecorderError: LocalizedError {
    case cannotCreateWriter(String)
    case noFramesCaptured
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateWriter(let reason): "Could not start recording: \(reason)"
        case .noFramesCaptured: "No video frames were captured, so nothing was saved."
        case .writerFailed(let reason): "Saving the recording failed: \(reason)"
        }
    }
}

/// Records a ScreenCaptureKit stream straight into a hardware-encoded movie file.
///
/// All writer state is confined to `queue`, which is also the sample handler queue for every
/// stream output, so no locking is needed and frames are never copied.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ScreenCapture.recorder", qos: .userInteractive)

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var isFinishing = false
    private var lastVideoSample: CMSampleBuffer?
    private var temporaryURL: URL?

    /// Called on an arbitrary queue when the system stops the stream (e.g. "Stop Sharing" in the menu bar).
    var onUnexpectedStop: (@Sendable (Error) -> Void)?

    func start(target: CaptureTarget, options: RecordingOptions, outputURL: URL) async throws {
        let size = options.outputSize(for: target.nativePixelSize)
        let tempURL = StorageManager.temporaryURL(for: outputURL)
        temporaryURL = tempURL

        let (writer, videoInput, audioInput, micInput) = try Self.makeWriter(url: tempURL, size: size, options: options)

        let config = SCStreamConfiguration()
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        config.queueDepth = 6
        // Native YUV 4:2:0 feeds the hardware encoder without any colour conversion.
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = options.showsCursor
        config.scalesToFit = true
        config.preservesAspectRatio = true
        if let rect = target.sourceRect { config.sourceRect = rect }

        config.capturesAudio = audioInput != nil
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = micInput != nil
        if micInput != nil, let id = options.microphoneID, !id.isEmpty {
            config.microphoneCaptureDeviceID = id
        }

        let stream = SCStream(filter: target.filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if audioInput != nil { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
            if micInput != nil { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            throw RecorderError.cannotCreateWriter(error.localizedDescription)
        }

        queue.sync {
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.micInput = micInput
            self.sessionStarted = false
            self.isFinishing = false
        }
        self.stream = stream

        do {
            try await stream.startCapture()
        } catch {
            queue.sync { self.reset() }
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: tempURL)
            throw RecorderError.cannotCreateWriter(error.localizedDescription)
        }
    }

    /// Creates a started AVAssetWriter with hardware-encoded video and optional AAC audio tracks.
    static func makeWriter(url tempURL: URL, size: CGSize, options: RecordingOptions)
        throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInput?, AVAssetWriterInput?) {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: tempURL, fileType: options.container.fileType)
        } catch {
            throw RecorderError.cannotCreateWriter(error.localizedDescription)
        }

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: options.bitrate(for: size),
            AVVideoExpectedSourceFrameRateKey: options.frameRate,
            AVVideoMaxKeyFrameIntervalKey: options.frameRate * 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if options.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: options.codec.avCodec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw RecorderError.cannotCreateWriter("The video encoder does not support \(Int(size.width))×\(Int(size.height)).")
        }
        writer.add(videoInput)

        func makeAudioInput(channels: Int, bitrate: Int) -> AVAssetWriterInput? {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: bitrate,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            return input
        }
        let audioInput = options.captureSystemAudio ? makeAudioInput(channels: 2, bitrate: 192_000) : nil
        let micInput = options.captureMicrophone ? makeAudioInput(channels: 1, bitrate: 128_000) : nil

        guard writer.startWriting() else {
            throw RecorderError.cannotCreateWriter(writer.error?.localizedDescription ?? "Unknown writer error")
        }
        return (writer, videoInput, audioInput, micInput)
    }

    /// Stops capturing, finalises the file and moves it to `outputURL`.
    func stop(moveTo outputURL: URL) async throws -> URL {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        let tempURL = temporaryURL
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.finishWriting { result in continuation.resume(with: result) }
            }
        }
        guard let tempURL else { throw RecorderError.noFramesCaptured }
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
        return outputURL
    }

    // Must run on `queue`.
    private func finishWriting(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard let writer, !isFinishing else {
            completion(.failure(RecorderError.noFramesCaptured))
            return
        }
        isFinishing = true

        guard sessionStarted, writer.status == .writing else {
            let reason = writer.error?.localizedDescription
            writer.cancelWriting()
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            reset()
            completion(.failure(reason.map { RecorderError.writerFailed($0) } ?? RecorderError.noFramesCaptured))
            return
        }

        // ScreenCaptureKit only delivers frames when the screen changes. Re-append the last frame
        // at "now" so a static ending isn't cut off.
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if let last = lastVideoSample, let videoInput, videoInput.isReadyForMoreMediaData,
           now > last.presentationTimeStamp,
           let copy = try? CMSampleBuffer(copying: last, withNewTiming: [
               CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: now, decodeTimeStamp: .invalid),
           ]) {
            videoInput.append(copy)
        }
        lastVideoSample = nil
        writer.endSession(atSourceTime: now)

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()

        nonisolated(unsafe) let finishedWriter = writer
        writer.finishWriting { [self] in
            queue.async {
                let error = finishedWriter.error
                let succeeded = finishedWriter.status == .completed
                self.reset()
                if succeeded {
                    completion(.success(()))
                } else {
                    if let url = self.temporaryURL { try? FileManager.default.removeItem(at: url) }
                    completion(.failure(RecorderError.writerFailed(error?.localizedDescription ?? "Unknown error")))
                }
            }
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        lastVideoSample = nil
        sessionStarted = false
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isFinishing, sampleBuffer.isValid, let writer, writer.status == .writing else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let rawStatus = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: rawStatus) == .complete,
                  let videoInput
            else { return }

            if !sessionStarted {
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                sessionStarted = true
            }
            // Drop the frame rather than block if the encoder is momentarily busy.
            if videoInput.isReadyForMoreMediaData, videoInput.append(sampleBuffer) {
                lastVideoSample = sampleBuffer
            }

        case .audio:
            guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)

        case .microphone:
            guard sessionStarted, let micInput, micInput.isReadyForMoreMediaData else { return }
            micInput.append(sampleBuffer)

        @unknown default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onUnexpectedStop?(error)
    }
}
