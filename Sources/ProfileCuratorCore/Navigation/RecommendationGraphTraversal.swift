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
    case openAsRoutingOnly
    case skipDuplicate
    case rejectNonFemaleHint
    case routingDepthLimitReached(Int)

    public var isOpenProposal: Bool {
        switch self {
        case .openForTargetVerification, .openAsRoutingOnly:
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
        guard candidate.genderHint == .female else { return .rejectNonFemaleHint }

        if let age = candidate.displayedAge, (18...21).contains(age) {
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
        if decision == .openAsRoutingOnly {
            routingDepth += 1
        }
    }
}
