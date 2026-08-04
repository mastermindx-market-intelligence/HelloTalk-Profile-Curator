import Foundation

public struct LocationBadgeSample: Hashable, Sendable {
    public let rawText: String
    public let cityText: String
    public let countryText: String
    public let confidence: Float
    public let bounds: NormalizedRect

    public init(
        rawText: String,
        cityText: String,
        countryText: String,
        confidence: Float,
        bounds: NormalizedRect
    ) {
        self.rawText = rawText
        self.cityText = cityText
        self.countryText = countryText
        self.confidence = confidence
        self.bounds = bounds
    }
}

public struct NearbyCountSample: Hashable, Sendable {
    public let count: Int
    public let confidence: Float
    public let bounds: NormalizedRect

    public init(count: Int, confidence: Float, bounds: NormalizedRect) {
        self.count = count
        self.confidence = confidence
        self.bounds = bounds
    }
}

public struct TemporalLocationResolution: Sendable {
    public let location: NormalizedLocation?
    public let source: LocationBadgeSample?
    public let nearbyCountsIgnored: [Int]
    public let framesExamined: Int

    public init(
        location: NormalizedLocation?,
        source: LocationBadgeSample?,
        nearbyCountsIgnored: [Int],
        framesExamined: Int
    ) {
        self.location = location
        self.source = source
        self.nearbyCountsIgnored = nearbyCountsIgnored
        self.framesExamined = framesExamined
    }
}

public struct RotatingLocationBadgeParser: Sendable {
    private static let locationExpression = try! NSRegularExpression(
        // Vision observed "Shenyang, China16 58pm" for the real tiny badge:
        // the leading 1 is an OCR artifact and the colon was read as a space.
        pattern: #"^(.{2,48}?),\s*([A-Z][A-Z ]{1,30}?)\s*[|IL1]?\d{1,2}\s*(?::|\s)\s*\d{2}\s*(?:AM|PM)$"#,
        options: [.caseInsensitive]
    )
    private static let nearbyExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(\d{1,5})\s+PEOPLE\s+NEARBY(?:$|\s)"#,
        options: [.caseInsensitive]
    )
    private static let badgeLocationWithoutTimeExpression = try! NSRegularExpression(
        pattern: #"^[•·]?\s*(.{2,48}?),\s*(CHINA|UNITED STATES|USA|AUSTRALIA|UNITED KINGDOM|UK|CANADA)\s*$"#,
        options: [.caseInsensitive]
    )

    private let locationNormalizer = LocationNormalizer()

    public init() {}

    public func locationSamples(in observations: [OCRObservation], minimumConfidence: Float = 0.45) -> [LocationBadgeSample] {
        observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence else { return nil }
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let timedMatch = Self.locationExpression.firstMatch(in: text, range: range)
            let badgeOnlyMatch = isPlausibleBadgeBounds(observation.bounds)
                ? Self.badgeLocationWithoutTimeExpression.firstMatch(in: text, range: range)
                : nil
            guard let match = timedMatch ?? badgeOnlyMatch,
                let cityRange = Range(match.range(at: 1), in: text),
                let countryRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }

            return LocationBadgeSample(
                rawText: text,
                cityText: String(text[cityRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                countryText: String(text[countryRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: observation.confidence,
                bounds: observation.bounds
            )
        }
    }

    private func isPlausibleBadgeBounds(_ bounds: NormalizedRect) -> Bool {
        bounds.minX >= 0.22
            && bounds.minY >= 0.10
            && bounds.maxY <= 0.45
            && bounds.height <= 0.09
    }

    public func nearbySamples(in observations: [OCRObservation], minimumConfidence: Float = 0.45) -> [NearbyCountSample] {
        observations.compactMap { observation in
            guard observation.confidence >= minimumConfidence else { return nil }
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard
                let match = Self.nearbyExpression.firstMatch(in: text, range: range),
                let countRange = Range(match.range(at: 1), in: text),
                let count = Int(text[countRange])
            else {
                return nil
            }
            return NearbyCountSample(count: count, confidence: observation.confidence, bounds: observation.bounds)
        }
    }

    public func resolve(frames: [[OCRObservation]]) -> TemporalLocationResolution {
        let locations = frames.flatMap { locationSamples(in: $0) }
        let nearbyCounts = frames.flatMap { nearbySamples(in: $0) }.map(\.count)
        let best = locations.max { lhs, rhs in lhs.confidence < rhs.confidence }

        guard let best else {
            return TemporalLocationResolution(
                location: nil,
                source: nil,
                nearbyCountsIgnored: nearbyCounts,
                framesExamined: frames.count
            )
        }

        return TemporalLocationResolution(
            location: locationNormalizer.normalize("\(best.cityText), \(best.countryText)"),
            source: best,
            nearbyCountsIgnored: nearbyCounts,
            framesExamined: frames.count
        )
    }
}
