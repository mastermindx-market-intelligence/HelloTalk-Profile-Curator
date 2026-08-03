import XCTest
@testable import ProfileCuratorCore

final class SessionGuardTests: XCTestCase {
    func testTwoConsecutiveUnknownScreensPauseConservativeSession() {
        var state = NavigationSessionState()
        let policy = NavigationSessionPolicy.conservativeDefault

        state.recordScreen(.unknown, policy: policy)
        XCTAssertFalse(state.isPaused)
        state.recordScreen(.unknown, policy: policy)

        XCTAssertEqual(state.pauseReason, .unknownScreenLimit(2))
    }

    func testKnownScreenResetsUnknownStreak() {
        var state = NavigationSessionState()
        let policy = NavigationSessionPolicy.conservativeDefault

        state.recordScreen(.unknown, policy: policy)
        state.recordScreen(.profileTop, policy: policy)

        XCTAssertEqual(state.consecutiveUnknownScreens, 0)
        XCTAssertFalse(state.isPaused)
    }

    func testEmergencyStopLatchesImmediately() {
        var state = NavigationSessionState()
        state.engageEmergencyStop()

        XCTAssertEqual(state.pauseReason, .emergencyStop)
        XCTAssertTrue(state.isPaused)
    }

    func testProposalLimitPausesAtBoundary() {
        var state = NavigationSessionState()
        let policy = NavigationSessionPolicy(
            maximumProposals: 2,
            maximumProfileVisits: 10,
            maximumDurationSeconds: 100,
            maximumConsecutiveUnknownScreens: 2
        )

        state.recordProposal(policy: policy)
        state.recordProposal(policy: policy)

        XCTAssertEqual(state.pauseReason, .proposalLimit(2))
    }
}
