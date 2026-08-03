import Foundation

public enum NavigationState: String, CaseIterable, Codable, Sendable {
    case acquireMirroringWindow
    case identifyCurrentScreen
    case acquireSeedProfile
    case profileTop
    case scanForPersonalInfo
    case evaluateMBTI
    case collectTargetProfile
    case inspectPFPViewer
    case collectMoments
    case inspectMomentViewer
    case seekSuggestions
    case scanRecommendationCards
    case swipeCarousel
    case returnToSeedFeed
    case openEligibleProfile
    case verifyProfileChanged
    case pausedUnknownState
    case emergencyStopped
}

public enum VisiblePostcondition: Codable, Hashable, Sendable {
    case contentHashChanged(previous: String)
    case ocrAnchorVisible(String)
    case viewerDetected
    case profilePageDetected
    case selectedTab(String)
    case profileIdentityChanged(previousUsername: String?)
}

public struct NavigationSnapshot: Codable, Sendable {
    public let state: NavigationState
    public let enteredAt: Date
    public let retryCount: Int
    public let pendingPostcondition: VisiblePostcondition?

    public init(
        state: NavigationState,
        enteredAt: Date = Date(),
        retryCount: Int = 0,
        pendingPostcondition: VisiblePostcondition? = nil
    ) {
        self.state = state
        self.enteredAt = enteredAt
        self.retryCount = retryCount
        self.pendingPostcondition = pendingPostcondition
    }
}
