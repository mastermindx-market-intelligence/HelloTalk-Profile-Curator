import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public enum WindowCaptureError: Error, LocalizedError, Sendable {
    case windowNoLongerAvailable(CGWindowID)
    case windowNotOnScreen(CGWindowID)
    case invalidWindowSize(CGSize)
    case invalidBurstFrameCount(Int)
    case windowResized(expected: CGSize, actual: CGSize)

    public var errorDescription: String? {
        switch self {
        case .windowNoLongerAvailable(let windowID):
            "Window \(windowID) is no longer available. Locate iPhone Mirroring again."
        case .windowNotOnScreen(let windowID):
            "Window \(windowID) is not currently visible on screen."
        case .invalidWindowSize(let size):
            "The mirrored window has an invalid size: \(Int(size.width))×\(Int(size.height))."
        case .invalidBurstFrameCount(let count):
            "A capture burst needs at least one frame; received \(count)."
        case .windowResized(let expected, let actual):
            "The mirrored window resized from \(Int(expected.width))×\(Int(expected.height)) to \(Int(actual.width))×\(Int(actual.height)). Start a new calibrated session."
        }
    }
}

public struct WindowGeometryGuard: Sendable {
    public let baselineWindowID: CGWindowID
    public let baselineSize: CGSize
    public let tolerancePoints: CGFloat

    public init(frame: CapturedWindowFrame, tolerancePoints: CGFloat = 1) {
        baselineWindowID = frame.windowID
        baselineSize = frame.windowFrame.size
        self.tolerancePoints = max(0, tolerancePoints)
    }

    public func validate(_ frame: CapturedWindowFrame) throws {
        guard frame.windowID == baselineWindowID else {
            throw WindowCaptureError.windowNoLongerAvailable(baselineWindowID)
        }
        guard abs(frame.windowFrame.width - baselineSize.width) <= tolerancePoints,
              abs(frame.windowFrame.height - baselineSize.height) <= tolerancePoints else {
            throw WindowCaptureError.windowResized(expected: baselineSize, actual: frame.windowFrame.size)
        }
    }
}

public struct CapturedWindowFrame: @unchecked Sendable {
    public let image: CGImage
    public let windowID: CGWindowID
    public let windowFrame: CGRect
    public let capturedAt: Date

    public init(image: CGImage, windowID: CGWindowID, windowFrame: CGRect, capturedAt: Date) {
        self.image = image
        self.windowID = windowID
        self.windowFrame = windowFrame
        self.capturedAt = capturedAt
    }
}

public struct WindowCaptureService: Sendable {
    public init() {}

    static func targetPixelSize(for windowFrame: CGRect) -> CGSize {
        CGSize(
            width: max(1, windowFrame.width.rounded()),
            height: max(1, windowFrame.height.rounded())
        )
    }

    public func capture(windowID: CGWindowID) async throws -> CapturedWindowFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw WindowCaptureError.windowNoLongerAvailable(windowID)
        }
        guard window.isOnScreen else {
            throw WindowCaptureError.windowNotOnScreen(windowID)
        }
        guard window.frame.width >= 1, window.frame.height >= 1 else {
            throw WindowCaptureError.invalidWindowSize(window.frame.size)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        let targetSize = Self.targetPixelSize(for: window.frame)
        configuration.width = Int(targetSize.width)
        configuration.height = Int(targetSize.height)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return CapturedWindowFrame(
            image: image,
            windowID: windowID,
            windowFrame: window.frame,
            capturedAt: Date()
        )
    }

    /// Captures enough frames to observe short-lived, rotating UI labels without
    /// interpreting any one frame as authoritative.
    public func captureBurst(
        windowID: CGWindowID,
        frameCount: Int = 5,
        intervalMilliseconds: Int = 700
    ) async throws -> [CapturedWindowFrame] {
        guard frameCount > 0 else {
            throw WindowCaptureError.invalidBurstFrameCount(frameCount)
        }

        var frames: [CapturedWindowFrame] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            if index > 0 {
                try await Task.sleep(for: .milliseconds(max(0, intervalMilliseconds)))
            }
            try Task.checkCancellation()
            frames.append(try await capture(windowID: windowID))
        }

        return frames
    }
}
