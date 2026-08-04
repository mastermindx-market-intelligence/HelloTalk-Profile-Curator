import Foundation

public enum CalibrationMarkKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case safeAvatar
    case safeAboutMe
    case safeMoments
    case safeMomentThumbnailGrid
    case safeMomentDismissGesture
    case safeRecommendationCard
    case safeCarouselGesture
    case safeBackClose
    case profileHeaderAnchor
    case excludeSayHi
    case excludeFollow
    case excludeLike
    case excludeGift
    case excludeMessageComposer
    case excludeAdControls

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safeAvatar: "Safe: Avatar"
        case .safeAboutMe: "Safe: About Me tab"
        case .safeMoments: "Safe: Moments tab"
        case .safeMomentThumbnailGrid: "Safe: Moment thumbnail grid"
        case .safeMomentDismissGesture: "Safe: Moment dismiss gesture"
        case .safeRecommendationCard: "Safe: Recommendation card body"
        case .safeCarouselGesture: "Safe: Carousel gesture zone"
        case .safeBackClose: "Safe: Back / close"
        case .profileHeaderAnchor: "Anchor: Profile header"
        case .excludeSayHi: "Never click: Say Hi"
        case .excludeFollow: "Never click: Follow"
        case .excludeLike: "Never click: Like"
        case .excludeGift: "Never click: Gift"
        case .excludeMessageComposer: "Never click: Message composer"
        case .excludeAdControls: "Never click: Ad controls"
        }
    }

    public var isExclusion: Bool {
        switch self {
        case .excludeSayHi, .excludeFollow, .excludeLike, .excludeGift, .excludeMessageComposer, .excludeAdControls:
            true
        default:
            false
        }
    }
}

public enum CalibrationContext: String, CaseIterable, Codable, Sendable, Identifiable {
    case connectFeed
    case profile
    case pfpViewer
    case momentsFeed
    case momentViewer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .connectFeed: "Connect feed"
        case .profile: "Profile"
        case .pfpViewer: "PFP viewer"
        case .momentsFeed: "Moments feed"
        case .momentViewer: "Moment viewer"
        }
    }
}

public struct CalibrationMark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let context: CalibrationContext
    public let kind: CalibrationMarkKind
    public let bounds: NormalizedRect
    public let confirmed: Bool

    public init(
        id: UUID = UUID(),
        context: CalibrationContext = .profile,
        kind: CalibrationMarkKind,
        bounds: NormalizedRect,
        confirmed: Bool = false
    ) {
        self.id = id
        self.context = context
        self.kind = kind
        self.bounds = bounds
        self.confirmed = confirmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case context
        case kind
        case bounds
        case confirmed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        context = try container.decodeIfPresent(CalibrationContext.self, forKey: .context) ?? .profile
        kind = try container.decode(CalibrationMarkKind.self, forKey: .kind)
        bounds = try container.decode(NormalizedRect.self, forKey: .bounds)
        confirmed = try container.decodeIfPresent(Bool.self, forKey: .confirmed) ?? false
    }
}

public enum ObservedHelloTalkCalibration {
    /// Baseline measured from the supervised 2026-08-03 session. Values are
    /// normalized to the complete 420×932 iPhone Mirroring window capture.
    /// Runtime must still validate visual anchors before using any safe region.
    public static let marks: [CalibrationMark] = [
        CalibrationMark(
            context: .connectFeed,
            kind: .safeRecommendationCard,
            bounds: NormalizedRect(x: 0.057, y: 0.258, width: 0.16, height: 0.077)
        ),
        CalibrationMark(
            context: .profile,
            kind: .safeAvatar,
            bounds: NormalizedRect(x: 0.057, y: 0.258, width: 0.171, height: 0.077)
        ),
        CalibrationMark(
            context: .profile,
            kind: .safeAboutMe,
            bounds: NormalizedRect(x: 0.057, y: 0.547, width: 0.293, height: 0.038)
        ),
        CalibrationMark(
            context: .profile,
            kind: .safeMoments,
            bounds: NormalizedRect(x: 0.35, y: 0.547, width: 0.298, height: 0.038)
        ),
        CalibrationMark(
            context: .profile,
            kind: .safeBackClose,
            bounds: NormalizedRect(x: 0.057, y: 0.103, width: 0.062, height: 0.04)
        ),
        CalibrationMark(
            context: .profile,
            kind: .profileHeaderAnchor,
            bounds: NormalizedRect(x: 0.057, y: 0.258, width: 0.881, height: 0.172)
        ),
        CalibrationMark(
            context: .profile,
            kind: .excludeFollow,
            bounds: NormalizedRect(x: 0.057, y: 0.89, width: 0.366, height: 0.057)
        ),
        CalibrationMark(
            context: .profile,
            kind: .excludeSayHi,
            bounds: NormalizedRect(x: 0.44, y: 0.89, width: 0.362, height: 0.057)
        ),
        CalibrationMark(
            context: .profile,
            kind: .excludeGift,
            bounds: NormalizedRect(x: 0.823, y: 0.89, width: 0.114, height: 0.057)
        ),
        CalibrationMark(
            context: .pfpViewer,
            kind: .safeBackClose,
            bounds: NormalizedRect(x: 0.057, y: 0.103, width: 0.062, height: 0.04)
        ),
        CalibrationMark(
            context: .pfpViewer,
            kind: .excludeLike,
            bounds: NormalizedRect(x: 0.714, y: 0.108, width: 0.088, height: 0.045)
        ),
        CalibrationMark(
            context: .pfpViewer,
            kind: .excludeGift,
            bounds: NormalizedRect(x: 0.845, y: 0.108, width: 0.093, height: 0.045)
        ),
        CalibrationMark(
            context: .pfpViewer,
            kind: .excludeGift,
            bounds: NormalizedRect(x: 0.057, y: 0.662, width: 0.881, height: 0.125)
        ),
        CalibrationMark(
            context: .momentViewer,
            kind: .safeBackClose,
            bounds: NormalizedRect(x: 0.057, y: 0.103, width: 0.062, height: 0.04)
        ),
        CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        ),
        CalibrationMark(
            context: .momentViewer,
            kind: .safeMomentDismissGesture,
            bounds: NormalizedRect(x: 0.12, y: 0.43, width: 0.76, height: 0.44),
            confirmed: true
        ),
        CalibrationMark(
            context: .momentViewer,
            kind: .excludeLike,
            bounds: NormalizedRect(x: 0.057, y: 0.89, width: 0.881, height: 0.072),
            confirmed: true
        )
    ]
}

public struct CalibrationProfile: Codable, Sendable {
    public let schemaVersion: Int
    public let referencePixelWidth: Int
    public let referencePixelHeight: Int
    public let marks: [CalibrationMark]
    public let updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        referencePixelWidth: Int,
        referencePixelHeight: Int,
        marks: [CalibrationMark],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.referencePixelWidth = referencePixelWidth
        self.referencePixelHeight = referencePixelHeight
        self.marks = marks
        self.updatedAt = updatedAt
    }
}

public struct CalibrationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) throws -> CalibrationStore {
        let dataDirectory = try ProfileRepository.defaultDataDirectory(fileManager: fileManager)
        return CalibrationStore(fileURL: dataDirectory.appendingPathComponent("calibration.json"))
    }

    public func save(_ profile: CalibrationProfile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(profile).write(to: fileURL, options: .atomic)
    }

    public func load() throws -> CalibrationProfile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CalibrationProfile.self, from: Data(contentsOf: fileURL))
    }
}
