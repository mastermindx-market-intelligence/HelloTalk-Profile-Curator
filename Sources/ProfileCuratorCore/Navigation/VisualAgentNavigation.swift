import Foundation

/// A dry-run, source-bound navigation proposal. No model has authority to emit desktop input.
public enum VisualAgentAction: String, Codable, Sendable {
    case tapElement = "tap_element"
    case scrollUp = "scroll_up"
    case scrollDown = "scroll_down"
    case wait
    case pause
}

public enum VisualAgentElementRole: String, Codable, Sendable {
    case navigation
    case dismiss
    case content
    case social
    case advertising
    case unknown
}

public struct VisualAgentElement: Sendable {
    public let id: String
    public let label: String
    public let role: VisualAgentElementRole
    public let actionKind: PlannedActionKind
    public let bounds: NormalizedRect

    public init(id: String, label: String, role: VisualAgentElementRole,
                actionKind: PlannedActionKind, bounds: NormalizedRect) {
        self.id = id
        self.label = label
        self.role = role
        self.actionKind = actionKind
        self.bounds = bounds
    }
}

public struct VisualAgentFrame: Sendable {
    public let id: String
    public let screenKind: String
    public let visibleText: [String]
    public let elements: [VisualAgentElement]
    public let exclusions: [ExclusionZone]

    public init(id: String, screenKind: String, visibleText: [String],
                elements: [VisualAgentElement], exclusions: [ExclusionZone]) {
        self.id = id
        self.screenKind = screenKind
        self.visibleText = visibleText
        self.elements = elements
        self.exclusions = exclusions
    }
}

public struct VisualAgentExpectation: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case screenKind = "screen_kind"
        case textAppeared = "text_appeared"
        case textDisappeared = "text_disappeared"
        case frameChanged = "frame_changed"
    }

    public let kind: Kind
    public let value: String?

    public init(kind: Kind, value: String? = nil) {
        self.kind = kind
        self.value = value
    }
}

public struct VisualAgentProposal: Codable, Sendable {
    public let schemaVersion: String
    public let frameID: String
    public let action: VisualAgentAction
    public let elementID: String?
    public let expectation: VisualAgentExpectation?
    public let confidence: Double
    public let rationale: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case frameID = "frame_id"
        case action
        case elementID = "element_id"
        case expectation, confidence, rationale
    }

    public init(schemaVersion: String = "visual-agent.v1", frameID: String,
                action: VisualAgentAction, elementID: String? = nil,
                expectation: VisualAgentExpectation? = nil,
                confidence: Double, rationale: String) {
        self.schemaVersion = schemaVersion
        self.frameID = frameID
        self.action = action
        self.elementID = elementID
        self.expectation = expectation
        self.confidence = confidence
        self.rationale = rationale
    }

    /// No markdown fences, trailing prose, oversized answers, or alternate schemas.
    public static func decodeJSON(_ bytes: Data) throws -> VisualAgentProposal {
        guard !bytes.isEmpty, bytes.count <= 8_192 else { throw VisualAgentRejection.malformedOutput }
        return try JSONDecoder().decode(Self.self, from: bytes)
    }
}

public enum VisualAgentRejection: Error, Equatable, Sendable {
    case staleFrame
    case malformedOutput
    case unsupportedAction
    case lowConfidence
    case unsafeElement
    case forbiddenLabel
    case invalidGeometry
    case excludedRegion
    case missingSemanticExpectation
    case unresolvedAction
    case repeatedFailure
    case paused
}

/// Only proposals; input authority remains with the existing SafeInputExecutor.
public enum VisualAgentPreview: Sendable {
    case tap(PlannedAction, VisualAgentExpectation)
    case scroll(lines: Int, point: NormalizedPoint)
    case wait
    case pause
}

public enum VisualAgentReview: Sendable {
    case approved(VisualAgentPreview)
    case rejected(VisualAgentRejection)
}

public struct VisualAgentSafetyGate: Sendable {
    public init() {}

