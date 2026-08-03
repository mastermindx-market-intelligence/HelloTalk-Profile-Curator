import Foundation

public enum DiscoverySource: String, Codable, Sendable {
    case similarProfilesGallery
    case customSearchSeed
    case connectFeedSeed
}

public struct DiscoveryPolicy: Codable, Equatable, Sendable {
    public let primarySource: DiscoverySource
    public let fallbackSources: [DiscoverySource]
    public let customSearchActiveUsersOnly: Bool
    public let reverifyAgeAndGenderOnEveryProfile: Bool
    public let sameGenderRecommendationIsHintOnly: Bool

    public init(
        primarySource: DiscoverySource,
        fallbackSources: [DiscoverySource],
        customSearchActiveUsersOnly: Bool,
        reverifyAgeAndGenderOnEveryProfile: Bool,
        sameGenderRecommendationIsHintOnly: Bool
    ) {
        self.primarySource = primarySource
        self.fallbackSources = fallbackSources
        self.customSearchActiveUsersOnly = customSearchActiveUsersOnly
        self.reverifyAgeAndGenderOnEveryProfile = reverifyAgeAndGenderOnEveryProfile
        self.sameGenderRecommendationIsHintOnly = sameGenderRecommendationIsHintOnly
    }

    public static let observedDefault = DiscoveryPolicy(
        primarySource: .similarProfilesGallery,
        fallbackSources: [.customSearchSeed, .connectFeedSeed],
        customSearchActiveUsersOnly: true,
        reverifyAgeAndGenderOnEveryProfile: true,
        sameGenderRecommendationIsHintOnly: true
    )
}
