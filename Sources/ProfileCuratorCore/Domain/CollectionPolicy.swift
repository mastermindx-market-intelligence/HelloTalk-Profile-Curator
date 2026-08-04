import Foundation

public struct OpenedProfileEvidence: Hashable, Sendable {
    public let username: String?
    public let age: Int?
    public let gender: GenderBadgeHint
    public let mbti: MBTIType?
    public let locationScore: Int?

    public init(
        username: String?,
        age: Int?,
        gender: GenderBadgeHint,
        mbti: MBTIType?,
        locationScore: Int? = nil
    ) {
        self.username = username
        self.age = age
        self.gender = gender
        self.mbti = mbti
        self.locationScore = locationScore
    }
}

public enum ProfileEligibilityDecision: Equatable, Sendable {
    case collectPrimary
    case collectSecondary
    case collectPreferredLocationNoMBTI
    case collectUnknownLocationNoMBTI
    case routingOnly(String)

    public var isCollectible: Bool {
        self == .collectPrimary
            || self == .collectSecondary
            || self == .collectPreferredLocationNoMBTI
            || self == .collectUnknownLocationNoMBTI
    }
}

public struct ProfileEligibilityPolicy: Sendable {
    public static let adultTargetAges = 18...21
    public static let primaryMBTIAgeException = 23...24
    public static let minimumGeneralLocationScore = 70
    public static let minimumNoMBTILocationScore = 85

    public init() {}

    public func evaluate(_ evidence: OpenedProfileEvidence) -> ProfileEligibilityDecision {
        guard let username = evidence.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            return .routingOnly("username_unverified")
        }
        guard evidence.gender == .female else {
            return .routingOnly("female_badge_unverified")
        }
        guard let age = evidence.age else {
            return .routingOnly("age_unverified")
        }
        let standardAge = Self.adultTargetAges.contains(age)
        let primaryAgeException = Self.primaryMBTIAgeException.contains(age)
            && evidence.mbti?.group == .primary
        guard standardAge || primaryAgeException else {
            return .routingOnly("age_outside_18_21_and_not_23_24_primary_mbti")
        }
        let locationScore = evidence.locationScore ?? 10
        let locationMissing = locationScore <= 10
        switch evidence.mbti?.group {
        case .primary: return .collectPrimary
        case .secondary where locationMissing || locationScore >= Self.minimumGeneralLocationScore:
            return .collectSecondary
        case .secondary:
            return .routingOnly("known_location_outside_tiers_1_3")
        case nil where evidence.mbti != nil: return .routingOnly("non_target_mbti")
        case nil where locationScore >= Self.minimumNoMBTILocationScore:
            return .collectPreferredLocationNoMBTI
        case nil where locationMissing:
            return .collectUnknownLocationNoMBTI
        case nil: return .routingOnly("target_mbti_missing_and_location_not_tier_1_or_2")
        }
    }
}

public struct CollectionLimits: Codable, Hashable, Sendable {
    public var maximumScannedPhotos: Int
    public var maximumRetainedPhotos: Int
    public var maximumRetainedFacePhotos: Int
    public var maximumRetainedContextPhotos: Int
    public var minimumFaceAreaRatio: Double
    public var minimumFaceCaptureQuality: Double

    public init(
        maximumScannedPhotos: Int = 20,
        maximumRetainedPhotos: Int = 10,
        maximumRetainedFacePhotos: Int = 6,
        maximumRetainedContextPhotos: Int = 4,
        // A clear face in a full-body Moment often occupies only 1–3% of the
        // cropped photo. Keep rejecting tiny background faces, but do not call
        // a real portrait "no face" solely because it is not a close-up.
        minimumFaceAreaRatio: Double = 0.012,
        minimumFaceCaptureQuality: Double = 0.35
    ) {
        self.maximumScannedPhotos = min(20, max(1, maximumScannedPhotos))
        self.maximumRetainedPhotos = min(10, max(1, maximumRetainedPhotos))
        self.maximumRetainedFacePhotos = min(6, max(0, maximumRetainedFacePhotos))
        self.maximumRetainedContextPhotos = min(4, max(0, maximumRetainedContextPhotos))
        self.minimumFaceAreaRatio = min(1, max(0, minimumFaceAreaRatio))
        self.minimumFaceCaptureQuality = min(1, max(0, minimumFaceCaptureQuality))
    }

    public static let hardenedDefault = CollectionLimits()
}

