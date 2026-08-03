import Foundation

public enum DiscoverySource: String, Codable, Sendable {
    case similarProfilesGallery
    case customSearchSeed
    case connectFeedSeed
}

public enum RecommendationTraversalMode: String, Codable, Sendable {
    case visibleCardGraph
    case horizontalCarousel
}

public enum VerticalTraversalMode: String, Codable, Sendable {
    case discreteScrollEvents
    case touchDrag
}

public struct DiscoveryPolicy: Codable, Equatable, Sendable {
    public let primarySource: DiscoverySource
    public let fallbackSources: [DiscoverySource]
    public let customSearchActiveUsersOnly: Bool
    public let reverifyAgeAndGenderOnEveryProfile: Bool
    public let sameGenderRecommendationIsHintOnly: Bool
    public let primaryTraversalMode: RecommendationTraversalMode
    public let horizontalCarouselEnabledByDefault: Bool
    public let maximumRoutingDepth: Int
    public let verticalTraversalMode: VerticalTraversalMode
    public let touchDragGesturesEnabledByDefault: Bool

    public init(
        primarySource: DiscoverySource,
        fallbackSources: [DiscoverySource],
        customSearchActiveUsersOnly: Bool,
        reverifyAgeAndGenderOnEveryProfile: Bool,
        sameGenderRecommendationIsHintOnly: Bool,
        primaryTraversalMode: RecommendationTraversalMode,
        horizontalCarouselEnabledByDefault: Bool,
        maximumRoutingDepth: Int,
        verticalTraversalMode: VerticalTraversalMode,
        touchDragGesturesEnabledByDefault: Bool
    ) {
        self.primarySource = primarySource
        self.fallbackSources = fallbackSources
        self.customSearchActiveUsersOnly = customSearchActiveUsersOnly
        self.reverifyAgeAndGenderOnEveryProfile = reverifyAgeAndGenderOnEveryProfile
        self.sameGenderRecommendationIsHintOnly = sameGenderRecommendationIsHintOnly
        self.primaryTraversalMode = primaryTraversalMode
        self.horizontalCarouselEnabledByDefault = horizontalCarouselEnabledByDefault
        self.maximumRoutingDepth = maximumRoutingDepth
        self.verticalTraversalMode = verticalTraversalMode
        self.touchDragGesturesEnabledByDefault = touchDragGesturesEnabledByDefault
    }

    public static let observedDefault = DiscoveryPolicy(
        primarySource: .similarProfilesGallery,
        fallbackSources: [.customSearchSeed, .connectFeedSeed],
        customSearchActiveUsersOnly: true,
        reverifyAgeAndGenderOnEveryProfile: true,
        sameGenderRecommendationIsHintOnly: true,
        primaryTraversalMode: .visibleCardGraph,
        horizontalCarouselEnabledByDefault: false,
        maximumRoutingDepth: 12,
        verticalTraversalMode: .discreteScrollEvents,
        touchDragGesturesEnabledByDefault: false
    )
}
