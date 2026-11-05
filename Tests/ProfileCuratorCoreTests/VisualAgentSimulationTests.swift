import Foundation
import XCTest
@testable import ProfileCuratorCore

final class VisualAgentSimulationTests: XCTestCase {
    private func frame(_ id: String = "a", screen: String = "profilePersonalInfo", stable: String? = "layout-a") -> VisualAgentFrame {
        let tabs = [
            VisualAgentElement(id: "tab-about-me", label: "About Me", role: .navigation, actionKind: .selectAboutMe,
                               bounds: .init(x: 0.1, y: 0.5, width: 0.2, height: 0.06)),
            VisualAgentElement(id: "tab-moments", label: "Moments", role: .navigation, actionKind: .selectMoments,
                               bounds: .init(x: 0.6, y: 0.5, width: 0.2, height: 0.06))
        ]
        return .init(id: id, screenKind: screen, visibleText: [], elements: tabs, exclusions: [], stableObservationID: stable)
    }

    private func json(_ action: VisualAgentAction = .tapElement, element: String? = "tab-moments",
                      target: String = "momentsFeed", id: String = "$CURRENT_FRAME") throws -> String {
        let expectation: VisualAgentExpectation? = action == .tapElement ? .init(kind: .screenKind, value: target)
            : (action == .scrollDown || action == .scrollUp ? .init(kind: .frameChanged) : nil)
        return String(decoding: try JSONEncoder().encode(VisualAgentProposal(frameID: id, action: action,
            elementID: element, expectation: expectation, confidence: 0.95, rationale: "Synthetic decision fixture")), as: UTF8.self)
    }

