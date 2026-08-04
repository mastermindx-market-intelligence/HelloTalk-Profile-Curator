import Foundation

public struct VisibleRecommendationTarget: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let profileKey: String
    public let displayName: String?
    public let displayedAge: Int?
    public let ageEvidence: RecommendationAgeCandidate?
    public let photoPoint: NormalizedPoint
    public let safePhotoRegion: NormalizedRect
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        profileKey: String,
        displayName: String? = nil,
        displayedAge: Int?,
        ageEvidence: RecommendationAgeCandidate?,
        photoPoint: NormalizedPoint,
        safePhotoRegion: NormalizedRect,
        confidence: Float
    ) {
        self.id = id
        self.profileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.displayName = displayName
        self.displayedAge = displayedAge
        self.ageEvidence = ageEvidence
        self.photoPoint = photoPoint
        self.safePhotoRegion = safePhotoRegion
        self.confidence = confidence
    }

    public var plannedAction: PlannedAction {
        let ageDescription = displayedAge.map { "displayed age \($0)" } ?? "age unavailable"
        return PlannedAction(
            kind: .openRecommendationCard,
            point: photoPoint,
            requiredSafeRegion: safePhotoRegion,
            rationale: "Dry-run visible-card photo proposal for \(profileKey), \(ageDescription)"
        )
    }
}

public struct VisibleRecommendationTargetDetector: Sendable {
    private let ageParser = RecommendationAgeParser()

    private struct AgeAssociation {
        let nameIndex: Int
        let ageIndex: Int
        let distance: Double
    }

    public init() {}

    public func targets(in observations: [OCRObservation]) -> [VisibleRecommendationTarget] {
        guard let galleryAnchor = observations
            .filter({ $0.text.localizedCaseInsensitiveContains("Suggested for You") })
            .max(by: { $0.confidence < $1.confidence }) else {
            return []
        }

        let ages = ageParser.allAges(in: observations).filter {
            $0.bounds.minY >= galleryAnchor.bounds.maxY - 0.01 && $0.bounds.minY < 0.94
        }
        let names = candidateNames(
            in: observations,
            below: galleryAnchor,
            alignedWith: ages
        )

        let associations = oneToOneAgeAssociations(names: names, ages: ages)
        let associatedAgeIndexes = Set(associations.values)
        var targets: [VisibleRecommendationTarget] = names.enumerated().compactMap { nameIndex, name in
            let ageIndex = associations[nameIndex]
            let age = ageIndex.map { ages[$0] }
            let point: NormalizedPoint
            if let age {
                let xOffset = min(0.075, max(0.045, age.bounds.width * 1.3))
                let yOffset = min(0.075, max(0.045, age.bounds.height * 1.5))
                point = NormalizedPoint(x: age.bounds.center.x - xOffset, y: age.bounds.minY - yOffset)
            } else {
                point = NormalizedPoint(
                    x: name.bounds.center.x,
                    y: name.bounds.minY - min(0.075, max(0.05, name.bounds.height * 1.7))
                )
            }
            guard isSafePhotoPoint(point, galleryAnchor: galleryAnchor) else { return nil }

            return VisibleRecommendationTarget(
                profileKey: normalizedProfileKey(name.text),
                displayName: name.text.trimmingCharacters(in: .whitespacesAndNewlines),
                displayedAge: age?.age,
                ageEvidence: age,
                photoPoint: point,
                safePhotoRegion: centeredRegion(around: point, width: 0.13, height: 0.11),
                confidence: min(name.confidence, age?.confidence ?? galleryAnchor.confidence)
            )
        }

        targets.append(contentsOf: ages.enumerated().compactMap { index, age in
            guard !associatedAgeIndexes.contains(index) else { return nil }
            let xOffset = min(0.075, max(0.045, age.bounds.width * 1.3))
            let yOffset = min(0.075, max(0.045, age.bounds.height * 1.5))
            let point = NormalizedPoint(x: age.bounds.center.x - xOffset, y: age.bounds.minY - yOffset)
            guard isSafePhotoPoint(point, galleryAnchor: galleryAnchor) else { return nil }
            let quantizedX = Int((point.x * 100).rounded())
            return VisibleRecommendationTarget(
                profileKey: "age-\(age.age)-x\(quantizedX)",
                displayedAge: age.age,
                ageEvidence: age,
                photoPoint: point,
                safePhotoRegion: centeredRegion(around: point, width: 0.13, height: 0.11),
                confidence: min(age.confidence, galleryAnchor.confidence)
            )
        })

        return targets
        .uniqued(by: \VisibleRecommendationTarget.profileKey)
        .sorted {
            if $0.photoPoint.x != $1.photoPoint.x { return $0.photoPoint.x < $1.photoPoint.x }
            return $0.photoPoint.y < $1.photoPoint.y
        }
    }