    public func review(_ proposal: VisualAgentProposal, on frame: VisualAgentFrame) -> VisualAgentReview {
        guard proposal.schemaVersion == "visual-agent.v1",
              !frame.id.isEmpty, frame.id == proposal.frameID else { return .rejected(.staleFrame) }
        guard proposal.confidence.isFinite, (0...1).contains(proposal.confidence),
              !proposal.rationale.isEmpty, proposal.rationale.count <= 600 else {
            return .rejected(.malformedOutput)
        }
        switch proposal.action {
        case .pause:
            return .approved(.pause)
        case .wait:
            return .approved(.wait)
        case .tapElement:
            // A plausible OCR tab is not proof that we are still on a profile.
            // Never navigate an ad, viewer, popup, or unrecognized surface.
            guard Self.tabScreens.contains(frame.screenKind) else {
                return .rejected(.unsupportedAction)
            }
            guard proposal.confidence >= 0.85 else { return .rejected(.lowConfidence) }
            guard let id = proposal.elementID, !id.isEmpty,
                  frame.elements.filter({ $0.id == id }).count == 1,
                  let element = frame.elements.first(where: { $0.id == id }) else {
                return .rejected(.unsafeElement)
            }
            guard element.role == .navigation || element.role == .dismiss,
                  !element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(.unsafeElement)
            }
            guard !Self.isForbiddenControl(element.label) else { return .rejected(.forbiddenLabel) }
            guard Self.allowedNavigationKinds.contains(element.actionKind) else { return .rejected(.unsupportedAction) }
            guard element.bounds.isValidNormalizedRect,
                  element.bounds.width >= 0.015, element.bounds.height >= 0.015 else {
                return .rejected(.invalidGeometry)
            }
            guard !frame.exclusions.contains(where: { Self.overlaps($0.bounds, element.bounds) }) else {
                return .rejected(.excludedRegion)
            }
            guard let expectation = proposal.expectation,
                  Self.validTapExpectation(expectation, before: frame) else {
                return .rejected(.missingSemanticExpectation)
            }
            let action = PlannedAction(kind: element.actionKind,
                                       point: element.bounds.center,
                                       requiredSafeRegion: element.bounds,
                                       rationale: "AI preview: \(element.id)")
            // Geometry/exclusion gate only. This is NOT an input authorization.
            let geometry = ActionSafetyValidator().validate(action, exclusionZones: frame.exclusions,
                                                            emergencyStopActive: false,
                                                            liveInputEnabled: true)
            guard geometry.isAllowed else { return .rejected(.excludedRegion) }
            return .approved(.tap(action, expectation))
        case .scrollUp, .scrollDown:
            guard Self.scrollScreens.contains(frame.screenKind) else {
                return .rejected(.unsupportedAction)
            }
            guard proposal.confidence >= 0.7 else { return .rejected(.lowConfidence) }
            guard proposal.expectation?.kind == .frameChanged else {
                return .rejected(.missingSemanticExpectation)
            }
            // Scrolling uses the existing bounded, excluded-zone-aware input executor in future wiring.
            let point = NormalizedPoint(x: 0.5, y: 0.48)
            guard !frame.exclusions.contains(where: { $0.bounds.contains(point) }) else {
                return .rejected(.excludedRegion)
            }
            return .approved(.scroll(lines: proposal.action == .scrollUp ? 5 : -5, point: point))
        }
    }

    private static let tabScreens: Set<String> = [
        "profileTop", "profilePersonalInfo", "suggestedProfilesGallery", "momentsFeed"
    ]

    private static let scrollScreens: Set<String> = tabScreens.union(["connectFeed", "customSearch"])

    private static let allowedNavigationKinds: Set<PlannedActionKind> = [
        .back, .closeViewer, .selectAboutMe, .selectMoments, .openAvatar,
        .openRecommendationCard, .openCustomSearchResult, .openMomentThumbnail,
        .refreshCustomSearch, .showViewerChrome
    ]

    public static func isForbiddenControl(_ label: String) -> Bool {
        let pattern = #"(?i)(?:^|[^a-z])(?:say\s+hi|follow|like|gift|message|chat|comment|share|download|send|buy|subscribe|purchase|shop|payment|block|report)(?:$|[^a-z])"#
        return label.range(of: pattern, options: .regularExpression) != nil
    }

    private static func overlaps(_ a: NormalizedRect, _ b: NormalizedRect) -> Bool {
        a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }

    private static func contains(_ needle: String, in haystack: [String]) -> Bool {
        haystack.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private static func validTapExpectation(_ expected: VisualAgentExpectation,
                                            before: VisualAgentFrame) -> Bool {
        guard let value = expected.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 100 else { return false }
        switch expected.kind {
        case .screenKind:
            return value != "unknown" && value != before.screenKind
        case .textAppeared:
            return !contains(value, in: before.visibleText)
        case .textDisappeared:
            return contains(value, in: before.visibleText)
        case .frameChanged:
            return false // A hash change alone never proves that a tap went to the right screen.
        }
    }
}