public struct MediaCandidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let perceptualHash: String
    public let faceCount: Int
    public let largestFaceRatio: Double
    public let captureQuality: Double?
    public let isPhotographicHuman: Bool?
    public let contextStrength: Double

    public init(
        id: UUID = UUID(),
        perceptualHash: String,
        faceCount: Int,
        largestFaceRatio: Double,
        captureQuality: Double?,
        isPhotographicHuman: Bool? = nil,
        contextStrength: Double = 0
    ) {
        self.id = id
        self.perceptualHash = perceptualHash
        self.faceCount = max(0, faceCount)
        self.largestFaceRatio = min(1, max(0, largestFaceRatio))
        self.captureQuality = captureQuality.map { min(1, max(0, $0)) }
        self.isPhotographicHuman = isPhotographicHuman
        self.contextStrength = min(1, max(0, contextStrength))
    }

    public func isUsableFace(limits: CollectionLimits) -> Bool {
        faceCount > 0
            && largestFaceRatio >= limits.minimumFaceAreaRatio
            && (captureQuality ?? 0) >= limits.minimumFaceCaptureQuality
            && isPhotographicHuman != false
    }
}

public struct MediaRetentionPlan: Sendable {
    public let scannedCount: Int
    public let retainedIDs: [UUID]
    public let duplicateCount: Int
    public let reachedScanLimit: Bool
}

public struct MediaRetentionPlanner: Sendable {
    public init() {}

    public func plan(
        candidates: [MediaCandidate],
        limits: CollectionLimits = .hardenedDefault
    ) -> MediaRetentionPlan {
        let scanned = Array(candidates.prefix(limits.maximumScannedPhotos))
        var seen = Set<String>()
        let unique = scanned.filter { seen.insert($0.perceptualHash).inserted }

        let faceImages = unique
            .filter { $0.isUsableFace(limits: limits) }
            .sorted { ($0.captureQuality ?? 0, $0.largestFaceRatio) > ($1.captureQuality ?? 0, $1.largestFaceRatio) }
            .prefix(limits.maximumRetainedFacePhotos)
        let faceIDs = Set(faceImages.map(\.id))
        let contexts = unique
            .filter { !faceIDs.contains($0.id) }
            .sorted { $0.contextStrength > $1.contextStrength }
            .prefix(limits.maximumRetainedContextPhotos)

        let retained = Array(faceImages.map(\.id) + contexts.map(\.id)).prefix(limits.maximumRetainedPhotos)
        return MediaRetentionPlan(
            scannedCount: scanned.count,
            retainedIDs: Array(retained),
            duplicateCount: scanned.count - unique.count,
            reachedScanLimit: candidates.count >= limits.maximumScannedPhotos
        )
    }
}

public enum NoFaceDecision: Equatable, Sendable {
    case continueScanning
    case retainForReview
    case rejectAndPurge
}

public struct NoFacePolicy: Sendable {
    public var enabledForPrimary: Bool
    public let limits: CollectionLimits

    public init(enabledForPrimary: Bool = true, limits: CollectionLimits = .hardenedDefault) {
        self.enabledForPrimary = enabledForPrimary
        self.limits = limits
    }

    public func decision(
        group: MBTIGroup,
        candidates: [MediaCandidate],
        feedExhausted: Bool
    ) -> NoFaceDecision {
        if candidates.contains(where: { $0.isUsableFace(limits: limits) }) { return .retainForReview }
        let mustEnforce = group == .secondary || enabledForPrimary
        guard mustEnforce else { return .retainForReview }
        guard feedExhausted || candidates.count >= limits.maximumScannedPhotos else { return .continueScanning }
        return .rejectAndPurge
    }
}

public struct ScoreWeights: Codable, Hashable, Sendable {
    public var face: Double
    public var lifestyle: Double
    public var location: Double
    public var completeness: Double

    public init(face: Double, lifestyle: Double, location: Double, completeness: Double) {
        let total = max(0.0001, face + lifestyle + location + completeness)
        self.face = max(0, face) / total
        self.lifestyle = max(0, lifestyle) / total
        self.location = max(0, location) / total
        self.completeness = max(0, completeness) / total
    }

    public static let primary = ScoreWeights(face: 0.45, lifestyle: 0.25, location: 0.20, completeness: 0.10)
    public static let secondary = ScoreWeights(face: 0.50, lifestyle: 0.30, location: 0.20, completeness: 0)
}

public struct ScoreComponents: Hashable, Sendable {
    public let face: Double
    public let lifestyle: Double
    public let location: Double
    public let completeness: Double
    public let confidence: Double

