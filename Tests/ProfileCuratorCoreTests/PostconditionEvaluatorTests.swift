import XCTest
@testable import ProfileCuratorCore

final class PostconditionEvaluatorTests: XCTestCase {
    func testMomentMediaLoadingPolicyAllowsDelayedVideoAndSlideshowFrames() {
        XCTAssertGreaterThanOrEqual(MomentMediaLoadingPolicy.totalWaitMilliseconds, 15_000)
        XCTAssertGreaterThanOrEqual(MomentMediaLoadingPolicy.verificationDelaysMilliseconds.count, 8)
    }

    func testCustomSearchAndMomentsFirstPostconditionsAreExact() {
        let evaluator = NavigationPostconditionEvaluator()
        let custom = makeSnapshot(
            fingerprint: "custom",
            username: nil,
            text: "Custom Search",
            kind: .customSearch
        )
        let moments = makeSnapshot(
            fingerprint: "moments",
            username: "@a",
            text: "About Me Moments Achievements",
            kind: .momentsFeed
        )

        XCTAssertEqual(evaluator.evaluate(.customSearchDetected, against: custom).status, .passed)
        XCTAssertEqual(evaluator.evaluate(.momentsFeedDetected, against: moments).status, .passed)
        XCTAssertEqual(evaluator.evaluate(.customSearchDetected, against: moments).status, .failed)
    }

    func testMomentDetailsImmediatelyStopsViewerPolling() {
        let evaluator = NavigationPostconditionEvaluator()
        let details = makeSnapshot(
            fingerprint: "details",
            text: "Details Comments Type a message",
            kind: .momentDetails
        )
        let loading = makeSnapshot(fingerprint: "loading", text: "", kind: .unknown)

        XCTAssertTrue(evaluator.shouldStopPolling(.viewerDetected, against: details))
        XCTAssertFalse(evaluator.shouldStopPolling(.viewerDetected, against: loading))
    }

    func testAnchorAbsentRequiresPopupTextToDisappear() {
        let evaluator = NavigationPostconditionEvaluator()
        let visible = makeSnapshot(fingerprint: "same", username: "@a", text: "Total learning points")
        let dismissed = makeSnapshot(fingerprint: "same", username: "@a", text: "About Me")

        XCTAssertEqual(
            evaluator.evaluate(.ocrAnchorAbsent("Total learning points"), against: visible).status,
            .failed
        )
        XCTAssertEqual(
            evaluator.evaluate(.ocrAnchorAbsent("Total learning points"), against: dismissed).status,
            .passed
        )
    }
    func testContentChangePostconditionPassesOnlyForDifferentFingerprint() {
        let snapshot = makeSnapshot(fingerprint: "new")
        let evaluator = NavigationPostconditionEvaluator()

        XCTAssertEqual(
            evaluator.evaluate(.contentHashChanged(previous: "old"), against: snapshot).status,
            .passed
        )
        XCTAssertEqual(
            evaluator.evaluate(.contentHashChanged(previous: "new"), against: snapshot).status,
            .failed
        )
    }

    func testProfileIdentityChangeIsInconclusiveWithoutBothUsernames() {
        let result = NavigationPostconditionEvaluator().evaluate(
            .profileIdentityChanged(previousUsername: nil),
            against: makeSnapshot(fingerprint: "x", username: "@new")
        )

        XCTAssertEqual(result.status, .inconclusive)
    }

    func testProfileIdentityChangePassesCaseInsensitivelyForNewUsername() {
        let result = NavigationPostconditionEvaluator().evaluate(
            .profileIdentityChanged(previousUsername: "@old"),
            against: makeSnapshot(fingerprint: "x", username: "@new")
        )

        XCTAssertEqual(result.status, .passed)
    }

    private func makeSnapshot(
        fingerprint: String,
        username: String? = nil,
        text: String = "About Me",
        kind: DetectedScreenKind = .profileTop
    ) -> ObservationSnapshot {
        ObservationSnapshot(
            fingerprint: fingerprint,
            screen: ScreenClassification(
                kind: kind,
                navigationState: .profileTop,
                confidence: 0.9,
                evidence: []
            ),
            combinedOCRText: text,
            username: username
        )
    }
}
