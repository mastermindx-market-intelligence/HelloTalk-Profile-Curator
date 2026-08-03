import CoreGraphics
import Foundation
@preconcurrency import Vision

public enum VisionFixtureAnalyzerError: Error, LocalizedError {
    case noImage

    public var errorDescription: String? {
        switch self {
        case .noImage:
            "The selected file could not be decoded as an image."
        }
    }
}

public struct VisionFixtureAnalyzer: Sendable {
    public init() {}

    public func analyze(_ image: CGImage) throws -> FixtureAnalysis {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["en-US", "zh-Hans"]
        textRequest.customWords = [
            "INFJ", "INTJ", "INFP", "INTP", "ENFP", "ENTP", "ENFJ",
            "Personal Info", "Suggested for You", "Moments", "About Me"
        ]

        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([textRequest, faceRequest])

        let text = (textRequest.results ?? []).compactMap { observation -> OCRObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRObservation(
                text: candidate.string,
                confidence: candidate.confidence,
                bounds: Self.topLeftRect(fromVisionRect: observation.boundingBox)
            )
        }

        let faceObservations: [VNFaceObservation] = faceRequest.results ?? [VNFaceObservation]()
        var faces: [DetectedFace] = []
        for observation in faceObservations {
            faces.append(DetectedFace(
                bounds: Self.topLeftRect(fromVisionRect: observation.boundingBox),
                captureQuality: observation.faceCaptureQuality,
                hasLandmarks: observation.landmarks != nil
            ))
        }

        return FixtureAnalysis(
            imageWidth: image.width,
            imageHeight: image.height,
            text: text,
            faces: faces
        )
    }

    private static func topLeftRect(fromVisionRect rect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: rect.minX,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
