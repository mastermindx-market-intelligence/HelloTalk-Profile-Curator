import CoreGraphics
import ImageIO
import XCTest
@testable import ProfileCuratorCore

final class MomentNavigationTests: XCTestCase {
    func testObservedMomentGridProducesNineImageOnlyTargets() throws {
        let marks = [CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )]
        let image = try makeMomentGridImage(rows: 3, finalRowColumns: 3)

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: marks)

        XCTAssertEqual(targets.count, 9)
        XCTAssertEqual(targets.map(\.index), Array(0..<9))
        XCTAssertTrue(targets.allSatisfy { $0.safePhotoRegion.contains($0.point) })
        XCTAssertTrue(targets.allSatisfy { $0.point.y < 0.706 })
        XCTAssertEqual(targets.first?.plannedAction.kind, .openMomentThumbnail)
    }

    func testMomentGridRequiresDedicatedCalibrationRegion() {
        let image = try! makeMomentGridImage(rows: 2, finalRowColumns: 2)
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(in: image, from: []).isEmpty)
        let unrelated = CalibrationMark(
            context: .profile,
            kind: .safeRecommendationCard,
            bounds: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        )
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(in: image, from: [unrelated]).isEmpty)
        let unconfirmed = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66)
        )
        XCTAssertTrue(MomentThumbnailTargetDetector().targets(in: image, from: [unconfirmed]).isEmpty)
    }

    func testDynamicGridFindsTwoFullRowsAndOnlyTwoCellsInFinalRow() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(rows: 3, finalRowColumns: 2)

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: [mark])

        XCTAssertEqual(targets.count, 8)
        XCTAssertEqual(targets.map(\.index), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertTrue(targets.allSatisfy { $0.point.y > 0.35 && $0.point.y < 0.75 })
    }

    func testPrivateLiveCaptureFindsEightCellsWhenFixtureIsAvailable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot
            .appendingPathComponent("fixtures/private/moments_feed/dynamic_grid_eight_cells.png")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Private supervised Moment fixture is not present")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fixture as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: [mark])

        XCTAssertEqual(targets.count, 8)
        XCTAssertEqual(targets.map(\.index), [0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testLongDownwardDismissStaysInsideDedicatedSafeRegion() throws {
        let mark = CalibrationMark(
            context: .momentViewer,
            kind: .safeMomentDismissGesture,
            bounds: NormalizedRect(x: 0.12, y: 0.43, width: 0.76, height: 0.44),
            confirmed: true
        )
        let gesture = try XCTUnwrap(MomentViewerDismissPlanner().proposal(from: [mark]))

        XCTAssertEqual(gesture.kind, .closeViewer)
        XCTAssertTrue(gesture.requiredSafeRegion.contains(gesture.start))
        XCTAssertTrue(gesture.requiredSafeRegion.contains(gesture.end))
        XCTAssertGreaterThan(gesture.end.y - gesture.start.y, 0.39)
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
            bounds: NormalizedRect(x: 0.12, y: 0.43, width: 0.76, height: 0.44),
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

    private func makeMomentGridImage(rows: Int, finalRowColumns: Int) throws -> CGImage {
        let width = 420
        let height = 932
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 24, y: height - 170 - 120, width: 326, height: 120))

        let cell = 106
        let gutter = 5
        let left = 24
        let top = 360
        for row in 0..<rows {
            let columnCount = row == rows - 1 ? finalRowColumns : 3
            for column in 0..<columnCount {
                let red = CGFloat(0.2 + Double((row + column) % 3) * 0.2)
                context.setFillColor(CGColor(red: red, green: 0.25, blue: 0.55, alpha: 1))
                context.fill(CGRect(
                    x: left + column * (cell + gutter),
                    y: height - top - cell - row * (cell + gutter),
                    width: cell,
                    height: cell
                ))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
}

private actor RecordingMomentDriver: InputDriving {
    private(set) var commands: [InputCommand] = []
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws {
        commands.append(command)
    }
}
