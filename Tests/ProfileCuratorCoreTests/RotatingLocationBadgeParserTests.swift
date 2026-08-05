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

    func testBadgeLocationStillResolvesWhenVisionSplitsOffOrDropsTime() {
        let locationOnly = [
            OCRObservation(text: "Guangzhou, China", confidence: 0.93, bounds: bounds),
            OCRObservation(
                text: "6:58pm",
                confidence: 0.88,
                bounds: NormalizedRect(x: 0.84, y: 0.18, width: 0.12, height: 0.04)
            )
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [locationOnly])

        XCTAssertEqual(result.location?.city, "Guangzhou")
        XCTAssertEqual(result.location?.tier, 2)
        XCTAssertEqual(result.location?.score, 85)
    }

    func testBadgeLocationResolvesWhenMirroringPlacesItFartherLeft() {
        let shiftedBadge = [
            OCRObservation(
                text: "Guangzhou, China",
                confidence: 0.93,
                bounds: NormalizedRect(x: 0.24, y: 0.18, width: 0.36, height: 0.04)
            )
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [shiftedBadge])

        XCTAssertEqual(result.location?.city, "Guangzhou")
        XCTAssertEqual(result.location?.score, 85)
    }

    func testTinyLowConfidenceBadgeStillResolvesExactCityAndCountry() {
        let frame = [
            OCRObservation(text: "Guangzhou, China", confidence: 0.50, bounds: bounds)
        ]

        XCTAssertEqual(
            RotatingLocationBadgeParser().resolve(frames: [frame]).location?.city,
            "Guangzhou"
        )
    }

    func testCityCountryTextOutsideBadgeGeometryIsNotAccepted() {
        let profileBody = [
            OCRObservation(
                text: "Guangzhou, China",
                confidence: 0.99,
                bounds: NormalizedRect(x: 0.08, y: 0.70, width: 0.34, height: 0.04)
            )
        ]

        XCTAssertNil(RotatingLocationBadgeParser().resolve(frames: [profileBody]).location)
    }

    func testMapLabelsWithoutRotatingBadgeNeverBecomeProfileLocation() {
        let mapLabels = [
            OCRObservation(text: "Nanjing", confidence: 0.99, bounds: NormalizedRect(x: 0.13, y: 0.15, width: 0.18, height: 0.03)),
            OCRObservation(text: "Shanghai", confidence: 0.99, bounds: NormalizedRect(x: 0.50, y: 0.16, width: 0.21, height: 0.03)),
            OCRObservation(text: "Suzhou", confidence: 0.99, bounds: NormalizedRect(x: 0.31, y: 0.20, width: 0.16, height: 0.03)),
            OCRObservation(text: "Hangzhou", confidence: 0.99, bounds: NormalizedRect(x: 0.31, y: 0.23, width: 0.22, height: 0.03))
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [mapLabels, mapLabels])

        XCTAssertNil(result.location)
        XCTAssertNil(result.source)
    }

    func testSeoulSouthKoreaTimedBadgeResolvesWithoutUsingMapLabels() {
        let frame = [
            OCRObservation(text: "Seoul, South Korea 10:28am", confidence: 0.94, bounds: bounds),
            OCRObservation(text: "Incheon", confidence: 0.99, bounds: NormalizedRect(x: 0.10, y: 0.20, width: 0.18, height: 0.03))
        ]

        let result = RotatingLocationBadgeParser().resolve(frames: [frame])

        XCTAssertEqual(result.location?.city, "Seoul")
        XCTAssertEqual(result.location?.country, "South Korea")
        XCTAssertEqual(result.location?.score, 30)
        XCTAssertEqual(result.source?.rawText, "Seoul, South Korea 10:28am")
    }
}
