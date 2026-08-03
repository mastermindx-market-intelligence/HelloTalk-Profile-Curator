import XCTest
@testable import ProfileCuratorCore

final class RotatingLocationBadgeParserTests: XCTestCase {
    private let bounds = NormalizedRect(x: 0.55, y: 0.18, width: 0.36, height: 0.04)

    func testTemporalResolutionIgnoresPeopleCountAndRetainsCityFrame() {
        let peopleFrame = [
            OCRObservation(text: "576 People Nearby", confidence: 0.96, bounds: bounds)
        ]
        let locationFrame = [
            OCRObservation(text: "Shenyang, China 6:58pm", confidence: 0.94, bounds: bounds)
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [peopleFrame, locationFrame])

        XCTAssertEqual(result.location?.city, "Shenyang")
        XCTAssertEqual(result.location?.province, "Liaoning")
        XCTAssertEqual(result.location?.tier, 5)
        XCTAssertEqual(result.nearbyCountsIgnored, [576])
        XCTAssertEqual(result.framesExamined, 2)
    }

    func testPeopleCountAloneDoesNotBecomeLocation() {
        let frame = [OCRObservation(text: "576 People Nearby", confidence: 0.96, bounds: bounds)]
        let result = RotatingLocationBadgeParser().resolve(frames: [frame])

        XCTAssertNil(result.location)
        XCTAssertEqual(result.nearbyCountsIgnored, [576])
    }

    func testObservedTinyBadgeTimeArtifactStillRetainsLocation() {
        let frame = [
            OCRObservation(text: "• Shenyang, China16 58pm", confidence: 0.91, bounds: bounds)
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [frame])

        XCTAssertEqual(result.location?.city, "Shenyang")
        XCTAssertEqual(result.source?.countryText, "China")
    }
}