    func testMultiStepDecisionsDispatchObserveAndStop() async throws {
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [
            .observe(frame("b", screen: "momentsFeed", stable: "layout-b")),
            .observe(frame("c", screen: "momentsFeed", stable: "layout-c"))
        ])
        let planner = VisualAgentScriptedPlanner(responses: [try json(), try json(.scrollDown, element: nil), try json(.pause, element: nil)])
        let report = await VisualAgentSimulationLoop().run(planner: planner, host: host)
        XCTAssertEqual(report.stopReason, .plannerPause)
        XCTAssertEqual(report.verifiedActions, 2)
        XCTAssertEqual(report.acknowledgedDispatches, 2)
        XCTAssertEqual(report.events.filter { $0.stage == "dispatch" }.count, 2)
        XCTAssertEqual(report.events.last?.stage, "stop")
        let count = await host.dispatchCount
        XCTAssertEqual(count, 2)
    }

    func testWrongDestinationReplansThenUsesDifferentAction() async throws {
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [
            .observe(frame("b")), .observe(frame("c", stable: "layout-c"))
        ])
        let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [
            try json(), try json(.scrollDown, element: nil), try json(.pause, element: nil)
        ]), host: host)
        XCTAssertEqual(report.verifiedActions, 1)
        XCTAssertTrue(report.events.contains { $0.stage == "verification" && $0.detail == "replan" })
        XCTAssertTrue(report.events.contains { $0.stage == "recovery" })
        XCTAssertEqual(report.stopReason, .plannerPause)
    }

    func testRepeatedFailedActionCannotDispatchTwice() async throws {
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [.observe(frame("new-pixels"))])
        let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json(), try json()]), host: host)
        XCTAssertEqual(report.stopReason, .rejectedProposal)
        XCTAssertTrue(report.events.contains { $0.detail == "rejected: repeatedFailure" })
        let count = await host.dispatchCount
        XCTAssertEqual(count, 1)
    }

    func testTwoDifferentFailuresRequireHuman() async throws {
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [.unchanged, .unchanged])
        let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json(), try json(.scrollDown, element: nil)]), host: host)
        XCTAssertEqual(report.stopReason, .needsHuman)
        XCTAssertEqual(report.verifiedActions, 0)
        XCTAssertEqual(report.acknowledgedDispatches, 2)
    }

    func testMissingOrMismatchedReceiptCannotVerifyOrRetry() async throws {
        for effect in [VisualAgentSimulatedEffect.withholdReceipt, .mismatchedReceipt] {
            let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [effect])
            let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json(), try json()]), host: host)
            XCTAssertTrue([.missingReceipt, .mismatchedReceipt].contains(report.stopReason))
            XCTAssertEqual(report.verifiedActions, 0)
            XCTAssertEqual(report.acknowledgedDispatches, 0)
            let count = await host.dispatchCount
            XCTAssertEqual(count, 1)
        }
    }

    func testMissingAndMalformedResponsesNeverDispatch() async {
        for responses in [[], ["not JSON"], [String(repeating: "a", count: 8193)]] {
            let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [])
            let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: responses), host: host)
            XCTAssertTrue([.missingResponse, .malformedResponse].contains(report.stopReason))
            let count = await host.dispatchCount
            XCTAssertEqual(count, 0)
        }
    }

    func testStaleDuplicateResponseNeverDispatchesAgain() async throws {
        let oldResponse = try json(id: "a")
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [.observe(frame("b", screen: "momentsFeed"))])
        let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [oldResponse, oldResponse]), host: host)
        XCTAssertEqual(report.stopReason, .rejectedProposal)
        XCTAssertTrue(report.events.contains { $0.detail == "rejected: staleFrame" })
        let count = await host.dispatchCount
        XCTAssertEqual(count, 1)
    }

    func testUnsafeAndWrongExpectedTargetRefuseBeforeHost() async throws {
        for response in [try json(element: "say-hi"), try json(target: "profilePersonalInfo")] {
            let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [])
            let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [response]), host: host)
            XCTAssertEqual(report.stopReason, .rejectedProposal)
            let count = await host.dispatchCount
            XCTAssertEqual(count, 0)
        }
    }

    func testMissingFramesAndMissingPostActionObservationStop() async throws {
        let missing = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json()]),
            host: VisualAgentSimulatedHost(initialFrame: nil, effects: []))
        XCTAssertEqual(missing.stopReason, .invalidFrame)
        let after = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json()]),
            host: VisualAgentSimulatedHost(initialFrame: frame(), effects: [.missingObservation]))
        XCTAssertEqual(after.stopReason, .invalidFrame)
        XCTAssertEqual(after.verifiedActions, 0)
    }

    func testScrollCannotCountAdsUnknownOrEmptyLayoutAsProgress() async throws {
        for after in [frame("b", screen: "interstitialAd", stable: "new"), frame("b", screen: "unknown", stable: "new"), frame("b", stable: "")] {
            let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json(.scrollDown, element: nil), try json(.pause, element: nil)]),
                host: VisualAgentSimulatedHost(initialFrame: frame(), effects: [.observe(after)]))
            XCTAssertEqual(report.verifiedActions, 0)
            XCTAssertTrue(report.events.contains { $0.detail == "replan" })
        }
    }

    func testRotatingBadgeCannotSatisfyScrollAndWaitBudgetIsBounded() async throws {
        let report = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: [try json(.scrollDown, element: nil), try json(.pause, element: nil)]),
            host: VisualAgentSimulatedHost(initialFrame: frame(), effects: [.observe(frame("badge-animation"))]))
        XCTAssertEqual(report.verifiedActions, 0)
        let waits = try Array(repeating: json(.wait, element: nil), count: 8)
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [])
        let waiting = await VisualAgentSimulationLoop().run(planner: VisualAgentScriptedPlanner(responses: waits), host: host)
        XCTAssertEqual(waiting.stopReason, .rejectedProposal)
        let count = await host.dispatchCount
        XCTAssertEqual(count, 0)
    }

    func testStopAndStepLimitLatchWithoutAutomaticRestart() async throws {
        let loop = VisualAgentSimulationLoop()
        await loop.stop()
        let planner = VisualAgentScriptedPlanner(responses: [try json()])
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [])
        let stopped = await loop.run(planner: planner, host: host)
        XCTAssertEqual(stopped.stopReason, .alreadyStopped)
        let boundedLoop = VisualAgentSimulationLoop()
        let bounded = await boundedLoop.run(planner: planner, host: host, maximumSteps: 0)
        XCTAssertEqual(bounded.stopReason, .stepLimit)
        let second = await boundedLoop.run(planner: planner, host: host)
        XCTAssertEqual(second.stopReason, .alreadyStopped)
    }

    func testStopWhileDecisionIsPendingPreventsDispatchAndConcurrentRun() async throws {
        let loop = VisualAgentSimulationLoop()
        let host = VisualAgentSimulatedHost(initialFrame: frame(), effects: [])
        let planner = SuspendedSimulationPlanner()
        let task = Task { await loop.run(planner: planner, host: host) }
        await planner.waitUntilRequested()
        let concurrent = await loop.run(planner: planner, host: host)
        XCTAssertEqual(concurrent.stopReason, .alreadyRunning)
        await loop.stop()
        await planner.release(Data(try json(id: "a").utf8))
        let report = await task.value
        XCTAssertEqual(report.stopReason, .userStop)
        XCTAssertEqual(report.simulatedDispatchAttempts, 0)
        let count = await host.dispatchCount
        XCTAssertEqual(count, 0)
    }

    func testMissingAndMalformedLocalImagesFailClosed() throws {
        XCTAssertThrowsError(try VisualAgentLocalImageFrame.load(at: URL(fileURLWithPath: "/no-such-synthetic-image.png")))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([137, 80, 78, 71, 13, 10, 26, 10, 0]).write(to: url)
        XCTAssertThrowsError(try VisualAgentLocalImageFrame.load(at: url))
    }

    func testCoordinatesAndExtraActionsCannotBeSmuggledIntoDecisionJSON() throws {
        var object = try JSONSerialization.jsonObject(with: Data(json().utf8)) as! [String: Any]
        object["coordinates"] = ["x": 0.5, "y": 0.5]
        XCTAssertThrowsError(try VisualAgentProposal.decodeJSON(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "coordinates")
        object["expectation"] = ["kind": "screen_kind", "value": "momentsFeed", "next_action": "send_message"]
        XCTAssertThrowsError(try VisualAgentProposal.decodeJSON(JSONSerialization.data(withJSONObject: object)))
    }
}

private actor SuspendedSimulationPlanner: VisualAgentSimulationPlanner {
    private var requested = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var responseWaiter: CheckedContinuation<Data?, Never>?

    func response(to request: VisualAgentSimulationRequest) async throws -> Data? {
        requested = true
        requestWaiter?.resume()
        requestWaiter = nil
        return await withCheckedContinuation { responseWaiter = $0 }
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func release(_ response: Data) {
        responseWaiter?.resume(returning: response)
        responseWaiter = nil
    }
}
