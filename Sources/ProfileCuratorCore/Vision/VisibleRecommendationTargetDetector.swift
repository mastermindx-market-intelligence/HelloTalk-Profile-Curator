import Foundation

public struct VisibleRecommendationTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let displayedAge: Int
    public let ageEvidence: RecommendationAgeCandidate
    public let photoPoint: NormalizedPoint
    public let safePhotoRegion: NormalizedRect
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        displayedAge: Int,
        ageEvidence: RecommendationAgeCandidate,
        photoPoint: NormalizedPoint,
        safePhotoRegion: NormalizedRect,
        confidence: Float
    ) {
        self.id = id
        self.displayedAge = displayedAge
        self.ageEvidence = ageEvidence
        self.photoPoint = photoPoint
        self.safePhotoRegion = safePhotoRegion
        self.confidence = confidence
    }

    public var plannedAction: PlannedAction {
        PlannedAction(
            kind: .openRecommendationCard,
            point: photoPoint,
            requiredSafeRegion: safePhotoRegion,
            rationale: "Dry-run visible-card photo proposal for displayed age \(displayedAge)"
        )
    }
}

public struct VisibleRecommendationTargetDetector: Sendable {
    private let ageParser = RecommendationAgeParser()

    public init() {}

    public func targets(in observations: [OCRObservation]) -> [VisibleRecommendationTarget] {
        guard let galleryAnchor = observations
            .filter({ $0.text.localizedCaseInsensitiveContains("Suggested for You") })
            .max(by: { $0.confidence < $1.confidence }) else {
            return []
        }

        return ageParser.allAges(in: observations).compactMap { age in
            guard age.bounds.minY >= galleryAnchor.bounds.maxY - 0.01,
                  age.bounds.minY < 0.94 else {
                return nil
            }

            let xOffset = min(0.075, max(0.045, age.bounds.width * 1.3))
            let yOffset = min(0.075, max(0.045, age.bounds.height * 1.5))
            let point = NormalizedPoint(
                x: age.bounds.center.x - xOffset,
                y: age.bounds.minY - yOffset
            )
            guard point.isInsideUnitSquare,
                  point.y >= galleryAnchor.bounds.maxY + 0.015,
                  point.y < 0.87 else {
                return nil
            }

            let safeRegion = centeredRegion(around: point, width: 0.13, height: 0.11)
            return VisibleRecommendationTarget(
                displayedAge: age.age,
                ageEvidence: age,
                photoPoint: point,
                safePhotoRegion: safeRegion,
                confidence: min(age.confidence, galleryAnchor.confidence)
            )
        }
        .sorted {
            if $0.photoPoint.x != $1.photoPoint.x { return $0.photoPoint.x < $1.photoPoint.x }
            return $0.photoPoint.y < $1.photoPoint.y
        }
    }

    private func centeredRegion(
        around point: NormalizedPoint,
        width: Double,
        height: Double
    ) -> NormalizedRect {
        let x = min(max(0, point.x - width / 2), 1 - width)
        let y = min(max(0, point.y - height / 2), 1 - height)
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }
}

public struct SocialControlExclusionDetector: Sendable {
    private static let controlAnchors = [
        "sayhi": "Say Hi",
        "follow": "Follow",
        "gift": "Gift",
        "like": "Like",
        "freetochat": "Free to Chat",
        "shopnow": "Shop Now",
        "download": "Download"
    ]

    public init() {}

    public func exclusions(in observations: [OCRObservation]) -> [ExclusionZone] {
        observations.compactMap { observation in
            let key = observation.text
                .lowercased()
                .filter { $0.isLetter }
            guard let label = Self.controlAnchors[key] else { return nil }

            let horizontalPadding = label == "Say Hi" || label == "Follow" ? 0.12 : 0.06
            let verticalPadding = 0.022
            let bounds = expanded(
                observation.bounds,
                horizontal: horizontalPadding,
                vertical: verticalPadding
            )
            return ExclusionZone(label: "Dynamic control: \(label)", bounds: bounds)
        }
    }

    private func expanded(
        _ bounds: NormalizedRect,
        horizontal: Double,
        vertical: Double
    ) -> NormalizedRect {
        let minX = max(0, bounds.minX - horizontal)
        let minY = max(0, bounds.minY - vertical)
        let maxX = min(1, bounds.maxX + horizontal)
        let maxY = min(1, bounds.maxY + vertical)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
