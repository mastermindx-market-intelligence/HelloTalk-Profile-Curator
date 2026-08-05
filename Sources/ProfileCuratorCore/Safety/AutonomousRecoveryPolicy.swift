import Foundation

public enum AutonomousRecoveryStep: Equatable, Sendable {
    case recapture
    case closePFPViewer
    case dismissMomentViewer
    case finishMoments
    case dismissProfileOverflow
    case dismissInterstitial
    case backToPreviousSurface
    case abandonProfile
    case resumeRecommendationGallery
    case resumeCustomSearch
    case resumeConnectFeed
    case stop
}

public struct AutonomousRecoveryPolicy: Sendable {
    public static let maximumAttemptsPerIncident = 5

    public init() {}

    public func step(for screen: DetectedScreenKind, attempt: Int) -> AutonomousRecoveryStep {
        guard attempt > 0, attempt <= Self.maximumAttemptsPerIncident else { return .stop }
        switch screen {
        case .pfpViewer:
            return attempt <= 2 ? .closePFPViewer : attempt == 3 ? .backToPreviousSurface : .stop
        case .momentViewer:
            return attempt <= 2 ? .dismissMomentViewer : attempt == 3 ? .backToPreviousSurface : .stop
        case .momentsFeed:
            return attempt <= 2 ? .finishMoments : attempt == 3 ? .backToPreviousSurface : .stop
        case .momentDetails:
            return attempt <= 3 ? .backToPreviousSurface : .stop
        case .profileOverflowMenu:
            return attempt == 1 ? .dismissProfileOverflow : attempt <= 3 ? .backToPreviousSurface : .stop
        case .interstitialAd:
            return attempt == 1 ? .dismissInterstitial : attempt <= 3 ? .backToPreviousSurface : .stop
        case .profileTop, .profilePersonalInfo:
            return attempt <= 3 ? .abandonProfile : .stop
        case .suggestedProfilesGallery:
            return attempt <= 3 ? .resumeRecommendationGallery : .stop
        case .customSearch:
            return attempt <= 3 ? .resumeCustomSearch : .stop
        case .connectFeed:
            return attempt <= 3 ? .resumeConnectFeed : .stop
        case .unknown:
            if attempt <= 2 { return .recapture }
            if attempt == 3 { return .backToPreviousSurface }
            return attempt == 4 ? .recapture : .stop
        }
    }
}
