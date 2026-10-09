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
        XCTAssertEqual(rejected(gate.review(scroll, on: unknown)), .unsupportedAction)
        if case .approved(.wait) = gate.review(proposal(action: .wait, expectation: nil), on: unknown) {} else {
            XCTFail("Expected an inert wait")
        }
    }

    func testOverlayScreensCannotBeTappedOrScrolledEvenWithPlausibleOCR() {
        let gate = VisualAgentSafetyGate()
        let scroll = proposal(action: .scrollDown, expectation: .init(kind: .frameChanged))
        for screen in ["unknown", "interstitialAd", "momentViewer", "profileOverflowMenu", "momentDetails"] {
            let frame = VisualAgentFrame(id: "frame-1", screenKind: screen,
                                         visibleText: ["About Me"], elements: observation().elements,
                                         exclusions: [])
            XCTAssertEqual(rejected(gate.review(proposal(), on: frame)), .unsupportedAction, screen)
            XCTAssertEqual(rejected(gate.review(scroll, on: frame)), .unsupportedAction, screen)
        }
    }

    func testFailedActionCannotReplayAfterOnlyScreenshotFingerprintChanges() async {
        let session = VisualAgentSession()
        _ = await session.propose(proposal(), on: observation())
        let first = await session.verify(on: observation(id: "cursor-blink-2"))
        XCTAssertEqual(first, .replan)
        let response = await session.propose(proposal(id: "cursor-blink-2"),
                                             on: observation(id: "cursor-blink-2"))
        XCTAssertEqual(rejected(response), .repeatedFailure)
    }

    func testChangingExpectedResultCannotAuthorizeSameFailedPhysicalClick() async {
        let session = VisualAgentSession()
        _ = await session.propose(proposal(), on: observation())
        let outcome = await session.verify(on: observation(id: "visual-change"))
        XCTAssertEqual(outcome, .replan)
        let repackaged = VisualAgentProposal(
            frameID: "visual-change", action: .tapElement,
            elementID: "tab-about-me", expectation: .init(kind: .textAppeared, value: "Details"),
            confidence: 0.99, rationale: "Changed postcondition, same tap"
        )
        let repeatResult = await session.propose(repackaged, on: observation(id: "visual-change"))
        XCTAssertEqual(rejected(repeatResult), .repeatedFailure)
    }

    func testRotatingLocationBadgeCannotFakeScrollProgress() async {
        let session = VisualAgentSession()
        let before = VisualAgentFrame(id: "pixels-1", screenKind: "profileTop",
                                      visibleText: ["Example City 6:58pm"], elements: [],
                                      exclusions: [], stableObservationID: "stable-layout")
        let after = VisualAgentFrame(id: "pixels-2", screenKind: "profileTop",
                                     visibleText: ["576 People Nearby"], elements: [],
                                     exclusions: [], stableObservationID: "stable-layout")
        let intent = VisualAgentProposal(frameID: "pixels-1", action: .scrollDown,
                                         expectation: .init(kind: .frameChanged),
                                         confidence: 0.94, rationale: "Scroll to details")
        _ = await session.propose(intent, on: before)
        let result = await session.verify(on: after)
        XCTAssertEqual(result, .replan)
    }

    func testStableObservationChangeVerifiesScroll() async {
        let session = VisualAgentSession()
        let before = VisualAgentFrame(id: "pixels-1", screenKind: "profileTop",
                                      visibleText: ["Example City 6:58pm"], elements: [],
                                      exclusions: [], stableObservationID: "stable-layout-1")
        let after = VisualAgentFrame(id: "pixels-2", screenKind: "profileTop",
                                     visibleText: ["Example City 6:59pm"], elements: [],
                                     exclusions: [], stableObservationID: "stable-layout-2")
        let intent = VisualAgentProposal(frameID: "pixels-1", action: .scrollDown,
                                         expectation: .init(kind: .frameChanged),
                                         confidence: 0.94, rationale: "Scroll to details")
        _ = await session.propose(intent, on: before)
        let result = await session.verify(on: after)
        XCTAssertEqual(result, .verified)
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
        let alternative = VisualAgentProposal(frameID: "frame-3", action: .scrollDown,
                                              expectation: .init(kind: .frameChanged),
                                              confidence: 0.92, rationale: "Try a scroll instead")
        _ = await session.propose(alternative, on: observation(id: "frame-3"))
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

    private var syntheticPNG: Data { Data([137, 80, 78, 71, 13, 10, 26, 10, 1]) }

    func testDefaultFabricPreviewRefusesImageTransferBeforeTransport() async {
        let fake = FakeVisualFabricTransport()
        let client = VisualAgentFabricPreviewPlanner(transport: fake)
        do {
            _ = try await client.preview(goal: .locateDetails, modelPreference: .qwen,
                                         frame: observation(), syntheticFixturePNG: syntheticPNG)
            XCTFail("Default must deny synthetic fixture transfer")
        } catch VisualAgentInferenceError.fixtureTransferNotAuthorized {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let calls = await fake.count()
        XCTAssertEqual(calls, 0)
    }

    func testNoFabricTransportFailsClosedAndNoDirectProviderFallbackExists() async {
        let client = VisualAgentFabricPreviewPlanner(permitSyntheticFixtureTransfer: true)
        do {
            _ = try await client.preview(goal: .locateDetails, modelPreference: .minimax,
                                         frame: observation(), syntheticFixturePNG: syntheticPNG)
            XCTFail("Missing admitted Fabric transport must refuse")
        } catch VisualAgentInferenceError.transportUnavailable {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testMalformedSyntheticFixtureFailsBeforeTransport() async {
        let fake = FakeVisualFabricTransport()
        let client = VisualAgentFabricPreviewPlanner(transport: fake, permitSyntheticFixtureTransfer: true)
        do {
            _ = try await client.preview(goal: .locateDetails, modelPreference: .qwen,
                                         frame: observation(), syntheticFixturePNG: Data([1, 2]))
            XCTFail("Non-PNG data must refuse")
        } catch VisualAgentInferenceError.invalidSyntheticFixture {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        let calls = await fake.count()
        XCTAssertEqual(calls, 0)
    }

    func testFabricRoutePreferenceIsNotDirectProviderSelection() async throws {
        let fake = FakeVisualFabricTransport()
        let client = VisualAgentFabricPreviewPlanner(transport: fake, permitSyntheticFixtureTransfer: true)
        let result = try await client.preview(goal: .locateNavigationTab, modelPreference: .qwen,
                                              frame: observation(), syntheticFixturePNG: syntheticPNG)
        let family = await fake.lastPreference()
        XCTAssertEqual(family, .qwen)
        XCTAssertEqual(result.reportedProviderProfile, "synthetic-plan")
        if case .approved(.tap) = result.review {} else { XCTFail("Expected safe, inert preview") }
    }

    func testFabricResultWrongFrameAndUngroundedTargetFailClosed() async throws {
        let fake = FakeVisualFabricTransport()
        let client = VisualAgentFabricPreviewPlanner(transport: fake, permitSyntheticFixtureTransfer: true)
        await fake.setWrongFrame(true)
        do {
            _ = try await client.preview(goal: .locateDetails, modelPreference: .minimax,
                                         frame: observation(), syntheticFixturePNG: syntheticPNG)
            XCTFail("Wrong Fabric frame must refuse")
        } catch VisualAgentInferenceError.staleFabricResult {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
        await fake.setWrongFrame(false)
        await fake.setHallucinatedControl(true)
        let result = try await client.preview(goal: .locateDetails, modelPreference: .minimax,
                                              frame: observation(), syntheticFixturePNG: syntheticPNG)
        XCTAssertEqual(rejected(result.review), .unsafeElement)
    }
}

private actor FakeVisualFabricTransport: VisualAgentFabricPreviewTransport {
    private var invocationCount = 0
    private var preference: VisualAgentModelPreference?
    private var wrongFrame = false
    private var hallucinatedControl = false

    func setWrongFrame(_ value: Bool) { wrongFrame = value }
    func setHallucinatedControl(_ value: Bool) { hallucinatedControl = value }
    func count() -> Int { invocationCount }
    func lastPreference() -> VisualAgentModelPreference? { preference }

    func inferSyntheticPreview(_ request: VisualAgentFabricPreviewRequest) async throws -> VisualAgentFabricPreviewResponse {
        invocationCount += 1
        preference = request.modelPreference
        let elementID = hallucinatedControl ? "invented-element" : "tab-about-me"
        let json = #"{"schema_version":"visual-agent.v1","frame_id":"frame-1","action":"tap_element","element_id":"ELEMENT","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.95,"rationale":"Synthetic fixture"}"#
            .replacingOccurrences(of: "ELEMENT", with: elementID)
        return VisualAgentFabricPreviewResponse(
            frameID: wrongFrame ? "incorrect-frame" : request.frameID,
            proposalJSON: Data(json.utf8),
            reportedProviderProfile: "synthetic-plan",
            reportedServedModel: "synthetic-model"
        )
    }
}
