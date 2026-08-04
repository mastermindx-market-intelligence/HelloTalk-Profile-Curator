import Foundation

public enum PlannedActionKind: String, Codable, Sendable {
    case openAvatar
    case selectAboutMe
    case selectMoments
    case openRecommendationCard
    case openMomentThumbnail
    case closeViewer
    case verticalScroll
    case horizontalCarousel
    case back
    case showViewerChrome
    case nextViewerPhoto
}

public struct ExclusionZone: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let label: String
    public let bounds: NormalizedRect

    public init(id: UUID = UUID(), label: String, bounds: NormalizedRect) {
        self.id = id
        self.label = label
        self.bounds = bounds
    }
}

public struct PlannedAction: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: PlannedActionKind
    public let point: NormalizedPoint
    public let requiredSafeRegion: NormalizedRect?
    public let rationale: String

    public init(
        id: UUID = UUID(),
        kind: PlannedActionKind,
        point: NormalizedPoint,
        requiredSafeRegion: NormalizedRect?,
        rationale: String
    ) {
        self.id = id
        self.kind = kind
        self.point = point
        self.requiredSafeRegion = requiredSafeRegion
        self.rationale = rationale
    }
}

public enum ActionSafetyRejection: Equatable, Sendable {
    case outsideWindow
    case outsideRequiredSafeRegion
    case intersectsExclusionZone(String)
    case emergencyStopActive
    case sessionPaused(String)
    case dryRunRequired
}

public struct ActionSafetyDecision: Equatable, Sendable {
    public let isAllowed: Bool
    public let rejection: ActionSafetyRejection?

    public init(isAllowed: Bool, rejection: ActionSafetyRejection?) {
        self.isAllowed = isAllowed
        self.rejection = rejection
    }
}

public struct ActionSafetyValidator: Sendable {
    public init() {}

    public func validate(
        _ action: PlannedAction,
        exclusionZones: [ExclusionZone],
        emergencyStopActive: Bool,
        sessionPauseReason: String? = nil,
        liveInputEnabled: Bool
    ) -> ActionSafetyDecision {
        guard action.point.isInsideUnitSquare else {
            return ActionSafetyDecision(isAllowed: false, rejection: .outsideWindow)
        }
        if emergencyStopActive {
            return ActionSafetyDecision(isAllowed: false, rejection: .emergencyStopActive)
        }
        if let sessionPauseReason {
            return ActionSafetyDecision(isAllowed: false, rejection: .sessionPaused(sessionPauseReason))
        }
        if let safeRegion = action.requiredSafeRegion, !safeRegion.contains(action.point) {
            return ActionSafetyDecision(isAllowed: false, rejection: .outsideRequiredSafeRegion)
        }
        if let exclusion = exclusionZones.first(where: { $0.bounds.contains(action.point) }) {
            return ActionSafetyDecision(isAllowed: false, rejection: .intersectsExclusionZone(exclusion.label))
        }
        guard liveInputEnabled else {
            return ActionSafetyDecision(isAllowed: false, rejection: .dryRunRequired)
        }
        return ActionSafetyDecision(isAllowed: true, rejection: nil)
    }
}

public enum DefaultInspectorCalibration {
    /// Deliberately illustrative only. Real calibration must be supervised before live input exists.
    public static let previewAction = PlannedAction(
        kind: .openRecommendationCard,
        point: NormalizedPoint(x: 0.29, y: 0.72),
        requiredSafeRegion: NormalizedRect(x: 0.08, y: 0.58, width: 0.42, height: 0.27),
        rationale: "Preview only — example recommendation card body"
    )

    public static let previewExclusions = [
        ExclusionZone(
            label: "Say Hi (example; requires calibration)",
            bounds: NormalizedRect(x: 0.12, y: 0.78, width: 0.34, height: 0.08)
        ),
        ExclusionZone(
            label: "Bottom social controls (example; requires calibration)",
            bounds: NormalizedRect(x: 0.03, y: 0.88, width: 0.94, height: 0.1)
        )
    ]
}