public enum VisualAgentVerification: Sendable, Equatable {
    case verified
    case replan
    case needsHuman
    case nothingPending
}

/// Ephemeral session coordination: no process, network, database, or desktop input.
public actor VisualAgentSession {
    private struct Pending {
        let before: VisualAgentFrame
        let proposal: VisualAgentProposal
    }
    private var pending: Pending?
    private var failedSignature: String?
    private var failures = 0
    private var waits = 0
    private var stopped = false

    public init() {}

    public func propose(_ proposal: VisualAgentProposal, on frame: VisualAgentFrame) -> VisualAgentReview {
        guard !stopped else { return .rejected(.paused) }
        guard pending == nil else { return .rejected(.unresolvedAction) }
        let signature = Self.signature(proposal)
        guard !(failedSignature == signature && failures > 0) else { return .rejected(.repeatedFailure) }
        let result = VisualAgentSafetyGate().review(proposal, on: frame)
        if case .approved(let preview) = result {
            switch preview {
            case .tap, .scroll:
                pending = Pending(before: frame, proposal: proposal)
                waits = 0
            case .wait:
                waits += 1
                if waits > 3 { stopped = true; return .rejected(.repeatedFailure) }
            case .pause:
                stopped = true
            }
        }
        return result
    }

    /// Called only after the host observes the result of a single reviewed action.
    public func verify(on after: VisualAgentFrame) -> VisualAgentVerification {
        guard let old = pending else { return .nothingPending }
        pending = nil
        let before = old.before
        let proposal = old.proposal
        let changed = !after.id.isEmpty && before.id != after.id
        let expected = proposal.expectation
        var passed = false
        if changed, let expected {
            switch expected.kind {
            case .frameChanged:
                // A blinking cursor/video is not proof of a successful scroll.
                passed = before.screenKind != after.screenKind || before.visibleText != after.visibleText
            case .screenKind:
                passed = after.screenKind == expected.value && before.screenKind != after.screenKind
            case .textAppeared:
                if let value = expected.value {
                    passed = !before.visibleText.contains(where: { $0.localizedCaseInsensitiveContains(value) }) &&
                             after.visibleText.contains(where: { $0.localizedCaseInsensitiveContains(value) })
                }
            case .textDisappeared:
                if let value = expected.value {
                    passed = before.visibleText.contains(where: { $0.localizedCaseInsensitiveContains(value) }) &&
                             !after.visibleText.contains(where: { $0.localizedCaseInsensitiveContains(value) })
                }
            }
        }
        if passed { failures = 0; failedSignature = nil; return .verified }
        failures += 1
        failedSignature = Self.signature(proposal)
        if failures >= 2 { stopped = true; return .needsHuman }
        return .replan
    }

    public func stop() { stopped = true; pending = nil }

    /// Deliberate user action only; never automatically clear the pause/stop gate.
    public func resetByUser() {
        stopped = false; pending = nil; failures = 0; waits = 0; failedSignature = nil
    }

    private static func signature(_ proposal: VisualAgentProposal) -> String {
        // Different screenshot bytes may be only a blinking cursor or animation.
        // Failed semantic actions cannot be retried just by changing the frame ID.
        "\(proposal.action.rawValue)|\(proposal.elementID ?? "")|\(proposal.expectation?.kind.rawValue ?? "")|\(proposal.expectation?.value ?? "")"
    }
}
