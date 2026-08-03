import Foundation

public struct ProfileAgeMatch: Hashable, Sendable {
    public let age: Int
    public let source: OCRObservation
    public let usedBadgeArtifactCorrection: Bool

    public init(age: Int, source: OCRObservation, usedBadgeArtifactCorrection: Bool) {
        self.age = age
        self.source = source
        self.usedBadgeArtifactCorrection = usedBadgeArtifactCorrection
    }
}

public struct ProfileHeaderParser: Sendable {
    private static let plainAge = try! NSRegularExpression(pattern: #"^(1[8-9]|[2-9][0-9])\+?$"#)
    private static let badgeArtifactAge = try! NSRegularExpression(pattern: #"^[QO09](1[8-9]|[2-9][0-9])$"#)

    public init() {}

    public func ageMatches(
        in observations: [OCRObservation],
        minimumConfidence: Float = 0.65
    ) -> [ProfileAgeMatch] {
        observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence else { return nil }
            let normalized = observation.text
                .uppercased()
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

            if let match = Self.badgeArtifactAge.firstMatch(in: normalized, range: fullRange),
               let ageRange = Range(match.range(at: 1), in: normalized),
               let age = Int(normalized[ageRange]) {
                return ProfileAgeMatch(age: age, source: observation, usedBadgeArtifactCorrection: true)
            }

            if let match = Self.plainAge.firstMatch(in: normalized, range: fullRange),
               let ageRange = Range(match.range(at: 1), in: normalized),
               let age = Int(normalized[ageRange]) {
                return ProfileAgeMatch(age: age, source: observation, usedBadgeArtifactCorrection: false)
            }

            return nil
        }
        .sorted { lhs, rhs in
            if lhs.usedBadgeArtifactCorrection != rhs.usedBadgeArtifactCorrection {
                return lhs.usedBadgeArtifactCorrection
            }
            return lhs.source.confidence > rhs.source.confidence
        }
    }

    public func bestAge(in observations: [OCRObservation], minimumConfidence: Float = 0.65) -> ProfileAgeMatch? {
        ageMatches(in: observations, minimumConfidence: minimumConfidence).first
    }
}

public struct OCRAnchorMatcher: Sendable {
    public init() {}

    public func contains(anchor: String, in combinedOCRText: String) -> Bool {
        if combinedOCRText.localizedCaseInsensitiveContains(anchor) {
            return true
        }

        let knownAlternatives: [String: [String]] = [
            "AI Photo Gift": ["Al Photo Gift"]
        ]
        return knownAlternatives[anchor, default: []].contains {
            combinedOCRText.localizedCaseInsensitiveContains($0)
        }
    }
}
