import Foundation

public struct CustomSearchResultTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let profileKey: String
    public let displayName: String
    public let location: NormalizedLocation
    public let photoPoint: NormalizedPoint
    public let safePhotoRegion: NormalizedRect
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        profileKey: String,
        displayName: String,
        location: NormalizedLocation,
        photoPoint: NormalizedPoint,
        safePhotoRegion: NormalizedRect,
        confidence: Float
    ) {
        self.id = id
        self.profileKey = profileKey
        self.displayName = displayName
        self.location = location
        self.photoPoint = photoPoint
        self.safePhotoRegion = safePhotoRegion
        self.confidence = confidence
    }

    public var plannedAction: PlannedAction {
        PlannedAction(
            kind: .openCustomSearchResult,
            point: photoPoint,
            requiredSafeRegion: safePhotoRegion,
            rationale: "Open Custom Search avatar for \(displayName) in \(location.city ?? location.province ?? location.country ?? "target location")"
        )
    }
}

public struct CustomSearchResultTargetDetector: Sendable {
    private let locationNormalizer = LocationNormalizer()

    public init() {}

    public func targets(in observations: [OCRObservation]) -> [CustomSearchResultTarget] {
        let locations = observations.compactMap { observation -> (OCRObservation, NormalizedLocation)? in
            guard observation.confidence >= 0.55,
                  observation.bounds.minY >= 0.14,
                  observation.bounds.maxY <= 0.94,
                  looksLikeResultLocation(observation.text) else { return nil }
            let location = locationNormalizer.normalize(observation.text)
            guard location.city != nil || location.province != nil || location.country != nil,
                  location.tier <= 5 else { return nil }
            return (observation, location)
        }

        return locations.compactMap { locationObservation, location in
            guard let name = bestName(above: locationObservation, observations: observations) else { return nil }
            let y = max(0.16, locationObservation.bounds.center.y - 0.045)
            let point = NormalizedPoint(x: 0.105, y: y)
            let safe = NormalizedRect(
                x: 0.035,
                y: max(0.10, y - 0.055),
                width: 0.14,
                height: 0.11
            )
            let compactName = name.text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
            let place = (location.city ?? location.province ?? location.country ?? "location")
                .lowercased().filter { $0.isLetter || $0.isNumber }
            return CustomSearchResultTarget(
                profileKey: "\(compactName)-\(place)",
                displayName: name.text.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location,
                photoPoint: point,
                safePhotoRegion: safe,
                confidence: min(name.confidence, locationObservation.confidence)
            )
        }
        .uniqued(by: \CustomSearchResultTarget.profileKey)
        .sorted { $0.photoPoint.y < $1.photoPoint.y }
    }

    private func looksLikeResultLocation(_ text: String) -> Bool {
        text.range(
            of: #"\b[A-Z][A-Z .'-]{1,40},\s*(?:CHINA|UNITED STATES|USA|AUSTRALIA|UNITED KINGDOM|UK|CANADA)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil || text.contains("中国") || text.contains("中國")
    }

    private func bestName(
        above location: OCRObservation,
        observations: [OCRObservation]
    ) -> OCRObservation? {
        let excluded = Set([
            "cn", "en", "chinese", "english", "active", "search", "custom search",
            "female", "male", "all", "age", "country", "city"
        ])
        return observations.filter { observation in
            let value = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = value.lowercased()
            let verticalGap = location.bounds.minY - observation.bounds.maxY
            return observation.confidence >= 0.55
                && verticalGap >= -0.01 && verticalGap <= 0.105
                && observation.bounds.minX >= 0.17
                && observation.bounds.minX <= 0.62
                && abs(observation.bounds.minX - location.bounds.minX) <= 0.18
                && value.count >= 2 && value.count <= 40
                && !excluded.contains(normalized)
                && value.range(of: #"^[\p{L}\p{N}_ .'-]+$"#, options: .regularExpression) != nil
        }.max {
            let lhsGap = location.bounds.minY - $0.bounds.maxY
            let rhsGap = location.bounds.minY - $1.bounds.maxY
            return lhsGap > rhsGap
        }
    }
}

public struct CustomSearchInteractionPlanner: Sendable {
    public init() {}

    public func searchAction(in observations: [OCRObservation]) -> PlannedAction? {
        guard let anchor = observations
            .filter({
                $0.confidence >= 0.65
                    && $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare("Search") == .orderedSame
                    && $0.bounds.minY >= 0.20
                    && $0.bounds.maxY <= 0.90
            })
            .max(by: { $0.confidence < $1.confidence }) else { return nil }
        let padding = 0.035
        let minX = max(0, anchor.bounds.minX - padding)
        let maxX = min(1, anchor.bounds.maxX + padding)
        let minY = max(0, anchor.bounds.minY - 0.02)
        let maxY = min(1, anchor.bounds.maxY + 0.02)
        let region = NormalizedRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        return PlannedAction(
            kind: .refreshCustomSearch,
            point: anchor.bounds.center,
            requiredSafeRegion: region,
            rationale: "Refresh Custom Search from the exact Search button OCR anchor"
        )
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
