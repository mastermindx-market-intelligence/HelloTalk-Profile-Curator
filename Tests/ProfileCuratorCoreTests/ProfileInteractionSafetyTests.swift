import XCTest
@testable import ProfileCuratorCore

final class ProfileInteractionSafetyTests: XCTestCase {
    private let safety = ProfileInteractionSafety()

    func testLearningStatsCardBecomesFullWidthExclusion() throws {
        let observations = [
            observation("1288d Joined", x: 0.06, y: 0.31, width: 0.22),
            observation("935 Points", x: 0.53, y: 0.31, width: 0.20)
        ]

        let exclusion = try XCTUnwrap(safety.learningStatsExclusions(in: observations).first)

        XCTAssertTrue(exclusion.bounds.contains(NormalizedPoint(x: 0.50, y: 0.38)))
        XCTAssertEqual(exclusion.label, "Learning statistics card")
    }

    func testAboutMeActionUsesTightLiveOCRBoundsInsteadOfCalibrationCenter() throws {
        let about = observation("About Me", x: 0.08, y: 0.46, width: 0.19)
        let action = try XCTUnwrap(safety.tabAction(named: "About Me", in: [about]))

        XCTAssertEqual(action.kind, .selectAboutMe)
        XCTAssertEqual(action.point, about.bounds.center)
        XCTAssertLessThan(try XCTUnwrap(action.requiredSafeRegion).height, 0.08)
    }

    func testMomentsTabAcceptsDynamicPostCountButRejectsOtherMomentsText() throws {
        let countedTab = observation("Moments 6", x: 0.37, y: 0.46, width: 0.19)
        let unrelated = observation("My favorite moments today", x: 0.08, y: 0.72, width: 0.42)

        let action = try XCTUnwrap(safety.tabAction(named: "Moments", in: [unrelated, countedTab]))

        XCTAssertEqual(action.kind, .selectMoments)
        XCTAssertEqual(action.point, countedTab.bounds.center)
        XCTAssertNil(safety.tabAction(named: "Moments", in: [unrelated]))
    }

    func testPopupDetectionRequiresMultipleSpecificAnchors() {
        XCTAssertTrue(safety.isLearningStatsPopup([
            observation("Total learning points: 935", x: 0.15, y: 0.25, width: 0.5),
            observation("Translations Used", x: 0.18, y: 0.34, width: 0.3)
        ]))
        XCTAssertFalse(safety.isLearningStatsPopup([
            observation("935 Points", x: 0.5, y: 0.3, width: 0.2)
        ]))
    }

    func testScrollPointMovesOutsideLearningStatsCard() throws {
        let exclusion = ExclusionZone(
            label: "Learning statistics card",
            bounds: NormalizedRect(x: 0.02, y: 0.45, width: 0.96, height: 0.18)
        )
        let action = try XCTUnwrap(safety.scrollAction(lines: -7, avoiding: [exclusion]))

        XCTAssertFalse(exclusion.bounds.contains(action.point))
    }

    func testReturnToTopUsesMultiplePassesAndScalesWithProfileDepth() {
        XCTAssertEqual(safety.returnToTopScrollPasses(afterDownwardScrollAttempts: 0), 4)
        XCTAssertEqual(safety.returnToTopScrollPasses(afterDownwardScrollAttempts: 2), 4)
        XCTAssertEqual(safety.returnToTopScrollPasses(afterDownwardScrollAttempts: 8), 7)
        XCTAssertEqual(safety.returnToTopScrollPasses(afterDownwardScrollAttempts: 99), 8)
    }

    private func observation(
        _ text: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double = 0.03
    ) -> OCRObservation {
        OCRObservation(
            text: text,
            confidence: 0.95,
            bounds: NormalizedRect(x: x, y: y, width: width, height: height)
        )
    }
}
