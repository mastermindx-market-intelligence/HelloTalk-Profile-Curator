import Foundation

public struct PlannedGesture: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: PlannedActionKind
    public let start: NormalizedPoint
    public let end: NormalizedPoint
    public let requiredSafeRegion: NormalizedRect
    public let rationale: String

    public init(
        id: UUID = UUID(),
        kind: PlannedActionKind,
        start: NormalizedPoint,
        end: NormalizedPoint,
        requiredSafeRegion: NormalizedRect,
        rationale: String
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.requiredSafeRegion = requiredSafeRegion
        self.rationale = rationale
    }
}

public enum GestureSafetyRejection: Equatable, Sendable {
    case unsupportedGestureKind
    case outsideWindow
    case outsideRequiredSafeRegion
    case intersectsExclusionZone(String)
    case calibrationIncomplete
    case emergencyStopActive
    case sessionPaused(String)
    case dryRunRequired
}

public struct GestureSafetyDecision: Equatable, Sendable {
    public let isAllowed: Bool
    public let rejection: GestureSafetyRejection?

    public init(isAllowed: Bool, rejection: GestureSafetyRejection?) {
        self.isAllowed = isAllowed
        self.rejection = rejection
    }
}

public struct GestureSafetyValidator: Sendable {
    public init() {}

    public func validate(
        _ gesture: PlannedGesture,
        exclusionZones: [ExclusionZone],
        calibrationConfirmed: Bool,
        emergencyStopActive: Bool,
        sessionPauseReason: String? = nil,
        liveInputEnabled: Bool
    ) -> GestureSafetyDecision {
        guard gesture.kind == .horizontalCarousel || gesture.kind == .verticalScroll || gesture.kind == .closeViewer else {
            return GestureSafetyDecision(isAllowed: false, rejection: .unsupportedGestureKind)
        }
        guard gesture.start.isInsideUnitSquare, gesture.end.isInsideUnitSquare else {
            return GestureSafetyDecision(isAllowed: false, rejection: .outsideWindow)
        }
        guard gesture.requiredSafeRegion.contains(gesture.start),
              gesture.requiredSafeRegion.contains(gesture.end) else {
            return GestureSafetyDecision(isAllowed: false, rejection: .outsideRequiredSafeRegion)
        }
        if let exclusion = exclusionZones.first(where: {
            $0.bounds.intersectsSegment(from: gesture.start, to: gesture.end)
        }) {
            return GestureSafetyDecision(
                isAllowed: false,
                rejection: .intersectsExclusionZone(exclusion.label)
            )
        }
        guard calibrationConfirmed else {
            return GestureSafetyDecision(isAllowed: false, rejection: .calibrationIncomplete)
        }
        if emergencyStopActive {
            return GestureSafetyDecision(isAllowed: false, rejection: .emergencyStopActive)
        }
        if let sessionPauseReason {
            return GestureSafetyDecision(isAllowed: false, rejection: .sessionPaused(sessionPauseReason))
        }
        guard liveInputEnabled else {
            return GestureSafetyDecision(isAllowed: false, rejection: .dryRunRequired)
        }
        return GestureSafetyDecision(isAllowed: true, rejection: nil)
    }
}

public struct MomentViewerDismissPlanner: Sendable {
    public init() {}

    public func proposal(from marks: [CalibrationMark]) -> PlannedGesture? {
        guard let mark = marks.last(where: {
            $0.context == .momentViewer && $0.kind == .safeMomentDismissGesture
        }) else {
            return nil
        }

        let x = mark.bounds.center.x
        return PlannedGesture(
            kind: .closeViewer,
            start: NormalizedPoint(x: x, y: mark.bounds.minY + mark.bounds.height * 0.045),
            end: NormalizedPoint(x: x, y: mark.bounds.minY + mark.bounds.height * 0.955),
            requiredSafeRegion: mark.bounds,
            rationale: "Calibrated letterbox-safe downward dismiss for the Moment viewer"
        )
    }
}

public struct InterstitialAdDismissPlanner: Sendable {
    public init() {}

    public func closeAction(observations: [OCRObservation] = []) -> PlannedAction {
        let text = observations.map(\.text).joined(separator: " ")
        let isStoreLanding = text.localizedCaseInsensitiveContains("Age Rating")
            || text.localizedCaseInsensitiveContains("In-App Purchases")
            || text.localizedCaseInsensitiveContains("Category")
        if isStoreLanding {
            let region = NormalizedRect(x: 0.045, y: 0.11, width: 0.14, height: 0.10)
            return PlannedAction(
                kind: .closeViewer,
                point: NormalizedPoint(x: 0.112, y: 0.16),
                requiredSafeRegion: region,
                rationale: "Dismiss the verified ad landing sheet using its top-left X"
            )
        }
        // Measured from the supervised 420x932 iPhone Mirroring capture. Unlike
        // Moment chrome, the interstitial close control is always at top-right.
        let region = NormalizedRect(x: 0.83, y: 0.09, width: 0.13, height: 0.09)
        return PlannedAction(
            kind: .closeViewer,
            point: NormalizedPoint(x: 0.887, y: 0.132),
            requiredSafeRegion: region,
            rationale: "Dismiss the verified full-screen ad using its top-right X"
        )
    }
}

public struct GalleryGesturePlanner: Sendable {
    public init() {}

    public func proposal(from marks: [CalibrationMark]) -> PlannedGesture? {
        guard let mark = marks.first(where: {
            $0.context == .profile && $0.kind == .safeCarouselGesture
        }) else {
            return nil
        }

        let y = mark.bounds.center.y
        return PlannedGesture(
            kind: .horizontalCarousel,
            start: NormalizedPoint(x: mark.bounds.minX + mark.bounds.width * 0.78, y: y),
            end: NormalizedPoint(x: mark.bounds.minX + mark.bounds.width * 0.22, y: y),
            requiredSafeRegion: mark.bounds,
            rationale: "Dry-run preview for the Suggested for You horizontal gallery"
        )
    }
}
