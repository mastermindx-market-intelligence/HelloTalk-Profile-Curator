import CoreGraphics
import XCTest
@testable import ProfileCuratorCore

final class MomentNavigationTests: XCTestCase {
    func testObservedMomentGridProducesNineImageOnlyTargets() throws {
        let marks = [CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.357, width: 0.78, height: 0.349),
            confirmed: true
        )]

        let targets = MomentThumbnailTargetDetector().targets(from: marks)

        XCTAssertEqual(targets.count, 9)
        XCTAssertEqual(targets.map(\.index), Array(0..<9))
        XCTAssertTrue(targets.allSatisfy { $0.safePhotoRegion.contains($0.point) })
        XCTAssertTrue(targets.allSatisfy { $0.point.y < 0.706 })
        XCTAssertEqual(targets.first?.plannedAction.kind, .openMomentThumbnail)
    }

    func testMomentGridRequiresDedicatedCalibrationRegion() {
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(from: []).isEmpty)
        let unrelated = CalibrationMark(
            context: .profile,
            kind: .safeRecommendationCard,
            bounds: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        )
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(from: [unrelated]).isEmpty)
        let unconfirmed = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.357, width: 0.78, height: 0.349)
        )
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(from: [unconfirmed]).isEmpty)
    }

    func testLongDownwardDismissStaysInsideDedicatedSafeRegion() throws {
        let mark = CalibrationMark(
            context: .momentViewer,
            kind: .safeMomentDismissGesture,
            bounds: NormalizedRect(x: 0.12, y: 0.25, width: 0.76, height: 0.58),
            confirmed: true
        )
        let gesture = try XCTUnwrap(MomentViewerDismissPlanner().proposal(from: [mark]))

        XCTAssertEqual(gesture.kind, .closeViewer)
        XCTAssertTrue(gesture.requiredSafeRegion.contains(gesture.start))
        XCTAssertTrue(gesture.requiredSafeRegion.contains(gesture.end))
        XCTAssertGreaterThan(gesture.end.y - gesture.start.y, 0.45)
        let decision = GestureSafetyValidator().validate(
            gesture,
            exclusionZones: [],
            calibrationConfirmed: true,
            emergencyStopActive: false,
            liveInputEnabled: false
        )
        XCTAssertEqual(decision.rejection, .dryRunRequired)
    }

    func testGestureExecutorEmitsDragOnlyAfterEveryGatePasses() async throws {
        let driver = RecordingMomentDriver()
        let executor = SafeInputExecutor(driver: driver)
        let mark = CalibrationMark(
            context: .momentViewer,
            kind: .safeMomentDismissGesture,
            bounds: NormalizedRect(x: 0.12, y: 0.25, width: 0.76, height: 0.58),
            confirmed: true
        )
        let gesture = try XCTUnwrap(MomentViewerDismissPlanner().proposal(from: [mark]))

        let blocked = try await executor.executeGesture(
            gesture: gesture,
            windowFrame: CGRect(x: 0, y: 0, width: 420, height: 932),
            exclusions: [],
            calibrationConfirmed: true,
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: false
        )
        XCTAssertEqual(blocked.rejection, .dryRunRequired)
        let blockedCommands = await driver.commands
        XCTAssertEqual(blockedCommands.count, 0)

        let allowed = try await executor.executeGesture(
            gesture: gesture,
            windowFrame: CGRect(x: 0, y: 0, width: 420, height: 932),
            exclusions: [],
            calibrationConfirmed: true,
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: true
        )
        XCTAssertTrue(allowed.isAllowed)
        let allowedCommands = await driver.commands
        XCTAssertEqual(allowedCommands, [.drag(start: gesture.start, end: gesture.end)])
    }
}

private actor RecordingMomentDriver: InputDriving {
    private(set) var commands: [InputCommand] = []
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws {
        commands.append(command)
    }
}