    private func oneToOneAgeAssociations(
        names: [OCRObservation],
        ages: [RecommendationAgeCandidate]
    ) -> [Int: Int] {
        let candidates = names.enumerated().flatMap { nameIndex, name in
            ages.enumerated().compactMap { ageIndex, age -> AgeAssociation? in
                let dx = abs(age.bounds.center.x - name.bounds.center.x)
                let dy = abs(age.bounds.center.y - name.bounds.center.y)
                guard dx <= 0.14, dy <= 0.055 else { return nil }
                return AgeAssociation(nameIndex: nameIndex, ageIndex: ageIndex, distance: dx + dy)
            }
        }.sorted { $0.distance < $1.distance }

        var usedNames = Set<Int>()
        var usedAges = Set<Int>()
        var result: [Int: Int] = [:]
        for candidate in candidates where !usedNames.contains(candidate.nameIndex) && !usedAges.contains(candidate.ageIndex) {
            result[candidate.nameIndex] = candidate.ageIndex
            usedNames.insert(candidate.nameIndex)
            usedAges.insert(candidate.ageIndex)
        }
        return result
    }

    private func candidateNames(
        in observations: [OCRObservation],
        below galleryAnchor: OCRObservation,
        alignedWith ages: [RecommendationAgeCandidate]
    ) -> [OCRObservation] {
        let excluded = [
            "suggestedforyou", "sayhi", "follow", "gift", "like", "freetochat",
            "shopnow", "download", "active", "nearby", "joined", "new", "more"
        ]
        let ageRows = ages.map(\.bounds.center.y)
        return observations.filter { observation in
            let trimmed = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let compact = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
            let letterCount = compact.filter(\.isLetter).count
            let words = trimmed.split(whereSeparator: \.isWhitespace)
            let aligned = ageRows.isEmpty || ageRows.contains { abs($0 - observation.bounds.center.y) <= 0.06 }
            return observation.bounds.minY >= galleryAnchor.bounds.maxY + 0.025
                && observation.bounds.minY < 0.94
                && observation.bounds.width <= 0.32
                && observation.bounds.height <= 0.07
                && letterCount >= 2
                && words.count <= 3
                && !excluded.contains(where: compact.contains)
                && aligned
        }
    }

    private func normalizedProfileKey(_ text: String) -> String {
        let compact = text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return compact.isEmpty ? text.lowercased() : compact
    }

    private func isSafePhotoPoint(
        _ point: NormalizedPoint,
        galleryAnchor: OCRObservation
    ) -> Bool {
        point.isInsideUnitSquare
            && point.y >= galleryAnchor.bounds.maxY + 0.015
            && point.y < 0.87
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

public struct VisibleRecommendationTargetRanker: Sendable {
    public init() {}

    public func ranked(_ targets: [VisibleRecommendationTarget]) -> [VisibleRecommendationTarget] {
        targets.sorted { lhs, rhs in
            let lhsPriority = agePriority(lhs.displayedAge)
            let rhsPriority = agePriority(rhs.displayedAge)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhsPriority <= 1, lhs.displayedAge != rhs.displayedAge {
                return (lhs.displayedAge ?? Int.max) < (rhs.displayedAge ?? Int.max)
            }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.photoPoint.x < rhs.photoPoint.x
        }
    }

    private func agePriority(_ age: Int?) -> Int {
        guard let age else { return 2 }
        if ProfileEligibilityPolicy.adultTargetAges.contains(age) { return 0 }
        if ProfileEligibilityPolicy.primaryMBTIAgeException.contains(age) { return 1 }
        return 3
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
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
