import Foundation

public struct RecommendationAgeCandidate: Hashable, Sendable {
    public let age: Int
    public let bounds: NormalizedRect
    public let confidence: Float

    public init(age: Int, bounds: NormalizedRect, confidence: Float) {
        self.age = age
        self.bounds = bounds
        self.confidence = confidence
    }
}

public struct RecommendationAgeParser: Sendable {
    private static let expression = try! NSRegularExpression(pattern: #"(?<!\d)(1[8-9]|2[0-1])(?!\d)"#)

    public init() {}

    public func candidates(in observations: [OCRObservation], minimumConfidence: Float = 0.72) -> [RecommendationAgeCandidate] {
        observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence else { return nil }
            let range = NSRange(observation.text.startIndex..<observation.text.endIndex, in: observation.text)
            guard
                let match = Self.expression.firstMatch(in: observation.text, range: range),
                let matchRange = Range(match.range(at: 1), in: observation.text),
                let age = Int(observation.text[matchRange])
            else {
                return nil
            }

            return RecommendationAgeCandidate(age: age, bounds: observation.bounds, confidence: observation.confidence)
        }
    }
}
