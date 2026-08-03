import XCTest
@testable import ProfileCuratorCore

final class VisibleRecommendationTargetDetectorTests: XCTestCase {
    func testDerivesPhotoPointAboveGalleryAgeBadge() throws {
        let observations = [
            observation("Suggested for You", x: 0.06, y: 0.50, width: 0.42, height: 0.04),
            observation("922", x: 0.29, y: 0.66, width: 0.06, height: 0.03),
            observation("25", x: 0.10, y: 0.20, width: 0.04, height: 0.03)
        ]

        let target = try XCTUnwrap(VisibleRecommendationTargetDetector().targets(in: observations).first)

        XCTAssertEqual(target.displayedAge, 22)
        XCTAssertLessThan(target.photoPoint.x, 0.29)
        XCTAssertLessThan(target.photoPoint.y, 0.66)
        XCTAssertTrue(target.safePhotoRegion.contains(target.photoPoint))
        XCTAssertEqual(target.plannedAction.kind, .openRecommendationCard)
    }

    func testAssociatesNamedCardsAndKeepsMissingAgeCardInspectable() throws {
        let observations = [
            observation("Suggested for You", x: 0.06, y: 0.50, width: 0.42, height: 0.04),
            observation("kk", x: 0.12, y: 0.70, width: 0.08, height: 0.03),
            observation("922", x: 0.21, y: 0.70, width: 0.05, height: 0.03),
            observation("looooyii", x: 0.52, y: 0.70, width: 0.15, height: 0.03),
            observation("Say Hi", x: 0.10, y: 0.80, width: 0.12, height: 0.03),
            observation("Follow", x: 0.52, y: 0.80, width: 0.12, height: 0.03)
        ]

        let targets = VisibleRecommendationTargetDetector().targets(in: observations)
        let first = try XCTUnwrap(targets.first { $0.profileKey == "kk" })
        let second = try XCTUnwrap(targets.first { $0.profileKey == "looooyii" })

        XCTAssertEqual(first.displayedAge, 22)
        XCTAssertNil(second.displayedAge)
        XCTAssertEqual(targets.count, 2)
    }

    func testRequiresSuggestedAnchorAndRejectsAgesBelowSocialBand() {
        let noAnchor = [observation("919", x: 0.2, y: 0.6, width: 0.05, height: 0.03)]
        XCTAssertTrue(VisibleRecommendationTargetDetector().targets(in: noAnchor).isEmpty)

        let tooLow = [
            observation("Suggested for You", x: 0.05, y: 0.70, width: 0.4, height: 0.04),
            observation("919", x: 0.2, y: 0.96, width: 0.05, height: 0.03)
        ]
        XCTAssertTrue(VisibleRecommendationTargetDetector().targets(in: tooLow).isEmpty)
    }

    func testDynamicSocialControlsBecomeExpandedExclusions() throws {
        let observations = [
            observation("Say Hi", x: 0.18, y: 0.78, width: 0.08, height: 0.03),
            observation("Free to Chat", x: 0.58, y: 0.72, width: 0.12, height: 0.03),
            observation("ordinary text", x: 0.1, y: 0.2, width: 0.2, height: 0.03)
        ]

        let exclusions = SocialControlExclusionDetector().exclusions(in: observations)

        XCTAssertEqual(exclusions.count, 2)
        let sayHi = try XCTUnwrap(exclusions.first { $0.label.contains("Say Hi") })
        XCTAssertTrue(sayHi.bounds.contains(NormalizedPoint(x: 0.14, y: 0.79)))
    }

    private func observation(
        _ text: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> OCRObservation {
        OCRObservation(
            text: text,
            confidence: 0.95,
            bounds: NormalizedRect(x: x, y: y, width: width, height: height)
        )
    }
}
