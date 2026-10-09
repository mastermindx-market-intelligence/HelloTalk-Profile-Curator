import Foundation

private actor FakeFabric: VisualAgentFabricPreviewTransport {
    var invocations = 0
    var lastPreference: VisualAgentModelPreference?
    var mismatchFrame = false
    var unsafeAnswer = false

    func inferSyntheticPreview(_ request: VisualAgentFabricPreviewRequest) async throws -> VisualAgentFabricPreviewResponse {
        invocations += 1
        lastPreference = request.modelPreference
        precondition(request.schemaVersion == "visual-agent.fabric-preview.v1")
        precondition(request.prompt.contains("tab-about-me"))
        precondition(request.syntheticFixturePNG.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let proposal = unsafeAnswer ?
            #"{"schema_version":"visual-agent.v1","frame_id":"f1","action":"tap_element","element_id":"made-up-id","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.99,"rationale":"Unsafe model output"}"# :
            #"{"schema_version":"visual-agent.v1","frame_id":"f1","action":"tap_element","element_id":"tab-about-me","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.93,"rationale":"Observed About tab"}"#
        return VisualAgentFabricPreviewResponse(frameID: mismatchFrame ? "wrong" : request.frameID,
                proposalJSON: Data(proposal.utf8), reportedProviderProfile: "synthetic-provider",
                reportedServedModel: "synthetic-model")
    }

    func setMismatch(_ value: Bool) { mismatchFrame = value }
    func setUnsafe(_ value: Bool) { unsafeAnswer = value }
    func count() -> Int { invocations }
    func preference() -> VisualAgentModelPreference? { lastPreference }
}

private enum Smoke {
    static func assert(_ b: Bool, _ label: String) { if !b { fatalError("FAILED: \(label)") } }
    static func frame(id: String = "f1", target: VisualAgentElement? = nil,
                      blocked: Bool = false) -> VisualAgentFrame {
        let t = target ?? VisualAgentElement(id: "tab-about-me", label: "About Me", role: .navigation,
            actionKind: .selectAboutMe, bounds: NormalizedRect(x: 0.1, y: 0.3, width: 0.2, height: 0.07))
        let exclusions = blocked ? [ExclusionZone(label: "social", bounds: NormalizedRect(x: 0.15, y: 0.28, width: 0.10, height: 0.11))] : []
        return VisualAgentFrame(id: id, screenKind: "profileTop", visibleText: ["About Me"], elements: [t], exclusions: exclusions, stableObservationID: "stable-top")
    }
    static func proposal(id: String = "f1", action: VisualAgentAction = .tapElement,
                         element: String? = "tab-about-me", confidence: Double = 0.95,
                         expectation: VisualAgentExpectation? = .init(kind: .screenKind, value: "profilePersonalInfo")) -> VisualAgentProposal {
        VisualAgentProposal(frameID: id, action: action, elementID: element,
            expectation: expectation, confidence: confidence, rationale: "Navigate")
    }
    static func isApproved(_ d: VisualAgentReview) -> Bool { if case .approved = d { return true }; return false }
    static func rejection(_ d: VisualAgentReview) -> VisualAgentRejection? { if case .rejected(let x) = d { return x }; return nil }
}

@main struct AgentSmokeRunner {
    static let fakePNG = Data([137,80,78,71,13,10,26,10,1]) // Synthetic protocol bytes; no real user image.
    static func main() async throws {
        let gate = VisualAgentSafetyGate()
        Smoke.assert(Smoke.isApproved(gate.review(Smoke.proposal(), on: Smoke.frame())), "valid tap")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(id:"old"), on: Smoke.frame())) == .staleFrame, "stale")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(confidence:0.4), on: Smoke.frame())) == .lowConfidence, "confidence")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(), on: Smoke.frame(blocked:true))) == .excludedRegion, "overlap")
        let social = VisualAgentElement(id:"tab-about-me",label:"Say Hi",role:.navigation,
             actionKind:.selectAboutMe,bounds:.init(x:0.1,y:0.2,width:0.2,height:0.05))
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:Smoke.frame(target:social))) == .forbiddenLabel,"forbidden")
        let role = VisualAgentElement(id:"tab-about-me",label:"About Me",role:.social,
             actionKind:.selectAboutMe,bounds:.init(x:0.1,y:0.2,width:0.2,height:0.05))
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:Smoke.frame(target:role))) == .unsafeElement,"social role")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(expectation:nil),on:Smoke.frame())) == .missingSemanticExpectation,"expected")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(expectation:.init(kind:.frameChanged)),on:Smoke.frame())) == .missingSemanticExpectation,"hash-only")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(action:.scrollDown,element:nil,expectation:.init(kind:.frameChanged)),on:Smoke.frame())) == nil,"scroll")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(action:.scrollDown,element:nil,expectation:.init(kind:.frameChanged)),on:.init(id:"f1",screenKind:"unknown",visibleText:[],elements:[],exclusions:[]))) == .unsupportedAction,"unknown")
        let duplicate = VisualAgentElement(id:"tab-about-me",label:"About Me",role:.navigation,actionKind:.selectAboutMe,bounds:.init(x:0.1,y:0.3,width:0.2,height:0.07))
        let two = VisualAgentFrame(id:"f1",screenKind:"profileTop",visibleText:[],elements:[duplicate,duplicate],exclusions:[])
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:two)) == .unsafeElement,"duplicate")
        do { _ = try VisualAgentProposal.decodeJSON(Data(repeating:32,count:8193)); fatalError("oversize accepted") }
        catch VisualAgentRejection.malformedOutput {}
        let actor = VisualAgentSession()
        Smoke.assert(Smoke.isApproved(await actor.propose(Smoke.proposal(),on:Smoke.frame())),"session")
        Smoke.assert(Smoke.rejection(await actor.propose(Smoke.proposal(),on:Smoke.frame())) == .unresolvedAction,"pending")
        Smoke.assert(await actor.acknowledgeHostDispatch(for:"f1"),"host dispatch receipt")
        Smoke.assert(await actor.verify(on:.init(id:"f2",screenKind:"profilePersonalInfo",visibleText:["Details"],elements:[],exclusions:[])) == .verified,"semantic")
        Smoke.assert(Smoke.isApproved(await actor.propose(Smoke.proposal(),on:Smoke.frame())),"new")
        Smoke.assert(await actor.acknowledgeHostDispatch(for:"f1"),"host dispatch receipt")
        Smoke.assert(await actor.verify(on:Smoke.frame()) == .replan,"replan")
        Smoke.assert(Smoke.rejection(await actor.propose(Smoke.proposal(),on:Smoke.frame())) == .repeatedFailure,"duplicate retry")
        let actor2 = VisualAgentSession()
        Smoke.assert(Smoke.isApproved(await actor2.propose(Smoke.proposal(),on:Smoke.frame())),"new session")
        Smoke.assert(await actor2.acknowledgeHostDispatch(for:"f1"),"host dispatch receipt")
        Smoke.assert(await actor2.verify(on:Smoke.frame()) == .replan,"fail")
        let alternate = Smoke.proposal(id:"f3",action:.scrollDown,element:nil,expectation:.init(kind:.frameChanged))
        Smoke.assert(Smoke.isApproved(await actor2.propose(alternate,on:Smoke.frame(id:"f3"))),"replan with different action")
        Smoke.assert(await actor2.acknowledgeHostDispatch(for:"f3"),"host dispatch receipt")
        Smoke.assert(await actor2.verify(on:Smoke.frame(id:"f3")) == .needsHuman,"bounded")
        Smoke.assert(Smoke.rejection(await actor2.propose(Smoke.proposal(id:"f3"),on:Smoke.frame(id:"f3"))) == .paused,"stopped")
        let fabric = FakeFabric()
        let disabled = VisualAgentFabricPreviewPlanner(transport:fabric)
        do { _ = try await disabled.preview(goal:.locateDetails,modelPreference:.qwen,frame:Smoke.frame(),syntheticFixturePNG:fakePNG);fatalError("opt-in bypass") }
        catch VisualAgentInferenceError.fixtureTransferNotAuthorized {}
        Smoke.assert(await fabric.count() == 0,"default sends no image")
        let missing = VisualAgentFabricPreviewPlanner(permitSyntheticFixtureTransfer:true)
        do { _ = try await missing.preview(goal:.locateDetails,modelPreference:.qwen,frame:Smoke.frame(),syntheticFixturePNG:fakePNG);fatalError("missing route accepted") }
        catch VisualAgentInferenceError.transportUnavailable {}
        let planner = VisualAgentFabricPreviewPlanner(transport:fabric,permitSyntheticFixtureTransfer:true)
        do { _ = try await planner.preview(goal:.locateDetails,modelPreference:.qwen,frame:Smoke.frame(),syntheticFixturePNG:Data([1,2]));fatalError("invalid image") }
        catch VisualAgentInferenceError.invalidSyntheticFixture {}
        Smoke.assert(await fabric.count() == 0,"invalid image blocked before call")
        let result = try await planner.preview(goal:.locateNavigationTab,modelPreference:.qwen,frame:Smoke.frame(),syntheticFixturePNG:fakePNG)
        Smoke.assert(Smoke.isApproved(result.review),"fabric response safely reviewed")
        Smoke.assert(await fabric.preference() == .qwen,"qwen is only preference")
        await fabric.setMismatch(true)
        do { _ = try await planner.preview(goal:.locateDetails,modelPreference:.minimax,frame:Smoke.frame(),syntheticFixturePNG:fakePNG);fatalError("stale receipt") }
        catch VisualAgentInferenceError.staleFabricResult {}
        await fabric.setMismatch(false)
        await fabric.setUnsafe(true)
        let bad = try await planner.preview(goal:.locateDetails,modelPreference:.minimax,frame:Smoke.frame(),syntheticFixturePNG:fakePNG)
        Smoke.assert(Smoke.rejection(bad.review) == .unsafeElement,"fabric cannot authorize hallucinated element")
        Smoke.assert(await fabric.preference() == .minimax,"minimax is preference, not direct API")
        print("PASS: offline navigation, bounded-recovery and Fabric-preview safety smoke assertions")
    }
}
