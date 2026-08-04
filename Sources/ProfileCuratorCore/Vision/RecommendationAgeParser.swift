import Foundation

public struct RecommendationAgeCandidate: Hashable, Sendable {
    public let age: Int
    public let bounds: NormalizedRect
    public let confidence: Float
    public let usedBadgeArtifactCorrection: Bool

    public init(
        age: Int,
        bounds: NormalizedRect,
        confidence: Float,
        usedBadgeArtifactCorrection: Bool = false
    ) {
        self.age = age
        self.bounds = bounds
        self.confidence = confidence
        self.usedBadgeArtifactCorrection = usedBadgeArtifactCorrection
    }
}

public struct RecommendationAgeParser: Sendable {
    private static let plainAge = try! NSRegularExpression(
        pattern: #"^(?:AGE\s*)?(1[8-9]|[2-9][0-9])(?:\s*(?:YEARS?\s*OLD|Y/O))?$"#,
        options: [.caseInsensitive]
    )
    private static let badgeArtifactAge = try! NSRegularExpression(pattern: #"^[QO09](1[8-9]|[2-9][0-9])$"#)

    public init() {}

    public func candidates(in observations: [OCRObservation], minimumConfidence: Float = 0.72) -> [RecommendationAgeCandidate] {
        allAges(in: observations, minimumConfidence: minimumConfidence).filter {
            ProfileEligibilityPolicy.adultTargetAges.contains($0.age)
                || ProfileEligibilityPolicy.primaryMBTIAgeException.contains($0.age)
        }
    }

    public func allAges(in observations: [OCRObservation], minimumConfidence: Float = 0.72) -> [RecommendationAgeCandidate] {
        observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence else { return nil }
            let trimmed = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

            if let match = Self.badgeArtifactAge.firstMatch(in: trimmed.uppercased(), range: range),
                let matchRange = Range(match.range(at: 1), in: trimmed),
               let age = Int(trimmed[matchRange]) {
                return RecommendationAgeCandidate(
                    age: age,
                    bounds: observation.bounds,
                    confidence: observation.confidence,
                    usedBadgeArtifactCorrection: true
                )
            }

            guard
                let match = Self.plainAge.firstMatch(in: trimmed, range: range),
                let matchRange = Range(match.range(at: 1), in: trimmed),
                let age = Int(trimmed[matchRange])
            else {
                return nil
            }

            return RecommendationAgeCandidate(
                age: age,
                bounds: observation.bounds,
                confidence: observation.confidence
            )
        }
    }
}
