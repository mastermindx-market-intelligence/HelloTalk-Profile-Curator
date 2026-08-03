import Foundation

public struct OCRObservation: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    public let bounds: NormalizedRect

    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        bounds: NormalizedRect
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.bounds = bounds
    }
}

public struct DetectedFace: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let bounds: NormalizedRect
    public let captureQuality: Float?
    public let hasLandmarks: Bool

    public init(
        id: UUID = UUID(),
        bounds: NormalizedRect,
        captureQuality: Float?,
        hasLandmarks: Bool
    ) {
        self.id = id
        self.bounds = bounds
        self.captureQuality = captureQuality
        self.hasLandmarks = hasLandmarks
    }
}

public struct FixtureAnalysis: Sendable {
    public let imageWidth: Int
    public let imageHeight: Int
    public let text: [OCRObservation]
    public let faces: [DetectedFace]

    public init(imageWidth: Int, imageHeight: Int, text: [OCRObservation], faces: [DetectedFace]) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.text = text
        self.faces = faces
    }
}
