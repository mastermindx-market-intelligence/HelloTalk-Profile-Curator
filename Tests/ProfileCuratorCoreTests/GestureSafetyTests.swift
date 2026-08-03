import XCTest
@testable import ProfileCuratorCore

final class GestureSafetyTests: XCTestCase {
    private let safeRegion = NormalizedRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2)

    func testGalleryPlannerRequiresDedicatedCalibrationMark() {
        XCTAssertNil(GalleryGesturePlanner().proposal(from: []))
    }

    func testGalleryPlannerBuildsRightToLeftPathInsideRegion() throws {
        let mark = CalibrationMark(kind: .safeCarouselGesture, bounds: safeRegion, confirmed: true)
        let gesture = try XCTUnwrap(GalleryGesturePlanner().proposal(from: [mark]))

        XCTAssertGreaterThan(gesture.start.x, gesture.end.x)
        XCTAssertTrue(safeRegion.contains(gesture.start))
        XCTAssertTrue(safeRegion.contains(gesture.end))
    }

    func testUnconfirmedCalibrationBlocksBeforeDryRunGate() throws {
        let mark = CalibrationMark(kind: .safeCarouselGesture, bounds: safeRegion)
        let gesture = try XCTUnwrap(GalleryGesturePlanner().proposal(from: [mark]))

        let decision = GestureSafetyValidator().validate(
            gesture,
            exclusionZones: [],
            calibrationConfirmed: false,
            emergencyStopActive: false,
            liveInputEnabled: false
        )

        XCTAssertEqual(decision.rejection, .calibrationIncomplete)
    }

    func testSwipeSegmentCannotCrossExclusionZone() throws {
        let mark = CalibrationMark(kind: .safeCarouselGesture, bounds: safeRegion, confirmed: true)
        let gesture = try XCTUnwrap(GalleryGesturePlanner().proposal(from: [mark]))
        let exclusion = ExclusionZone(
            label: "Say Hi",
            bounds: NormalizedRect(x: 0.45, y: 0.55, width: 0.1, height: 0.1)
        )

        let decision = GestureSafetyValidator().validate(
            gesture,
            exclusionZones: [exclusion],
            calibrationConfirmed: true,
            emergencyStopActive: false,
            liveInputEnabled: true
        )

        XCTAssertEqual(decision.rejection, .intersectsExclusionZone("Say Hi"))
    }

    func testConfirmedSafeGestureStillStopsAtDryRunGate() throws {
        let mark = CalibrationMark(kind: .safeCarouselGesture, bounds: safeRegion, confirmed: true)
        let gesture = try XCTUnwrap(GalleryGesturePlanner().proposal(from: [mark]))

        let decision = GestureSafetyValidator().validate(
            gesture,
            exclusionZones: [],
            calibrationConfirmed: true,
            emergencyStopActive: false,
            liveInputEnabled: false
        )

        XCTAssertEqual(decision.rejection, .dryRunRequired)
    }
}
