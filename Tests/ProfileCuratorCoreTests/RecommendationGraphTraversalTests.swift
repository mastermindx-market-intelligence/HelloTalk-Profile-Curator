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

    func testFemaleMissingOrOutOfRangeAgeIsRoutingOnly() {
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
                displayedAge: 24,
                genderHint: .female
            )),
            .openAsRoutingOnly
        )
    }

    func testRoutingNodeIsDeduplicatedAndConsumesDepth() {
        let candidate = VisibleRecommendationCandidate(profileKey: "Mia", displayedAge: nil, genderHint: .female)
        var ledger = RecommendationTraversalLedger(maximumRoutingDepth: 2)
        let decision = ledger.decision(for: candidate)
        ledger.recordOpened(candidate, decision: decision)

        XCTAssertEqual(ledger.routingDepth, 1)
        XCTAssertEqual(ledger.decision(for: candidate), .skipDuplicate)
    }

    func testNonFemaleHintAndDepthLimitFailClosed() {
        XCTAssertEqual(
            RecommendationTraversalLedger().decision(for: VisibleRecommendationCandidate(
                profileKey: "unknown",
                displayedAge: 20,
                genderHint: .unknown
            )),
            .rejectNonFemaleHint
        )

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
}
