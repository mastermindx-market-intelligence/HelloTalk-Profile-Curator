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
        proposals(from: marks).first
    }

    public func proposals(from marks: [CalibrationMark]) -> [PlannedGesture] {
        guard let mark = marks.last(where: {
            $0.context == .momentViewer && $0.kind == .safeMomentDismissGesture
        }) else {
            return []
        }

        // A Moment image can occasionally treat a rapid mouse drag as a tap and
        // merely toggle its transient chrome. Use three distinct, still-calibrated
        // vertical paths so a retry never repeats an ineffective gesture exactly.
        let paths: [(x: Double, startY: Double, endY: Double, label: String)] = [
            (0.50, 0.03, 0.97, "center"),
            (0.36, 0.07, 0.99, "left-center"),
            (0.64, 0.02, 0.99, "right-center")
        ]
        return paths.map { path in
            PlannedGesture(
                kind: .closeViewer,
                start: NormalizedPoint(
                    x: mark.bounds.minX + mark.bounds.width * path.x,
                    y: mark.bounds.minY + mark.bounds.height * path.startY
                ),
                end: NormalizedPoint(
                    x: mark.bounds.minX + mark.bounds.width * path.x,
                    y: mark.bounds.minY + mark.bounds.height * path.endY
                ),
                requiredSafeRegion: mark.bounds,
                rationale: "Calibrated \(path.label) downward dismiss for the Moment viewer"
            )
        }
    }
}

public struct InterstitialAdDismissPlanner: Sendable {
    public init() {}

    public func closeAction(observations: [OCRObservation] = []) -> PlannedAction? {
        let text = observations.map(\.text).joined(separator: " ")
        let hasProfileTabs = text.localizedCaseInsensitiveContains("Moments")
            && (text.localizedCaseInsensitiveContains("About Me")
                || text.localizedCaseInsensitiveContains("Achievements"))
        guard !hasProfileTabs else { return nil }
        let isStoreLanding = text.localizedCaseInsensitiveContains("Age Rating")
            || text.localizedCaseInsensitiveContains("In-App Purchases")
            || text.localizedCaseInsensitiveContains("Category")
        let isAIPromo = text.localizedCaseInsensitiveContains("Share with")
            && text.localizedCaseInsensitiveContains("chatting")
        let genericAdMarkers = ["Install", "Ad-Free", "Sponsored", "Advertisement", "Download App"]
        guard isStoreLanding
                || isAIPromo
                || genericAdMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) else {
            return nil
        }
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

public struct ProfileOverflowMenuDismissPlanner: Sendable {
    public init() {}

    public func cancelAction(observations: [OCRObservation]) -> PlannedAction? {
        guard let cancel = observations
            .filter({
                $0.confidence >= 0.45
                    && $0.text.localizedCaseInsensitiveContains("Cancel")
                    && $0.bounds.center.y >= 0.72
            })
            .max(by: { $0.bounds.center.y < $1.bounds.center.y }) else {
            return nil
        }
        let width = max(0.24, cancel.bounds.width + 0.12)
        let height = max(0.065, cancel.bounds.height + 0.035)
        let minX = min(max(0.03, cancel.bounds.center.x - width / 2), 0.97 - width)
        let minY = min(max(0.70, cancel.bounds.center.y - height / 2), 0.97 - height)
        let region = NormalizedRect(x: minX, y: minY, width: width, height: height)
        return PlannedAction(
            kind: .closeViewer,
            point: cancel.bounds.center,
            requiredSafeRegion: region,
            rationale: "Dismiss the verified profile overflow menu using Cancel"
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
