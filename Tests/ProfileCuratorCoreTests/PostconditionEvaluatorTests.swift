import XCTest
@testable import ProfileCuratorCore

final class PostconditionEvaluatorTests: XCTestCase {
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

    private func makeSnapshot(fingerprint: String, username: String? = nil) -> ObservationSnapshot {
        ObservationSnapshot(
            fingerprint: fingerprint,
            screen: ScreenClassification(
                kind: .profileTop,
                navigationState: .profileTop,
                confidence: 0.9,
                evidence: []
            ),
            combinedOCRText: "About Me",
            username: username
        )
    }
}
