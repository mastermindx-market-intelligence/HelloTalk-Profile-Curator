import CoreGraphics
import Foundation

public struct PhotoExtractionRegion: Hashable, Sendable {
    public let bounds: NormalizedRect
    public let confidence: Double

    public init(bounds: NormalizedRect, confidence: Double) {
        self.bounds = bounds
        self.confidence = min(1, max(0, confidence))
    }
}

public struct ViewerPhotoRegionDetector: Sendable {
    public init() {}

    public func region(for screen: DetectedScreenKind, observations: [OCRObservation]) -> PhotoExtractionRegion? {
        switch screen {
        case .pfpViewer:
            let actionTop = observations
                .filter {
                    $0.text.localizedCaseInsensitiveContains("AI Photo Gift")
                        || $0.text.localizedCaseInsensitiveContains("Avatar Effect")
                        || $0.text.localizedCaseInsensitiveContains("Save")
                }
                .map(\.bounds.minY)
                .min() ?? 0.82
            let bottom = min(0.84, max(0.45, actionTop - 0.015))
            return PhotoExtractionRegion(
                bounds: NormalizedRect(x: 0.015, y: 0.055, width: 0.97, height: bottom - 0.055),
                confidence: actionTop < 0.82 ? 0.92 : 0.7
            )
        case .momentViewer:
            return PhotoExtractionRegion(
                bounds: NormalizedRect(x: 0.015, y: 0.07, width: 0.97, height: 0.76),
                confidence: 0.65
            )
        default:
            return nil
        }
    }
}

public struct WindowPhotoCropper: Sendable {
    public init() {}

    public func crop(_ image: CGImage, to normalized: NormalizedRect) -> CGImage? {
        guard normalized.isValidNormalizedRect else { return nil }
        let pixelRect = CGRect(
            x: (normalized.minX * Double(image.width)).rounded(),
            y: ((1 - normalized.maxY) * Double(image.height)).rounded(),
            width: (normalized.width * Double(image.width)).rounded(),
            height: (normalized.height * Double(image.height)).rounded()
        )
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return nil }
        return image.cropping(to: pixelRect)
    }

    public func faceCrop(
        _ image: CGImage,
        faceBounds: NormalizedRect,
        padding: Double = 0.35
    ) -> CGImage? {
        let horizontal = faceBounds.width * padding
        let vertical = faceBounds.height * padding
        let minX = max(0, faceBounds.minX - horizontal)
        let minY = max(0, faceBounds.minY - vertical)
        let maxX = min(1, faceBounds.maxX + horizontal)
        let maxY = min(1, faceBounds.maxY + vertical)
        return crop(
            image,
            to: NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )
    }
}
