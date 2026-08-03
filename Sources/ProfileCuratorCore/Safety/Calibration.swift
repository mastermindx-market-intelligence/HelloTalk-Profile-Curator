import Foundation

public enum CalibrationMarkKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case safeAvatar
    case safeAboutMe
    case safeMoments
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

public struct CalibrationMark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: CalibrationMarkKind
    public let bounds: NormalizedRect
    public let confirmed: Bool

    public init(
        id: UUID = UUID(),
        kind: CalibrationMarkKind,
        bounds: NormalizedRect,
        confirmed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
        self.confirmed = confirmed
    }
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
