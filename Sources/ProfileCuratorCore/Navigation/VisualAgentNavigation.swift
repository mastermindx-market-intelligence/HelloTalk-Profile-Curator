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

public struct VisualAgentElement: Codable, Sendable {
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

public struct VisualAgentFrame: Codable, Sendable {
    public let id: String
    /// OCR/layout fingerprint that excludes known rotating badges; not a pixel hash.
    public let stableObservationID: String?
    public let screenKind: String
    public let visibleText: [String]
    public let elements: [VisualAgentElement]
    public let exclusions: [ExclusionZone]

    public init(id: String, screenKind: String, visibleText: [String],
                elements: [VisualAgentElement], exclusions: [ExclusionZone],
                stableObservationID: String? = nil) {
        self.id = id
        self.stableObservationID = stableObservationID
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
        let allowed: Set<String> = ["schema_version", "frame_id", "action", "element_id", "expectation", "confidence", "rationale"]
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(object.keys).isSubset(of: allowed) else { throw VisualAgentRejection.malformedOutput }
        if let expectation = object["expectation"] as? [String: Any] {
            guard Set(expectation.keys).isSubset(of: ["kind", "value"]) else { throw VisualAgentRejection.malformedOutput }
        }
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
            guard element.role == .navigation,
                  !element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .rejected(.unsafeElement)
            }
            guard !Self.isForbiddenControl(element.label) else { return .rejected(.forbiddenLabel) }
            // Only the two OCR-grounded tab IDs are currently trusted. Do not
            // let model text promote arbitrary profile/photo/social actions.
            guard Self.expectedTabScreen(for: element) != nil else {
                return .rejected(.unsupportedAction)
            }
            guard element.bounds.isValidNormalizedRect,
                  element.bounds.width >= 0.015, element.bounds.height >= 0.015 else {
                return .rejected(.invalidGeometry)
            }
            guard !frame.exclusions.contains(where: { Self.overlaps($0.bounds, element.bounds) }) else {
                return .rejected(.excludedRegion)
            }
            guard let expectation = proposal.expectation,
                  Self.validTapExpectation(expectation, for: element, before: frame) else {
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
            guard let stableID = frame.stableObservationID, !stableID.isEmpty else {
                return .rejected(.missingSemanticExpectation)
            }
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

    /// Fixed tab mapping is an allowlist, not a deterministic navigation script.
    /// AI chooses the next tab or a scroll; no other controls are admitted yet.
    private static func expectedTabScreen(for element: VisualAgentElement) -> String? {
        if element.id == "tab-about-me" && element.label == "About Me" &&
           element.actionKind == .selectAboutMe { return "profilePersonalInfo" }
        if element.id == "tab-moments" && element.label == "Moments" &&
           element.actionKind == .selectMoments { return "momentsFeed" }
        return nil
    }

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
                                            for element: VisualAgentElement,
                                            before: VisualAgentFrame) -> Bool {
        guard let target = expectedTabScreen(for: element),
              let value = expected.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 100 else { return false }
        switch expected.kind {
        case .screenKind:
            return value == target && target != before.screenKind
        case .textAppeared:
            let anchors: Set<String> = target == "profilePersonalInfo"
                ? ["Personal Info"] : ["Posts", "No moments", "Album"]
            return anchors.contains(value) && !contains(value, in: before.visibleText)
        case .textDisappeared, .frameChanged:
            return false // Disappearance or a hash change cannot prove a tab arrived.
        }
    }
}

public enum VisualAgentVerification: Sendable, Equatable {
    case verified
    case replan
    case needsHuman
    case awaitingHostDispatch
    case nothingPending
}

/// Ephemeral session coordination: no process, network, database, or desktop input.
public actor VisualAgentSession {
    private struct Pending {
        let before: VisualAgentFrame
        let proposal: VisualAgentProposal
        var hostDispatched: Bool
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
                pending = Pending(before: frame, proposal: proposal, hostDispatched: false)
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

    /// Only the authorized host input executor may call this after an attempted
    /// action. Model output and an approved preview are NOT dispatch evidence.
    /// This is a host assertion, not a substitute for an actual executor receipt.
    public func acknowledgeHostDispatch(for frameID: String) -> Bool {
        guard !stopped, var item = pending, !item.hostDispatched,
              item.before.id == frameID else { return false }
        item.hostDispatched = true
        pending = item
        return true
    }

    /// Observe the postcondition ONLY after host-reported action dispatch. An
    /// unsolicited screenshot change cannot complete a proposal.
    public func verify(on after: VisualAgentFrame) -> VisualAgentVerification {
        guard let old = pending else { return .nothingPending }
        guard old.hostDispatched else { return .awaitingHostDispatch }
        pending = nil
        let before = old.before
        let proposal = old.proposal
        let changed = !after.id.isEmpty && before.id != after.id
        let expected = proposal.expectation
        var passed = false
        if changed, let expected {
            switch expected.kind {
            case .frameChanged:
                // The existing OCR fingerprint ignores rotating location/nearby
                // badges. Never count a timestamp/badge animation as scrolling.
                switch (before.stableObservationID, after.stableObservationID) {
                case (.some(let oldID), .some(let newID)):
                    // A scroll must preserve the recognized surface. An ad or
                    // popup replacing it is a recovery condition, not progress.
                    passed = before.screenKind == after.screenKind &&
                        !oldID.isEmpty && !newID.isEmpty && oldID != newID
                default:
                    // No reliable OCR-layout fingerprint: do not infer progress
                    // from animations, a rotating badge, or other text changes.
                    passed = false
                }
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
        if proposal.action == .tapElement,
           let id = proposal.elementID,
           let element = before.elements.first(where: { $0.id == id }),
           let requiredTarget = Self.expectedTabScreen(for: element.actionKind) {
            // Even a coincidental text match cannot validate a popup/ad/viewer.
            passed = passed && after.screenKind == requiredTarget
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

    private static func expectedTabScreen(for action: PlannedActionKind) -> String? {
        switch action {
        case .selectAboutMe: "profilePersonalInfo"
        case .selectMoments: "momentsFeed"
        default: nil
        }
    }

    private static func signature(_ proposal: VisualAgentProposal) -> String {
        // Different screenshot bytes may be only a blinking cursor or animation.
        // A model cannot reopen the *same physical input* by changing the
        // screenshot ID, the proposed postcondition, confidence, or rationale.
        "\(proposal.action.rawValue)|\(proposal.elementID ?? "")"
    }
}
