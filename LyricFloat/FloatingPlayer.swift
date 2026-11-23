import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import SwiftUI
import UIKit
import os

@MainActor
final class FloatingPlayer: NSObject, ObservableObject, AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate {

    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    let displayLayer = AVSampleBufferDisplayLayer()
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    private static let frameSize = CGSize(width: 720, height: 320)
    private var controller: AVPictureInPictureController?
    private var possibilityObservation: NSKeyValueObservation?
    private nonisolated let playbackPaused = OSAllocatedUnfairLock(initialState: true)
    private var audioSessionActive = false

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        if isSupported {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.requiresLinearPlayback = true
            self.controller = controller
            possibilityObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
                [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.isPossible = self?.controller?.isPictureInPicturePossible == true
                }
            }
        }
    }

    func toggle() {
        guard let controller, !isStarting else { return }
        errorMessage = nil
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        guard controller.isPictureInPicturePossible else { return }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audio.setActive(true)
            audioSessionActive = true
            isStarting = true
            controller.startPictureInPicture()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPaused(_ paused: Bool) {
        let changed = playbackPaused.withLock { previous in
            guard previous != paused else { return false }
            previous = paused
            return true
        }
        if changed { controller?.invalidatePlaybackState() }
    }

    func render(current: String, next: String?, theme: LyricTheme, lyricFont: LyricFont) {
        guard let buffer = Self.makeFrame(current: current, next: next, theme: theme, lyricFont: lyricFont) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(buffer)
    }

    private static func makeFrame(current: String, next: String?, theme: LyricTheme,
                                  lyricFont: LyricFont) -> CMSampleBuffer? {
        let width = Int(frameSize.width)
        let height = Int(frameSize.height)
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        theme.panelColor.setFill()
        context.fill(CGRect(origin: .zero, size: frameSize))

        let textWidth = frameSize.width - 104
        let currentLine = fittedLine(current, width: textWidth, maxHeight: 148,
                                     maxSize: 55, minSize: 27, font: lyricFont, weight: .semibold,
                                     color: UIColor(lyricHex: theme.text))
        let nextLine = next.flatMap { text in
            text.isEmpty ? nil : fittedLine(text, width: textWidth, maxHeight: 70,
                                            maxSize: 32, minSize: 19, font: lyricFont, weight: .medium,
                                            color: UIColor(lyricHex: theme.muted))
        }
        let gap: CGFloat = nextLine == nil ? 0 : 18
        let contentHeight = currentLine.height + gap + (nextLine?.height ?? 0)
        let top = (frameSize.height - contentHeight) / 2
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        currentLine.text.draw(with: CGRect(x: 52, y: top, width: textWidth, height: currentLine.height),
                              options: options, context: nil)
        if let nextLine {
            let nextTop = top + currentLine.height + gap
            nextLine.text.draw(with: CGRect(x: 52, y: nextTop, width: textWidth, height: nextLine.height),
                               options: options, context: nil)
        }

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                       decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           let item = CFArrayGetValueAtIndex(attachments, 0) {
            let dictionary = unsafeBitCast(item, to: CFMutableDictionary.self)
            let displayImmediately: CFBoolean = kCFBooleanTrue
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(displayImmediately).toOpaque())
        }
        return sample
    }

    private static func fittedLine(_ text: String, width: CGFloat, maxHeight: CGFloat,
                                   maxSize: Int, minSize: Int, font: LyricFont, weight: UIFont.Weight,
                                   color: UIColor) -> (text: NSAttributedString, height: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        for size in stride(from: maxSize, through: minSize, by: -1) {
            let line = NSAttributedString(string: text, attributes: [
                .font: font.uiFont(size: CGFloat(size), weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ])
            let bounds = line.boundingRect(with: CGSize(width: width, height: 5000),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                           context: nil)
            let height = ceil(bounds.height)
            if height <= maxHeight || size == minSize {
                return (line, min(height, maxHeight))
            }
        }

        return (NSAttributedString(string: text), maxHeight)
    }

    private func releaseAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isStarting = false
            self?.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isStarting = false
            self?.isActive = false
            self?.releaseAudioSession()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let message = "Couldn’t start Picture in Picture. \(error.localizedDescription)"
        Task { @MainActor [weak self] in
            self?.isStarting = false
            self?.isActive = false
            self?.releaseAudioSession()
            self?.errorMessage = message
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // The overlay follows Spotify's read-only playback state.
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        playbackPaused.withLock { $0 }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

struct LyricsPreview: UIViewRepresentable {
    let player: FloatingPlayer
    let theme: LyricTheme

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(displayLayer: player.displayLayer)
        view.backgroundColor = theme.panelColor
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.backgroundColor = theme.panelColor
    }

    final class PreviewView: UIView {
        private let displayLayer: AVSampleBufferDisplayLayer

        init(displayLayer: AVSampleBufferDisplayLayer) {
            self.displayLayer = displayLayer
            super.init(frame: .zero)
            layer.addSublayer(displayLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
