import Foundation

private struct VLMHealth: Sendable {}
public protocol VLMClientProtocol: Sendable {
    func generateJSON(prompt: String, images: [Data]) async throws -> Data
}

private actor FakeOllama: VLMClientProtocol {
    var latestPrompt: String = ""
    func generateJSON(prompt: String, images: [Data]) async throws -> Data {
        latestPrompt = prompt
        precondition(images.count == 1)
        return #"{"schema_version":"visual-agent.v1","frame_id":"f1","action":"tap_element","element_id":"tab-about","expectation":{"kind":"screen_kind","value":"details"},"confidence":0.93,"rationale":"Observed About tab"}"#.data(using: .utf8)!
    }
}

private enum Smoke {
    static func assert(_ b: Bool, _ label: String) {
        if !b { fatalError("FAILED: \(label)") }
    }
    static func frame(id: String = "f1", target: VisualAgentElement? = nil,
                      blocked: Bool = false) -> VisualAgentFrame {
        let t = target ?? VisualAgentElement(id:"tab-about",label:"About Me",role:.navigation,
                  actionKind:.selectAboutMe,bounds:NormalizedRect(x:0.1,y:0.3,width:0.2,height:0.07))
        let exclusions = blocked ? [ExclusionZone(label:"social",bounds:NormalizedRect(x:0.15,y:0.28,width:0.10,height:0.11))] : []
        return VisualAgentFrame(id:id,screenKind:"profileTop",visibleText:["About Me"],elements:[t],exclusions:exclusions)
    }
    static func proposal(id: String="f1",action:VisualAgentAction = .tapElement,
                         element:String?="tab-about",confidence:Double=0.95,
                         expectation:VisualAgentExpectation?=VisualAgentExpectation(kind:.screenKind,value:"details")) -> VisualAgentProposal {
        VisualAgentProposal(frameID:id,action:action,elementID:element,expectation:expectation,confidence:confidence,rationale:"Navigate")
    }
    static func isApproved(_ d:VisualAgentReview) -> Bool { if case .approved = d {return true};return false }
    static func rejection(_ d:VisualAgentReview) -> VisualAgentRejection? { if case .rejected(let x) = d { return x };return nil }
}

@main struct AgentSmokeRunner {
    static func main() async throws {
        let gate=VisualAgentSafetyGate()
        Smoke.assert(Smoke.isApproved(gate.review(Smoke.proposal(),on:Smoke.frame())),"valid tap")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(id:"old"),on:Smoke.frame())) == .staleFrame,"stale")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(confidence:0.4),on:Smoke.frame())) == .lowConfidence,"confidence")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:Smoke.frame(blocked:true))) == .excludedRegion,"overlapping exclusion")
        let social=VisualAgentElement(id:"tab-about",label:"Say Hi",role:.navigation,actionKind:.selectAboutMe,bounds:NormalizedRect(x:0.1,y:0.2,width:0.2,height:0.05))
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:Smoke.frame(target:social))) == .forbiddenLabel,"forbidden label")
        let wrongRole=VisualAgentElement(id:"tab-about",label:"About Me",role:.social,actionKind:.selectAboutMe,bounds:NormalizedRect(x:0.1,y:0.2,width:0.2,height:0.05))
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:Smoke.frame(target:wrongRole))) == .unsafeElement,"social role")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(expectation:nil),on:Smoke.frame())) == .missingSemanticExpectation,"missing expectation")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(expectation:.init(kind:.frameChanged)),on:Smoke.frame())) == .missingSemanticExpectation,"hash-only tap")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(action:.scrollDown,element:nil,expectation:.init(kind:.frameChanged)),on:Smoke.frame())) == nil,"safe scroll")
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(action:.scrollDown,element:nil,expectation:.init(kind:.frameChanged)),on:.init(id:"f1",screenKind:"unknown",visibleText:[],elements:[],exclusions:[]))) == .missingSemanticExpectation,"unknown scroll")
        let two=VisualAgentFrame(id:"f1",screenKind:"profileTop",visibleText:[],elements:[Smoke.frame().elements[0],Smoke.frame().elements[0]],exclusions:[])
        Smoke.assert(Smoke.rejection(gate.review(Smoke.proposal(),on:two)) == .unsafeElement,"duplicate IDs")
        do {_ = try VisualAgentProposal.decodeJSON(Data(repeating:UInt8(32),count:8193));fatalError("oversize accepted")}
        catch VisualAgentRejection.malformedOutput {}
        let actor = VisualAgentSession()
        Smoke.assert(Smoke.isApproved(await actor.propose(Smoke.proposal(),on:Smoke.frame())),"session propose")
        Smoke.assert(Smoke.rejection(await actor.propose(Smoke.proposal(),on:Smoke.frame())) == .unresolvedAction,"pending latch")
        let after = VisualAgentFrame(id:"f2",screenKind:"details",visibleText:["Details"],elements:[],exclusions:[])
        Smoke.assert(await actor.verify(on:after) == .verified,"semantic verify")
        Smoke.assert(Smoke.isApproved(await actor.propose(Smoke.proposal(),on:Smoke.frame())),"fresh action")
        Smoke.assert(await actor.verify(on:Smoke.frame()) == .replan,"failed action")
        Smoke.assert(Smoke.rejection(await actor.propose(Smoke.proposal(),on:Smoke.frame())) == .repeatedFailure,"no blind identical retry")
        let actor2 = VisualAgentSession()
        Smoke.assert(Smoke.isApproved(await actor2.propose(Smoke.proposal(),on:Smoke.frame())),"fresh new session")
        Smoke.assert(await actor2.verify(on:Smoke.frame()) == .replan,"first failure")
        Smoke.assert(Smoke.isApproved(await actor2.propose(Smoke.proposal(id:"f3"),on:Smoke.frame(id:"f3"))),"replan new frame")
        Smoke.assert(await actor2.verify(on:Smoke.frame(id:"f3")) == .needsHuman,"bounded recovery")
        Smoke.assert(Smoke.rejection(await actor2.propose(Smoke.proposal(id:"f3"),on:Smoke.frame(id:"f3"))) == .paused,"stopped")
        let q=FakeOllama()
        let res=try await OllamaVisualAgent(client:q,allowPrivateNetworkImages:true).propose(goal:.locateNavigationTab,frame:Smoke.frame(),png:Data([1,2]))
        Smoke.assert(res.frameID == "f1","ollama result decoding")
        let prompt=await q.latestPrompt
        Smoke.assert(prompt.contains("tab-about"),"grounded element ID")
        Smoke.assert(!prompt.contains("Private biography"),"no private OCR supplied")
        let mini=MiniMaxVisualAgent(apiKey:"synthetic",allowOffDeviceImages:false)
        do { _ = try await mini.propose(goal:.locateDetails,frame:Smoke.frame(),png:Data([1,2]));fatalError("remote consent bypass") }
        catch VisualAgentInferenceError.offDeviceImagesNotAuthorized {}
        print("PASS: 22 offline visual-agent contract, gating, recovery and provider smoke assertions")
    }
}
