import Foundation

public enum RuntimeEvent: Sendable {
    case screenObserved(DetectedScreenKind)
    case mbtiEvaluated(ProfileEligibilityDecision)
    case profileCaptureComplete
    case pfpViewerOpened
    case pfpCaptureComplete
    case momentsOpened
    case momentsCollectionComplete
    case suggestionsReached
    case recommendationProposed(previousUsername: String)
    case profileChangeVerified
    case recommendationsExhausted
    case timeout
    case emergencyStop
}

public struct RuntimeTransition: Sendable {
    public let previous: NavigationState
    public let current: NavigationState
    public let reason: String
}

public struct DeterministicRuntimeCoordinator: Sendable {
    public private(set) var snapshot: NavigationSnapshot

    public init(snapshot: NavigationSnapshot = NavigationSnapshot(state: .acquireMirroringWindow)) {
        self.snapshot = snapshot
    }

    @discardableResult
    public mutating func handle(_ event: RuntimeEvent, now: Date = Date()) -> RuntimeTransition {
        let previous = snapshot.state
        let next: NavigationState
        let postcondition: VisiblePostcondition?
        let reason: String

        switch event {
        case .emergencyStop:
            next = .emergencyStopped; postcondition = nil; reason = "Emergency stop latched"
        case .timeout:
            next = .pausedUnknownState; postcondition = nil; reason = "State timeout; random recovery clicks forbidden"
        case .screenObserved(.unknown):
            next = .pausedUnknownState; postcondition = nil; reason = "Unknown screen"
        case .screenObserved(.profileTop):
            next = .scanForPersonalInfo; postcondition = nil; reason = "Opened profile header recognized"
        case .screenObserved(.profilePersonalInfo):
            next = .evaluateMBTI; postcondition = nil; reason = "Personal Info recognized"
        case .screenObserved(.suggestedProfilesGallery):
            next = .scanRecommendationCards; postcondition = nil; reason = "Suggested gallery recognized"
        case .screenObserved(.pfpViewer):
            next = .inspectPFPViewer; postcondition = nil; reason = "PFP viewer recognized"
        case .screenObserved(.momentsFeed):
            next = .collectMoments; postcondition = nil; reason = "Moments feed recognized"
        case .screenObserved(.momentViewer):
            next = .inspectMomentViewer; postcondition = nil; reason = "Moment viewer recognized"
        case .screenObserved:
            next = .identifyCurrentScreen; postcondition = nil; reason = "Known non-profile surface"
        case .mbtiEvaluated(let decision):
            next = decision.isCollectible ? .collectTargetProfile : .seekSuggestions
            postcondition = nil
            reason = decision.isCollectible ? "Opened profile eligibility verified" : "Profile is routing-only"
        case .profileCaptureComplete:
            next = .inspectPFPViewer; postcondition = .viewerDetected; reason = "Profile top checkpointed"
        case .pfpViewerOpened:
            next = .inspectPFPViewer; postcondition = nil; reason = "PFP viewer verified"
        case .pfpCaptureComplete:
            next = .collectMoments; postcondition = .selectedTab("Moments"); reason = "PFP captured"
        case .momentsOpened:
            next = .collectMoments; postcondition = nil; reason = "Moments tab verified"
        case .momentsCollectionComplete:
            next = .seekSuggestions; postcondition = .ocrAnchorVisible("Suggested for You"); reason = "Media limits or feed bottom reached"
        case .suggestionsReached:
            next = .scanRecommendationCards; postcondition = nil; reason = "Suggested gallery ready"
        case .recommendationProposed(let previousUsername):
            next = .verifyProfileChanged
            postcondition = .profileIdentityChanged(previousUsername: previousUsername)
            reason = "Safe visible-card proposal awaiting identity change"
        case .profileChangeVerified:
            next = .profileTop; postcondition = nil; reason = "New profile identity verified"
        case .recommendationsExhausted:
            next = .returnToSeedFeed; postcondition = nil; reason = "Visible graph exhausted"
        }

        snapshot = NavigationSnapshot(state: next, enteredAt: now, retryCount: 0, pendingPostcondition: postcondition)
        return RuntimeTransition(previous: previous, current: next, reason: reason)
    }
}

public struct CollectionCheckpoint: Codable, Sendable {
    public let navigation: NavigationSnapshot
    public let currentUsername: String?
    public let currentProfileID: String?
    public let scannedPhotoCount: Int
    public let retainedPhotoCount: Int
    public let perceptualHashes: Set<String>
    public let momentVisitKeys: Set<String>
    public let updatedAt: Date

    public init(
        navigation: NavigationSnapshot,
        currentUsername: String?,
        currentProfileID: String?,
        scannedPhotoCount: Int,
        retainedPhotoCount: Int,
        perceptualHashes: Set<String>,
        momentVisitKeys: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.navigation = navigation
        self.currentUsername = currentUsername
        self.currentProfileID = currentProfileID
        self.scannedPhotoCount = min(20, max(0, scannedPhotoCount))
        self.retainedPhotoCount = min(10, max(0, retainedPhotoCount))
        self.perceptualHashes = perceptualHashes
        self.momentVisitKeys = momentVisitKeys
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case navigation, currentUsername, currentProfileID, scannedPhotoCount
        case retainedPhotoCount, perceptualHashes, momentVisitKeys, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            navigation: try container.decode(NavigationSnapshot.self, forKey: .navigation),
            currentUsername: try container.decodeIfPresent(String.self, forKey: .currentUsername),
            currentProfileID: try container.decodeIfPresent(String.self, forKey: .currentProfileID),
            scannedPhotoCount: try container.decode(Int.self, forKey: .scannedPhotoCount),
            retainedPhotoCount: try container.decode(Int.self, forKey: .retainedPhotoCount),
            perceptualHashes: try container.decode(Set<String>.self, forKey: .perceptualHashes),
            momentVisitKeys: try container.decodeIfPresent(Set<String>.self, forKey: .momentVisitKeys) ?? [],
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

public final class CollectionCheckpointStore: @unchecked Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultStore(fileManager: FileManager = .default) throws -> CollectionCheckpointStore {
        let root = try ProfileRepository.defaultDataDirectory(fileManager: fileManager)
        return CollectionCheckpointStore(fileURL: root.appendingPathComponent("checkpoint.json"))
    }

    public func save(_ checkpoint: CollectionCheckpoint) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(checkpoint).write(to: fileURL, options: .atomic)
    }

    public func load() throws -> CollectionCheckpoint? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(CollectionCheckpoint.self, from: Data(contentsOf: fileURL))
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
