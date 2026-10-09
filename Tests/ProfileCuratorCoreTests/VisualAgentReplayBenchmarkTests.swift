import Foundation
import XCTest
@testable import ProfileCuratorCore

final class VisualAgentReplayBenchmarkTests: XCTestCase {
    private func cases() -> [VisualAgentReplayCase] {
        let about = VisualAgentElement(id: "tab-about-me", label: "About Me", role: .navigation,
                                       actionKind: .selectAboutMe,
                                       bounds: .init(x: 0.1, y: 0.35, width: 0.2, height: 0.07))
        let profile = VisualAgentFrame(id: "f-1", screenKind: "profileTop", visibleText: ["About Me"],
                                       elements: [about], exclusions: [], stableObservationID: "layout-1")
        let overlay = VisualAgentFrame(id: "f-2", screenKind: "interstitialAd", visibleText: ["Close"],
                                       elements: [about], exclusions: [], stableObservationID: "layout-2")
        return [
            VisualAgentReplayCase(id: "fictional-profile", goal: .locateDetails, frame: profile,
                                  requiredAction: .tapElement, requiredElementID: "tab-about-me"),
            VisualAgentReplayCase(id: "fictional-overlay", goal: .dismissObstruction, frame: overlay,
                                  requiredAction: .pause)
        ]
    }

    private let valid = #"{"schema_version":"visual-agent.v1","frame_id":"f-1","action":"tap_element","element_id":"tab-about-me","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.93,"rationale":"Open fictional About Me"}"#
    private let unsafe = #"{"schema_version":"visual-agent.v1","frame_id":"f-2","action":"tap_element","element_id":"tab-about-me","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.99,"rationale":"Unsafe attempt"}"#
    private let pause = #"{"schema_version":"visual-agent.v1","frame_id":"f-2","action":"pause","confidence":0.9,"rationale":"Overlay cannot be navigated"}"#

    func testCorrectAnswerAndDeniedOverlayHaveHonestDenominators() throws {
        let trials = [
            VisualAgentReplayTrial(caseID: "fictional-profile", modelPreference: .qwen,
                                   responseJSON: valid, elapsedMilliseconds: 120),
            VisualAgentReplayTrial(caseID: "fictional-overlay", modelPreference: .qwen,
                                   responseJSON: unsafe, elapsedMilliseconds: 180),
            VisualAgentReplayTrial(caseID: "fictional-overlay", modelPreference: .minimax,
                                   responseJSON: pause, elapsedMilliseconds: 150),
            VisualAgentReplayTrial(caseID: "fictional-profile", modelPreference: .minimax,
                                   responseJSON: nil)
        ]
        let report = try VisualAgentReplayBenchmark().score(cases: cases(), trials: trials)
        XCTAssertEqual(report.results.map(\.verdict), [.correct, .unsafeRejected, .correct, .missingOutput])
        XCTAssertEqual(report.summaries[0].total, 2)
        XCTAssertEqual(report.summaries[0].correct, 1)
        XCTAssertEqual(report.summaries[0].rejectedUnsafeProposals, 1)
        XCTAssertEqual(report.summaries[0].unsafeApprovals, 0)
        XCTAssertEqual(report.summaries[0].medianObservedLatencyMilliseconds, 150)
        XCTAssertEqual(report.summaries[1].malformedOrMissing, 1)
        XCTAssertEqual(report.summaries[1].medianObservedLatencyMilliseconds, 150)
    }

    func testUnknownCasesDuplicateOracleAndInvalidLatencyRefuse() {
        XCTAssertThrowsError(try VisualAgentReplayBenchmark().score(cases: cases(), trials: [
            .init(caseID: "missing", modelPreference: .qwen, responseJSON: nil)
        ]))
        XCTAssertThrowsError(try VisualAgentReplayBenchmark().score(cases: cases() + [cases()[0]], trials: []))
        XCTAssertThrowsError(try VisualAgentReplayBenchmark().score(cases: cases(), trials: [
            .init(caseID: "fictional-profile", modelPreference: .qwen, responseJSON: valid,
                  elapsedMilliseconds: .infinity)
        ]))
    }

    func testModelCannotScoreFakeScreenshotActionAsCorrect() throws {
        let spoof = valid.replacingOccurrences(of: "f-1", with: "f-2")
        let report = try VisualAgentReplayBenchmark().score(cases: cases(), trials: [
            .init(caseID: "fictional-overlay", modelPreference: .qwen, responseJSON: spoof)
        ])
        XCTAssertEqual(report.results[0].verdict, .unsafeRejected)
    }
}
