import ImageIO
import XCTest
@testable import ProfileCuratorCore

final class VisibleRecommendationTargetDetectorTests: XCTestCase {
    func testOptionalLiveGalleryExposesPartialThirdCardFallback() throws {
        guard let path = ProcessInfo.processInfo.environment["HELLOTALK_PARTIAL_GALLERY"] else {
            throw XCTSkip("No live partial-gallery fixture supplied")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let observations = try VisionFixtureAnalyzer().analyze(image).text

        let targets = VisibleRecommendationTargetDetector().targets(in: observations)
        let partial = try XCTUnwrap(targets.first(where: \.isPartialEdgeFallback))

        XCTAssertGreaterThan(partial.photoPoint.x, 0.95)
        XCTAssertNil(partial.displayedAge)
        XCTAssertTrue(partial.safePhotoRegion.contains(partial.photoPoint))
    }

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
        XCTAssertEqual(targets.filter { !$0.isPartialEdgeFallback }.count, 2)
        XCTAssertEqual(targets.filter(\.isPartialEdgeFallback).count, 1)
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

    func testOneAgeBadgeCannotBeReusedByTwoAdjacentNames() {
        let observations = [
            observation("Suggested for You", x: 0.06, y: 0.50, width: 0.42, height: 0.04),
            observation("Left", x: 0.08, y: 0.70, width: 0.10, height: 0.03),
            observation("Right", x: 0.23, y: 0.70, width: 0.10, height: 0.03),
            observation("921", x: 0.31, y: 0.70, width: 0.05, height: 0.03)
        ]

        let targets = VisibleRecommendationTargetDetector().targets(in: observations)

        XCTAssertEqual(targets.filter { $0.displayedAge == 21 }.count, 1)
    }

    func testRankerChoosesYoungestEligibleCardBeforeLeftmostOlderCard() throws {
        let older = VisibleRecommendationTarget(
            profileKey: "left-35",
            displayedAge: 35,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: 0.15, y: 0.62),
            safePhotoRegion: NormalizedRect(x: 0.08, y: 0.56, width: 0.14, height: 0.12),
            confidence: 0.95
        )
        let age21 = VisibleRecommendationTarget(
            profileKey: "right-21",
            displayedAge: 21,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: 0.62, y: 0.62),
            safePhotoRegion: NormalizedRect(x: 0.55, y: 0.56, width: 0.14, height: 0.12),
            confidence: 0.90
        )
        let age19 = VisibleRecommendationTarget(
            profileKey: "middle-19",
            displayedAge: 19,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: 0.42, y: 0.62),
            safePhotoRegion: NormalizedRect(x: 0.35, y: 0.56, width: 0.14, height: 0.12),
            confidence: 0.88
        )
        let conditional24 = VisibleRecommendationTarget(
            profileKey: "conditional-24",
            displayedAge: 24,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: 0.78, y: 0.62),
            safePhotoRegion: NormalizedRect(x: 0.71, y: 0.56, width: 0.14, height: 0.12),
            confidence: 0.97
        )

        let ranked = VisibleRecommendationTargetRanker().ranked([older, conditional24, age21, age19])

        XCTAssertEqual(try XCTUnwrap(ranked.first).profileKey, "middle-19")
        XCTAssertEqual(ranked[1].profileKey, "right-21")
        XCTAssertEqual(ranked[2].profileKey, "conditional-24")
        XCTAssertEqual(ranked.last?.profileKey, "left-35")
    }

    func testPartialThirdCardRanksAheadOfConfirmedOlderVisibleCards() throws {
        let age28 = target("visible-28", age: 28, x: 0.18)
        let age35 = target("visible-35", age: 35, x: 0.58)
        let partial = VisibleRecommendationTarget(
            profileKey: "partial-next-edge",
            displayedAge: nil,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: 0.975, y: 0.62),
            safePhotoRegion: NormalizedRect(x: 0.955, y: 0.58, width: 0.035, height: 0.08),
            confidence: 0.55,
            isPartialEdgeFallback: true
        )

        let ranked = VisibleRecommendationTargetRanker().ranked([age28, partial, age35])

        XCTAssertEqual(ranked.first?.profileKey, "partial-next-edge")
    }

    private func target(_ key: String, age: Int, x: Double) -> VisibleRecommendationTarget {
        VisibleRecommendationTarget(
            profileKey: key,
            displayedAge: age,
            ageEvidence: nil,
            photoPoint: NormalizedPoint(x: x, y: 0.62),
            safePhotoRegion: NormalizedRect(x: x - 0.06, y: 0.56, width: 0.12, height: 0.12),
            confidence: 0.9
        )
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
