import Foundation
import XCTest
@testable import ProfileCuratorCore

final class VisualAgentNavigationTests: XCTestCase {
    private func observation(id: String = "frame-1", label: String = "About Me",
                             role: VisualAgentElementRole = .navigation,
                             exclusions: [ExclusionZone] = []) -> VisualAgentFrame {
        let el = VisualAgentElement(
            id: "tab-about-me", label: label, role: role, actionKind: .selectAboutMe,
            bounds: NormalizedRect(x: 0.1, y: 0.35, width: 0.2, height: 0.07)
        )
        return VisualAgentFrame(id: id, screenKind: "profileTop", visibleText: ["About Me"],
                                elements: [el], exclusions: exclusions)
    }

    private func proposal(id: String = "frame-1", action: VisualAgentAction = .tapElement,
                          expectation: VisualAgentExpectation? = .init(kind: .screenKind, value: "profilePersonalInfo"),
                          confidence: Double = 0.95) -> VisualAgentProposal {
        VisualAgentProposal(frameID: id, action: action, elementID: "tab-about-me",
                            expectation: expectation, confidence: confidence, rationale: "Open the navigation tab")
    }

    private func rejected(_ result: VisualAgentReview) -> VisualAgentRejection? {
        if case .rejected(let reason) = result { return reason }
        return nil
    }

    func testGroundedTapCanBePreviewedButNeverExecutedByCore() {
        let result = VisualAgentSafetyGate().review(proposal(), on: observation())
        guard case .approved(.tap(let plan, let expectation)) = result else {
            return XCTFail("Expected a preview-only proposal")
        }
        XCTAssertEqual(plan.kind, .selectAboutMe)
        XCTAssertEqual(plan.point.x, 0.2, accuracy: 0.00001)
        XCTAssertEqual(expectation.kind, .screenKind)
    }

    func testStaleFrameAndLowConfidenceFailClosed() {
        let gate = VisualAgentSafetyGate()
        XCTAssertEqual(rejected(gate.review(proposal(id: "old"), on: observation())), .staleFrame)
        XCTAssertEqual(rejected(gate.review(proposal(confidence: 0.3), on: observation())), .lowConfidence)
    }

    func testSocialRoleAndForbiddenLabelsCannotBecomeNavigation() {
        let gate = VisualAgentSafetyGate()
        XCTAssertEqual(rejected(gate.review(proposal(), on: observation(role: .social))), .unsafeElement)
        XCTAssertEqual(rejected(gate.review(proposal(), on: observation(label: "Say Hi"))), .forbiddenLabel)
        XCTAssertEqual(rejected(gate.review(proposal(), on: observation(label: "Follow"))), .forbiddenLabel)
        XCTAssertEqual(rejected(gate.review(proposal(), on: observation(label: "Gift"))), .forbiddenLabel)
    }

    func testOverlappingExcludedAreaRejectedEvenIfTapCenterOutside() {
        let exclusion = ExclusionZone(label: "Social", bounds: NormalizedRect(x: 0.29, y: 0.38, width: 0.12, height: 0.08))
        let frame = observation(exclusions: [exclusion])
        XCTAssertEqual(rejected(VisualAgentSafetyGate().review(proposal(), on: frame)), .excludedRegion)
    }

    func testSemanticExpectationIsMandatoryForTaps() {
        let gate = VisualAgentSafetyGate()
        XCTAssertEqual(rejected(gate.review(proposal(expectation: nil), on: observation())), .missingSemanticExpectation)
        XCTAssertEqual(rejected(gate.review(proposal(expectation: .init(kind: .frameChanged)), on: observation())), .missingSemanticExpectation)
        XCTAssertEqual(rejected(gate.review(proposal(expectation: .init(kind: .textAppeared, value: "About Me")), on: observation())), .missingSemanticExpectation)
    }

    func testUnknownScreenCannotBeScrolledAndWaitDoesNotEmitInput() {
        let gate = VisualAgentSafetyGate()
        let scroll = proposal(action: .scrollDown, expectation: .init(kind: .frameChanged))
        let unknown = VisualAgentFrame(id: "frame-1", screenKind: "unknown", visibleText: [], elements: [], exclusions: [])
        XCTAssertEqual(rejected(gate.review(scroll, on: unknown)), .missingSemanticExpectation)
        if case .approved(.wait) = gate.review(proposal(action: .wait, expectation: nil), on: unknown) {} else {
            XCTFail("Expected an inert wait")
        }
    }

    func testMalformedOrOversizedModelResponseRejected() {
        XCTAssertThrowsError(try VisualAgentProposal.decodeJSON(Data(repeating: 0, count: 8193)))
        XCTAssertThrowsError(try VisualAgentProposal.decodeJSON(Data("not json".utf8)))
        let raw = #"{"schema_version":"visual-agent.v1","frame_id":"f","action":"buy","confidence":0.9,"rationale":"no"}"#
        XCTAssertThrowsError(try VisualAgentProposal.decodeJSON(Data(raw.utf8)))
    }

    func testOnlyOnePendingActionAndSemanticPostconditionRequired() async {
        let session = VisualAgentSession()
        if case .approved(.tap) = await session.propose(proposal(), on: observation()) {} else { XCTFail("Expected proposal") }
        let pendingResponse = await session.propose(proposal(), on: observation())
        XCTAssertEqual(rejected(pendingResponse), .unresolvedAction)
        let different = VisualAgentFrame(id: "frame-2", screenKind: "profilePersonalInfo",
                                         visibleText: ["Details"], elements: [], exclusions: [])
        let status = await session.verify(on: different)
        XCTAssertEqual(status, .verified)
    }

    func testIdenticalFailedProposalDoesNotRetryBlindly() async {
        let session = VisualAgentSession()
        _ = await session.propose(proposal(), on: observation())
        let first = await session.verify(on: observation())
        XCTAssertEqual(first, .replan)
        let retriedResponse = await session.propose(proposal(), on: observation())
        XCTAssertEqual(rejected(retriedResponse), .repeatedFailure)
    }

    func testConsecutiveFailuresRequireHumanReset() async {
        let session = VisualAgentSession()
        _ = await session.propose(proposal(), on: observation())
        _ = await session.verify(on: observation())
        _ = await session.propose(proposal(id: "frame-3"), on: observation(id: "frame-3"))
        let result = await session.verify(on: observation(id: "frame-3"))
        XCTAssertEqual(result, .needsHuman)
        let pausedResponse = await session.propose(proposal(), on: observation())
        XCTAssertEqual(rejected(pausedResponse), .paused)
        await session.resetByUser()
        let rearmed = await session.propose(proposal(), on: observation())
        XCTAssertNil(rejected(rearmed))
    }

    func testPromptDoesNotSerializeRawOCR() {
        let frame = VisualAgentFrame(id: "frame-1", screenKind: "profileTop",
                                     visibleText: ["Private biography and identity text"],
                                     elements: observation().elements, exclusions: [])
        let prompt = VisualAgentPrompt.user(goal: .locateDetails, frame: frame)
        XCTAssertTrue(prompt.contains("tab-about-me"))
        XCTAssertFalse(prompt.contains("Private biography"))
    }

    func testRemoteModelRequiresExplicitOptIn() async {
        let model = MiniMaxVisualAgent(apiKey: "not-a-real-key")
        do {
            _ = try await model.propose(goal: .locateDetails, frame: observation(), png: Data([1]))
            XCTFail("Model must remain disabled by default")
        } catch VisualAgentInferenceError.offDeviceImagesNotAuthorized {
            // Correct: no URLSession request was sent.
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }
}
