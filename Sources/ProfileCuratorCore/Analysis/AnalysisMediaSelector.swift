import Foundation
import ImageIO

public enum AnalysisMediaSelector {
    public static func faceMedia(from media: [MediaRecord], limit: Int = 3) -> [MediaRecord] {
        let usable = media
            .filter(\.usableFace)
            .sorted(by: isHigherQualityFace)
        let candidates = usable.isEmpty
            ? media.filter { $0.typedKind == .pfp }.sorted(by: isHigherQualityFace)
            : usable
        guard let best = candidates.first else { return [] }

        // Small faces inside screenshots can pass the general retention gate but
        // should not dilute face-presentation scoring when a true close-up exists.
        let focusedFaceFloor = max(0.08, best.largestFaceRatio * 0.25)
        let focused = candidates.filter { $0.largestFaceRatio >= focusedFaceFloor }
        return Array((focused.isEmpty ? [best] : focused).prefix(max(1, limit)))
    }

    public static func lifestyleMedia(from media: [MediaRecord], limit: Int = 3) -> [MediaRecord] {
        Array(media
            .filter { $0.typedKind == .moment }
            .filter(isCleanMomentPhoto)
            .prefix(max(1, limit)))
    }

    private static func isHigherQualityFace(_ left: MediaRecord, _ right: MediaRecord) -> Bool {
        let leftQuality = left.faceCaptureQuality ?? 0
        let rightQuality = right.faceCaptureQuality ?? 0
        if leftQuality != rightQuality { return leftQuality > rightQuality }
        if left.largestFaceRatio != right.largestFaceRatio {
            return left.largestFaceRatio > right.largestFaceRatio
        }
        return left.sourceSequence < right.sourceSequence
    }

    private static func isCleanMomentPhoto(_ media: MediaRecord) -> Bool {
        let url = URL(fileURLWithPath: media.filePath) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let analysis = try? VisionFixtureAnalyzer().analyze(image) else {
            return true
        }
        return MomentMediaCaptureValidator().isFullPhoto(observations: analysis.text)
    }
}