    public init(face: Double, lifestyle: Double, location: Double, completeness: Double, confidence: Double) {
        self.face = min(100, max(0, face))
        self.lifestyle = min(100, max(0, lifestyle))
        self.location = min(100, max(0, location))
        self.completeness = min(100, max(0, completeness))
        self.confidence = min(1, max(0, confidence))
    }
}

public struct ProfileScore: Hashable, Sendable {
    public let overall: Double
    public let confidenceAdjusted: Double
    public let secondaryHighPriority: Bool
}

public struct ScoringEngine: Sendable {
    public var primaryWeights: ScoreWeights
    public var secondaryWeights: ScoreWeights
    public var secondaryFaceThreshold: Double
    public var secondaryLifestyleThreshold: Double
    public var secondaryOverallThreshold: Double
    public var secondaryLocationThreshold: Double
    public var preferredLocationNoMBTIPenalty: Double
    public var missingLocationPenalty: Double
    public var missingLocationFaceWaiverThreshold: Double

    public init(
        primaryWeights: ScoreWeights = .primary,
        secondaryWeights: ScoreWeights = .secondary,
        secondaryFaceThreshold: Double = 82,
        secondaryLifestyleThreshold: Double = 82,
        secondaryOverallThreshold: Double = 76,
        secondaryLocationThreshold: Double = 100,
        preferredLocationNoMBTIPenalty: Double = 8,
        missingLocationPenalty: Double = 8,
        missingLocationFaceWaiverThreshold: Double = 90
    ) {
        self.primaryWeights = primaryWeights
        self.secondaryWeights = secondaryWeights
        self.secondaryFaceThreshold = secondaryFaceThreshold
        self.secondaryLifestyleThreshold = secondaryLifestyleThreshold
        self.secondaryOverallThreshold = secondaryOverallThreshold
        self.secondaryLocationThreshold = secondaryLocationThreshold
        self.preferredLocationNoMBTIPenalty = min(25, max(0, preferredLocationNoMBTIPenalty))
        self.missingLocationPenalty = min(25, max(0, missingLocationPenalty))
        self.missingLocationFaceWaiverThreshold = min(100, max(0, missingLocationFaceWaiverThreshold))
    }

    public func score(
        group: MBTIGroup,
        components: ScoreComponents,
        locationMissing: Bool = false
    ) -> ProfileScore {
        let weights = group == .primary ? primaryWeights : secondaryWeights
        let base: Double
        if locationMissing {
            let remainingWeight = max(0.0001, weights.face + weights.lifestyle + weights.completeness)
            base = components.face * weights.face / remainingWeight
                + components.lifestyle * weights.lifestyle / remainingWeight
                + components.completeness * weights.completeness / remainingWeight
        } else {
            base = components.face * weights.face
                + components.lifestyle * weights.lifestyle
                + components.location * weights.location
                + components.completeness * weights.completeness
        }
        let waiveMissingLocationPenalty = group == .primary
            || components.face >= missingLocationFaceWaiverThreshold
        let locationPenalty = locationMissing && !waiveMissingLocationPenalty ? missingLocationPenalty : 0
        let overall = max(0, base - locationPenalty)
        let adjusted = overall * (0.75 + 0.25 * components.confidence)
        let highPriority = group == .secondary && (
            components.face >= secondaryFaceThreshold
                || components.lifestyle >= secondaryLifestyleThreshold
                || overall >= secondaryOverallThreshold
                || components.location >= secondaryLocationThreshold
        )
        return ProfileScore(overall: overall, confidenceAdjusted: adjusted, secondaryHighPriority: highPriority)
    }

    public func scorePreferredLocationNoMBTI(
        components: ScoreComponents,
        locationMissing: Bool = false
    ) -> ProfileScore {
        let base: Double
        if locationMissing {
            base = components.face * (0.55 / 0.90) + components.lifestyle * (0.35 / 0.90)
        } else {
            base = components.face * 0.55
                + components.lifestyle * 0.35
                + components.location * 0.10
        }
        let locationPenalty = locationMissing && components.face < missingLocationFaceWaiverThreshold
            ? missingLocationPenalty
            : 0
        let overall = max(0, base - preferredLocationNoMBTIPenalty - locationPenalty)
        let adjusted = overall * (0.75 + 0.25 * components.confidence)
        let highPriority = components.face >= secondaryFaceThreshold
            || components.lifestyle >= secondaryLifestyleThreshold
            || overall >= secondaryOverallThreshold
        return ProfileScore(
            overall: overall,
            confidenceAdjusted: adjusted,
            secondaryHighPriority: highPriority
        )
    }
}
