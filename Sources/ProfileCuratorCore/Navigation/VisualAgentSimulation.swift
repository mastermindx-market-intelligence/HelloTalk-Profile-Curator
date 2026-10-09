import Foundation

/// Offline decision source. A fixture implementation is not measured AI inference.
/// The request includes the actually observed frame and the previous verification
/// so that recovery decisions consume feedback instead of replaying a fixed tap.
public struct VisualAgentSimulationRequest: Sendable {
    public let step: Int
    public let frame: VisualAgentFrame
    public let previousVerification: VisualAgentVerification?
    public var prompt: String {
        VisualAgentPrompt.system + "\n" +
        VisualAgentPrompt.user(goal: .locateNavigationTab, frame: frame)
    }
}

public protocol VisualAgentSimulationPlanner: Sendable {
    func response(to request: VisualAgentSimulationRequest) async throws -> Data?
}

/// JSON responses authored for regression only. The marker is replaced in the
/// parsed frame_id field, never in arbitrary JSON text. Explicit stale IDs remain
/// stale. Neither provider names nor invented latency are attached to these data.
public struct VisualAgentScriptedPlanner: VisualAgentSimulationPlanner {
    public let responses: [String]
    public init(responses: [String]) { self.responses = responses }

    public func response(to request: VisualAgentSimulationRequest) async throws -> Data? {
        guard responses.indices.contains(request.step) else { return nil }
        let bytes = Data(responses[request.step].utf8)
        guard bytes.count <= 8_192,
              var object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              object["frame_id"] as? String == "$CURRENT_FRAME" else { return bytes }
        object["frame_id"] = request.frame.id
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public enum VisualAgentSimulatedEffect: Sendable {
    case observe(VisualAgentFrame)
    case unchanged
    case missingObservation
    case withholdReceipt
    case mismatchedReceipt
}

public struct VisualAgentSimulationReceipt: Sendable {
    public let dispatchID: UUID
    public let sourceFrameID: String
}

/// Injected fake host: changes an in-memory frame only. This concrete type has no
/// InputDriver, window handle, CGEvent, network client, filesystem or live binding.
/// Effects are test-owner authored, independent of the model's claimed destination.
public actor VisualAgentSimulatedHost {
    private var frame: VisualAgentFrame?
    private let effects: [VisualAgentSimulatedEffect]
    public private(set) var dispatchCount = 0

    public init(initialFrame: VisualAgentFrame?, effects: [VisualAgentSimulatedEffect]) {
        frame = initialFrame
        self.effects = effects
    }

    public func observe() -> VisualAgentFrame? { frame }

    public func dispatch(_ proposal: VisualAgentProposal, dispatchID: UUID) -> VisualAgentSimulationReceipt? {
        guard let current = frame,
              case .approved(let preview) = VisualAgentSafetyGate().review(proposal, on: current) else { return nil }
        switch preview {
        case .wait, .pause: return nil
        case .tap, .scroll: break
        }
        let effect = effects.indices.contains(dispatchCount) ? effects[dispatchCount] : .unchanged
        dispatchCount += 1
        switch effect {
        case .observe(let next): frame = next
        case .missingObservation: frame = nil
        case .withholdReceipt: return nil
        case .mismatchedReceipt:
            return VisualAgentSimulationReceipt(dispatchID: UUID(), sourceFrameID: current.id)
        case .unchanged: break
        }
        return VisualAgentSimulationReceipt(dispatchID: dispatchID, sourceFrameID: current.id)
    }
}

public struct VisualAgentSimulationEvent: Codable, Sendable {
    public let step: Int
    public let stage: String
    public let frameID: String?
    public let detail: String
}

public enum VisualAgentSimulationStop: String, Codable, Sendable {
    case plannerPause, missingResponse, malformedResponse, rejectedProposal
    case missingReceipt, mismatchedReceipt, invalidFrame, plannerError
    case stepLimit, userStop, needsHuman, alreadyStopped, alreadyRunning
}

public struct VisualAgentSimulationReport: Encodable, Sendable {
    public let schemaVersion = "visual-agent.simulation-report.v1"
    public let evidenceKind = "offline_simulation_no_model_inference"
    public let stopReason: VisualAgentSimulationStop
    public let verifiedActions: Int
    public let simulatedDispatchAttempts: Int
    public let acknowledgedDispatches: Int
    public let events: [VisualAgentSimulationEvent]
}

/// Bounded decision -> deterministic review -> fake dispatch -> acknowledgment
/// -> fresh observation -> semantic verification -> feedback/recovery/STOP.
/// A stopped instance cannot restart itself. Create a new test instance explicitly.
public actor VisualAgentSimulationLoop {
    private let session = VisualAgentSession()
    private var stopped = false
    private var running = false

    public init() {}

    public func stop() async {
        stopped = true
        await session.stop()
    }

    public func run(planner: any VisualAgentSimulationPlanner, host: VisualAgentSimulatedHost,
                    maximumSteps: Int = 8) async -> VisualAgentSimulationReport {
        func empty(_ reason: VisualAgentSimulationStop) -> VisualAgentSimulationReport {
            .init(stopReason: reason, verifiedActions: 0, simulatedDispatchAttempts: 0, acknowledgedDispatches: 0, events: [])
        }
        guard !stopped else { return empty(.alreadyStopped) }
        guard !running else { return empty(.alreadyRunning) }
        running = true
        let initialDispatchCount = await host.dispatchCount
        var events: [VisualAgentSimulationEvent] = []
        var verified = 0
        var acknowledged = 0
        var previous: VisualAgentVerification?
        var reason: VisualAgentSimulationStop = .stepLimit
        func record(_ step: Int, _ stage: String, _ frameID: String?, _ detail: String) {
            events.append(.init(step: step, stage: stage, frameID: frameID, detail: detail))
        }

        for step in 0..<max(0, min(maximumSteps, 16)) {
            guard !stopped, !Task.isCancelled else { reason = .userStop; break }
            guard let frame = await host.observe(), !frame.id.isEmpty,
                  frame.id.count <= 128, !frame.id.contains("\n") else { reason = .invalidFrame; break }
            record(step, "observation", frame.id, frame.screenKind)
            let bytes: Data?
            do {
                bytes = try await planner.response(to: .init(step: step, frame: frame, previousVerification: previous))
            } catch {
                reason = .plannerError
                break
            }
            guard !stopped, !Task.isCancelled else { reason = .userStop; break }
            guard let bytes, !bytes.isEmpty else { reason = .missingResponse; break }
            guard let proposal = try? VisualAgentProposal.decodeJSON(bytes) else { reason = .malformedResponse; break }
            record(step, "proposal", proposal.frameID, proposal.action.rawValue + " " + (proposal.elementID ?? ""))
            let review = await session.propose(proposal, on: frame)
            guard !stopped, !Task.isCancelled else { reason = .userStop; break }
            switch review {
            case .rejected(let rejection):
                record(step, "review", frame.id, "rejected: \(rejection)")
                reason = .rejectedProposal
            case .approved(let preview):
                record(step, "review", frame.id, "approved simulation only")
                switch preview {
                case .pause: reason = .plannerPause
                case .wait:
                    record(step, "recovery", frame.id, "wait; no host dispatch")
                    continue
                case .tap, .scroll:
                    let dispatchID = UUID()
                    record(step, "dispatch_attempt", frame.id, "in-memory simulated action \(dispatchID)")
                    guard let receipt = await host.dispatch(proposal, dispatchID: dispatchID) else {
                        reason = .missingReceipt
                        break
                    }
                    record(step, "dispatch", frame.id, "simulated host receipt \(receipt.dispatchID)")
                    guard !stopped, !Task.isCancelled else { reason = .userStop; break }
                    guard receipt.dispatchID == dispatchID, receipt.sourceFrameID == frame.id else {
                        reason = .mismatchedReceipt
                        break
                    }
                    guard await session.acknowledgeHostDispatch(for: receipt.sourceFrameID) else {
                        reason = .mismatchedReceipt
                        break
                    }
                    acknowledged += 1
                    record(step, "acknowledgment", frame.id, "exact simulated dispatch acknowledged")
                    guard let after = await host.observe(), !after.id.isEmpty else { reason = .invalidFrame; break }
                    record(step, "observation", after.id, after.screenKind)
                    guard !stopped, !Task.isCancelled else { reason = .userStop; break }
                    let result = await session.verify(on: after)
                    previous = result
                    record(step, "verification", after.id, "\(result)")
                    switch result {
                    case .verified:
                        verified += 1
                        continue
                    case .replan:
                        record(step, "recovery", after.id, "replan; same failed physical action stays blocked")
                        continue
                    case .needsHuman: reason = .needsHuman
                    case .awaitingHostDispatch, .nothingPending: reason = .mismatchedReceipt
                    }
                }
            }
            break
        }
        stopped = true
        await session.stop()
        let dispatchAttempts = await host.dispatchCount - initialDispatchCount
        running = false
        record(events.last?.step ?? 0, "stop", events.last?.frameID, reason.rawValue)
        return .init(stopReason: reason, verifiedActions: verified, simulatedDispatchAttempts: dispatchAttempts,
                     acknowledgedDispatches: acknowledged, events: events)
    }
}
