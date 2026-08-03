import Foundation

public struct NavigationSessionPolicy: Codable, Equatable, Sendable {
    public let maximumProposals: Int
    public let maximumProfileVisits: Int
    public let maximumDurationSeconds: TimeInterval
    public let maximumConsecutiveUnknownScreens: Int

    public init(
        maximumProposals: Int = 100,
        maximumProfileVisits: Int = 25,
        maximumDurationSeconds: TimeInterval = 30 * 60,
        maximumConsecutiveUnknownScreens: Int = 2
    ) {
        self.maximumProposals = maximumProposals
        self.maximumProfileVisits = maximumProfileVisits
        self.maximumDurationSeconds = maximumDurationSeconds
        self.maximumConsecutiveUnknownScreens = maximumConsecutiveUnknownScreens
    }

    public static let conservativeDefault = NavigationSessionPolicy()
}

public enum NavigationSessionPauseReason: Equatable, Sendable {
    case emergencyStop
    case proposalLimit(Int)
    case profileVisitLimit(Int)
    case durationLimit(TimeInterval)
    case unknownScreenLimit(Int)

    public var summary: String {
        switch self {
        case .emergencyStop:
            "Emergency stop is latched"
        case .proposalLimit(let limit):
            "Proposal limit reached (\(limit))"
        case .profileVisitLimit(let limit):
            "Profile visit limit reached (\(limit))"
        case .durationLimit(let seconds):
            "Session duration limit reached (\(Int(seconds / 60)) min)"
        case .unknownScreenLimit(let limit):
            "Unknown-screen limit reached (\(limit) consecutive)"
        }
    }
}

public struct NavigationSessionState: Sendable {
    public let startedAt: Date
    public private(set) var proposalCount: Int
    public private(set) var profileVisitCount: Int
    public private(set) var consecutiveUnknownScreens: Int
    public private(set) var pauseReason: NavigationSessionPauseReason?

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        proposalCount = 0
        profileVisitCount = 0
        consecutiveUnknownScreens = 0
        pauseReason = nil
    }

    public var isPaused: Bool { pauseReason != nil }

    public mutating func recordProposal(policy: NavigationSessionPolicy, now: Date = Date()) {
        guard pauseReason == nil else { return }
        proposalCount += 1
        applyLimits(policy: policy, now: now)
    }

    public mutating func recordProfileVisit(policy: NavigationSessionPolicy, now: Date = Date()) {
        guard pauseReason == nil else { return }
        profileVisitCount += 1
        applyLimits(policy: policy, now: now)
    }

    public mutating func recordScreen(
        _ kind: DetectedScreenKind,
        policy: NavigationSessionPolicy,
        now: Date = Date()
    ) {
        guard pauseReason == nil else { return }
        consecutiveUnknownScreens = kind == .unknown ? consecutiveUnknownScreens + 1 : 0
        applyLimits(policy: policy, now: now)
    }

    public mutating func engageEmergencyStop() {
        pauseReason = .emergencyStop
    }

    private mutating func applyLimits(policy: NavigationSessionPolicy, now: Date) {
        if proposalCount >= policy.maximumProposals {
            pauseReason = .proposalLimit(policy.maximumProposals)
        } else if profileVisitCount >= policy.maximumProfileVisits {
            pauseReason = .profileVisitLimit(policy.maximumProfileVisits)
        } else if now.timeIntervalSince(startedAt) >= policy.maximumDurationSeconds {
            pauseReason = .durationLimit(policy.maximumDurationSeconds)
        } else if consecutiveUnknownScreens >= policy.maximumConsecutiveUnknownScreens {
            pauseReason = .unknownScreenLimit(policy.maximumConsecutiveUnknownScreens)
        }
    }
}
