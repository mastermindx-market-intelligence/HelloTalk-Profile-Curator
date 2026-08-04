import Foundation

public struct VisibleRecommendationCandidate: Hashable, Sendable {
    public let profileKey: String
    public let displayedAge: Int?
    public let genderHint: GenderBadgeHint

    public init(profileKey: String, displayedAge: Int?, genderHint: GenderBadgeHint) {
        self.profileKey = profileKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.displayedAge = displayedAge
        self.genderHint = genderHint
    }
}

public enum RecommendationTraversalDecision: Equatable, Sendable {
    case openForTargetVerification
    case openForEligibilityInspection
    case openAsRoutingOnly
    case skipDuplicate
    case rejectNonFemaleHint
    case routingDepthLimitReached(Int)

    public var isOpenProposal: Bool {
        switch self {
        case .openForTargetVerification, .openForEligibilityInspection, .openAsRoutingOnly:
            true
        default:
            false
        }
    }
}

public struct RecommendationTraversalLedger: Sendable {
    public private(set) var visitedProfileKeys: Set<String>
    public private(set) var routingDepth: Int
    public let maximumRoutingDepth: Int

    public init(
        visitedProfileKeys: Set<String> = [],
        routingDepth: Int = 0,
        maximumRoutingDepth: Int = DiscoveryPolicy.observedDefault.maximumRoutingDepth
    ) {
        self.visitedProfileKeys = visitedProfileKeys
        self.routingDepth = routingDepth
        self.maximumRoutingDepth = maximumRoutingDepth
    }

    public func decision(for candidate: VisibleRecommendationCandidate) -> RecommendationTraversalDecision {
        guard !visitedProfileKeys.contains(candidate.profileKey) else { return .skipDuplicate }
        guard candidate.genderHint != .male else { return .rejectNonFemaleHint }

        if candidate.genderHint == .unknown {
            guard routingDepth < maximumRoutingDepth else {
                return .routingDepthLimitReached(maximumRoutingDepth)
            }
            return .openForEligibilityInspection
        }

        if let age = candidate.displayedAge,
           ProfileEligibilityPolicy.adultTargetAges.contains(age)
            || ProfileEligibilityPolicy.primaryMBTIAgeException.contains(age) {
            return .openForTargetVerification
        }
        guard routingDepth < maximumRoutingDepth else {
            return .routingDepthLimitReached(maximumRoutingDepth)
        }
        return .openAsRoutingOnly
    }

    public mutating func recordOpened(
        _ candidate: VisibleRecommendationCandidate,
        decision: RecommendationTraversalDecision
    ) {
        guard decision.isOpenProposal else { return }
        visitedProfileKeys.insert(candidate.profileKey)
        if decision == .openAsRoutingOnly || decision == .openForEligibilityInspection {
            routingDepth += 1
        }
    }

    public mutating func recordVerifiedProfileKey(_ profileKey: String) {
        let normalized = profileKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        visitedProfileKeys.insert(normalized)
    }

    public mutating func recordCompletedDisplayName(_ displayName: String) {
        let normalized = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !normalized.isEmpty else { return }
        visitedProfileKeys.insert(normalized)
    }
}
