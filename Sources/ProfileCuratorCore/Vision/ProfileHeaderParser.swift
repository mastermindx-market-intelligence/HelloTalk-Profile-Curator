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

    /// Profile pages contain many standalone counters that look like ages
    /// (translations, points, dates). For persisted age evidence, require the
    /// age token to be spatially tied to the visible @username header.
    public func bestHeaderAge(
        in observations: [OCRObservation],
        minimumConfidence: Float = 0.65
    ) -> ProfileAgeMatch? {
        guard let username = observations
            .filter({
                $0.confidence >= 0.55
                    && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
            })
            .min(by: { $0.bounds.minY < $1.bounds.minY }) else {
            return nil
        }
        return ageMatches(in: observations, minimumConfidence: minimumConfidence).first { match in
            let verticalDistance = abs(match.source.bounds.center.y - username.bounds.center.y)
            let isNearHeaderLine = match.source.bounds.minY <= username.bounds.maxY + 0.055
            return verticalDistance <= 0.12 && isNearHeaderLine
        }
    }
}

public struct ProfileDisplayNameParser: Sendable {
    public init() {}

    public func displayName(in observations: [OCRObservation]) -> String? {
        guard let username = observations
            .filter({ $0.confidence >= 0.55 && $0.text.trimmingCharacters(in: .whitespaces).hasPrefix("@") })
            .min(by: { $0.bounds.minY < $1.bounds.minY }) else {
            return nil
        }

        return observations.compactMap { observation -> (String, Double, Double)? in
            let value = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard observation.confidence >= 0.55,
                  !value.isEmpty,
                  !value.hasPrefix("@"),
                  observation.bounds.maxY <= username.bounds.minY + 0.012 else { return nil }
            let verticalGap = username.bounds.minY - observation.bounds.maxY
            let horizontalGap = abs(username.bounds.minX - observation.bounds.minX)
            guard verticalGap >= -0.012, verticalGap <= 0.09, horizontalGap <= 0.16,
                  value.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) == nil,
                  value.range(of: #"^[\d\s%]+$"#, options: .regularExpression) == nil else { return nil }
            return (value, verticalGap, horizontalGap)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 < $1.2
        }
        .first?.0
    }
}

public struct OCRAnchorMatcher: Sendable {
    public init() {}

    public func contains(anchor: String, in combinedOCRText: String) -> Bool {
        if combinedOCRText.localizedCaseInsensitiveContains(anchor) {
            return true
        }

        let knownAlternatives: [String: [String]] = [
            "AI Photo Gift": ["Al Photo Gift"],
            "Moments": ["Momopts"]
        ]
        return knownAlternatives[anchor, default: []].contains {
            combinedOCRText.localizedCaseInsensitiveContains($0)
        }
    }
}
