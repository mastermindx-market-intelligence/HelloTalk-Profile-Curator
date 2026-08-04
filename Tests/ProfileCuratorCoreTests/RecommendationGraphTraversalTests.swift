import XCTest
@testable import ProfileCuratorCore

final class RecommendationGraphTraversalTests: XCTestCase {
    func testFemaleTargetAgeOpensForFullProfileVerification() {
        let candidate = VisibleRecommendationCandidate(profileKey: "candidate", displayedAge: 19, genderHint: .female)
        XCTAssertEqual(
            RecommendationTraversalLedger().decision(for: candidate),
            .openForTargetVerification
        )
    }

    func testFemaleMissingOrNonExceptionAgeIsRoutingOnly() {
        let ledger = RecommendationTraversalLedger()
        XCTAssertEqual(
            ledger.decision(for: VisibleRecommendationCandidate(
                profileKey: "mia",
                displayedAge: nil,
                genderHint: .female
            )),
            .openAsRoutingOnly
        )
        XCTAssertEqual(
            ledger.decision(for: VisibleRecommendationCandidate(
                profileKey: "janice",
                displayedAge: 22,
                genderHint: .female
            )),
            .openAsRoutingOnly
        )
    }

    func testPrimaryMBTIAgeExceptionOpensForFullProfileVerification() {
        for age in 23...24 {
            XCTAssertEqual(
                RecommendationTraversalLedger().decision(for: VisibleRecommendationCandidate(
                    profileKey: "candidate-\(age)",
                    displayedAge: age,
                    genderHint: .female
                )),
                .openForTargetVerification
            )
        }
    }

    func testRoutingNodeIsDeduplicatedAndConsumesDepth() {
        let candidate = VisibleRecommendationCandidate(profileKey: "Mia", displayedAge: nil, genderHint: .female)
        var ledger = RecommendationTraversalLedger(maximumRoutingDepth: 2)
        let decision = ledger.decision(for: candidate)
        ledger.recordOpened(candidate, decision: decision)

        XCTAssertEqual(ledger.routingDepth, 1)
        XCTAssertEqual(ledger.decision(for: candidate), .skipDuplicate)
    }

    func testUnknownGenderCanOnlyOpenForEligibilityInspection() {
        XCTAssertEqual(
            RecommendationTraversalLedger().decision(for: VisibleRecommendationCandidate(
                profileKey: "unknown",
                displayedAge: 20,
                genderHint: .unknown
            )),
            .openForEligibilityInspection
        )

        let male = VisibleRecommendationCandidate(profileKey: "male", displayedAge: 20, genderHint: .male)
        XCTAssertEqual(RecommendationTraversalLedger().decision(for: male), .rejectNonFemaleHint)
    }

    func testDepthLimitFailsClosed() {
        let ledger = RecommendationTraversalLedger(routingDepth: 2, maximumRoutingDepth: 2)
        XCTAssertEqual(
            ledger.decision(for: VisibleRecommendationCandidate(
                profileKey: "next",
                displayedAge: 27,
                genderHint: .female
            )),
            .routingDepthLimitReached(2)
        )
    }

    func testVerifiedUsernameIsAlsoDeduplicated() {
        var ledger = RecommendationTraversalLedger()
        ledger.recordVerifiedProfileKey("@New_Profile")
        XCTAssertTrue(ledger.visitedProfileKeys.contains("@new_profile"))
    }
}
