import XCTest
@testable import ProfileCuratorCore

final class AutonomousRecoveryPolicyTests: XCTestCase {
    private let policy = AutonomousRecoveryPolicy()

    func testUnknownFramesRecaptureThenUseOneBoundedBackRecovery() {
        XCTAssertEqual(policy.step(for: .unknown, attempt: 1), .recapture)
        XCTAssertEqual(policy.step(for: .unknown, attempt: 2), .recapture)
        XCTAssertEqual(policy.step(for: .unknown, attempt: 3), .backToPreviousSurface)
        XCTAssertEqual(policy.step(for: .unknown, attempt: 4), .recapture)
        XCTAssertEqual(policy.step(for: .unknown, attempt: 5), .stop)
    }

    func testProfileFailureAbandonsProfileWithoutBypassingSafety() {
        XCTAssertEqual(policy.step(for: .profileTop, attempt: 1), .abandonProfile)
        XCTAssertEqual(policy.step(for: .profilePersonalInfo, attempt: 3), .abandonProfile)
        XCTAssertEqual(policy.step(for: .profileTop, attempt: 4), .stop)
    }

    func testViewerAndMomentsRecoveryEscalateToVerifiedBackNavigation() {
        XCTAssertEqual(policy.step(for: .momentViewer, attempt: 1), .dismissMomentViewer)
        XCTAssertEqual(policy.step(for: .momentViewer, attempt: 3), .backToPreviousSurface)
        XCTAssertEqual(policy.step(for: .momentsFeed, attempt: 1), .finishMoments)
        XCTAssertEqual(policy.step(for: .momentsFeed, attempt: 3), .backToPreviousSurface)
    }

    func testPolicyAlwaysStopsOutsideBoundedAttemptBudget() {
        for screen in DetectedScreenKind.allCases {
            XCTAssertEqual(
                policy.step(
                    for: screen,
                    attempt: AutonomousRecoveryPolicy.maximumAttemptsPerIncident + 1
                ),
                .stop,
                screen.rawValue
            )
        }
    }
}
