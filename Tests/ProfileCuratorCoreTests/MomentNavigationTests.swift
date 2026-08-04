import CoreGraphics
import ImageIO
import XCTest
@testable import ProfileCuratorCore

final class MomentNavigationTests: XCTestCase {
    func testMomentVisitKeysStayStableWhenWholeScreenFingerprintChanges() {
        let builder = MomentVisitKeyBuilder()
        let first = builder.keys(
            targetIndex: 0,
            feedPage: 0,
            thumbnailHash: "same-thumbnail"
        )
        let afterViewerDismissal = builder.keys(
            targetIndex: 0,
            feedPage: 0,
            thumbnailHash: "same-thumbnail"
        )

        XCTAssertEqual(first, afterViewerDismissal)
        XCTAssertFalse(first.isDisjoint(with: afterViewerDismissal))
    }

    func testMomentVisitKeysRecognizeMovedThumbnailByImageHash() {
        let builder = MomentVisitKeyBuilder()
        let first = builder.keys(targetIndex: 0, feedPage: 0, thumbnailHash: "same-thumbnail")
        let moved = builder.keys(targetIndex: 4, feedPage: 1, thumbnailHash: "same-thumbnail")

        XCTAssertFalse(first.isDisjoint(with: moved))
    }

    func testMomentVisitSlotCanBeReusedOnlyAfterDeliberateFeedPageChange() {
        let builder = MomentVisitKeyBuilder()
        let visited = builder.keys(targetIndex: 0, feedPage: 0, thumbnailHash: nil)
        let samePage = builder.keys(targetIndex: 0, feedPage: 0, thumbnailHash: nil)
        let nextPage = builder.keys(targetIndex: 0, feedPage: 1, thumbnailHash: nil)

        XCTAssertFalse(visited.isDisjoint(with: samePage))
        XCTAssertTrue(visited.isDisjoint(with: nextPage))
    }

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

    func testDynamicGridGeometryIsScaleIndependent() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(rows: 3, finalRowColumns: 2, scale: 2)

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: [mark])

        XCTAssertEqual(targets.map(\.index), [0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testDarkThemeGuttersStillRevealMomentGrid() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(rows: 2, finalRowColumns: 3, darkGutters: true)

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: [mark])

        XCTAssertEqual(targets.count, 6)
        XCTAssertTrue(targets.allSatisfy { $0.point.y < 0.70 })
    }

    func testVerticalTimelineUsesFaceInsideDatedPostInsteadOfAdOrSocialControls() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(rows: 2, finalRowColumns: 3)
        let face = DetectedFace(
            bounds: NormalizedRect(x: 0.18, y: 0.69, width: 0.18, height: 0.16),
            captureQuality: 0.8,
            hasLandmarks: true
        )
        let observations = [
            OCRObservation(text: "Install", confidence: 0.99, bounds: NormalizedRect(x: 0.80, y: 0.30, width: 0.12, height: 0.03)),
            OCRObservation(text: "28/11/2025", confidence: 0.97, bounds: NormalizedRect(x: 0.76, y: 0.57, width: 0.18, height: 0.025))
        ]

        let targets = MomentThumbnailTargetDetector().targets(
            in: image,
            from: [mark],
            observations: observations,
            faces: [face]
        )

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].index, 100)
        XCTAssertEqual(targets[0].point, face.bounds.center)
        XCTAssertTrue(targets[0].safePhotoRegion.contains(targets[0].point))
    }

    func testLaterAlignedRowsBeatSingleThreeColumnDistractor() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(
            rows: 2,
            finalRowColumns: 3,
            includeThreeColumnDistractor: true
        )

        let targets = MomentThumbnailTargetDetector().targets(in: image, from: [mark])

        XCTAssertEqual(targets.count, 6)
        XCTAssertTrue(targets.allSatisfy { $0.point.y > 0.38 })
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

    func testMomentDismissRetriesUseThreeDistinctCalibratedPaths() throws {
        let mark = CalibrationMark(
            context: .momentViewer,
            kind: .safeMomentDismissGesture,
            bounds: NormalizedRect(x: 0.12, y: 0.27, width: 0.76, height: 0.60),
            confirmed: true
        )

        let gestures = MomentViewerDismissPlanner().proposals(from: [mark])

        XCTAssertEqual(gestures.count, 3)
        XCTAssertEqual(Set(gestures.map(\.start.x)).count, 3)
        XCTAssertTrue(gestures.allSatisfy {
            $0.requiredSafeRegion == mark.bounds
                && mark.bounds.contains($0.start)
                && mark.bounds.contains($0.end)
                && $0.end.y - $0.start.y > 0.54
        })
    }

    func testInterstitialAdDismissUsesDedicatedTopRightCloseRegion() throws {
        let action = try XCTUnwrap(InterstitialAdDismissPlanner().closeAction(observations: [
            OCRObservation(
                text: "Chat Share with Al Strat chatting...",
                confidence: 0.95,
                bounds: NormalizedRect(x: 0.2, y: 0.3, width: 0.5, height: 0.05)
            )
        ]))

        XCTAssertEqual(action.kind, .closeViewer)
        XCTAssertGreaterThan(action.point.x, 0.85)
        XCTAssertLessThan(action.point.y, 0.18)
        XCTAssertTrue(action.requiredSafeRegion?.contains(action.point) == true)
        XCTAssertTrue(ActionSafetyValidator().validate(
            action,
            exclusionZones: [],
            emergencyStopActive: false,
            liveInputEnabled: true
        ).isAllowed)
    }

    func testInterstitialStoreLandingUsesDedicatedTopLeftCloseRegion() throws {
        let action = try XCTUnwrap(InterstitialAdDismissPlanner().closeAction(observations: [
            OCRObservation(
                text: "Age Rating 18+ In-App Purchases",
                confidence: 0.95,
                bounds: NormalizedRect(x: 0.2, y: 0.3, width: 0.5, height: 0.05)
            )
        ]))

        XCTAssertEqual(action.kind, .closeViewer)
        XCTAssertLessThan(action.point.x, 0.15)
        XCTAssertLessThan(action.point.y, 0.20)
        XCTAssertTrue(action.requiredSafeRegion?.contains(action.point) == true)
    }

    func testInterstitialCloseRefusesVisibleProfileTabs() {
        let action = InterstitialAdDismissPlanner().closeAction(observations: [
            OCRObservation(text: "About Me", confidence: 0.95, bounds: NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.03)),
            OCRObservation(text: "Moments 6", confidence: 0.95, bounds: NormalizedRect(x: 0.4, y: 0.2, width: 0.2, height: 0.03)),
            OCRObservation(text: "Achievements", confidence: 0.95, bounds: NormalizedRect(x: 0.7, y: 0.2, width: 0.2, height: 0.03)),
            OCRObservation(text: "Ad-Free Experience", confidence: 0.95, bounds: NormalizedRect(x: 0.5, y: 0.6, width: 0.3, height: 0.03))
        ])

        XCTAssertNil(action)
    }

    func testOverflowMenuDismissUsesOnlyBottomCancelAnchor() throws {
        let action = try XCTUnwrap(ProfileOverflowMenuDismissPlanner().cancelAction(observations: [
            OCRObservation(text: "Block", confidence: 0.98, bounds: NormalizedRect(x: 0.42, y: 0.70, width: 0.16, height: 0.03)),
            OCRObservation(text: "Cancel", confidence: 0.98, bounds: NormalizedRect(x: 0.42, y: 0.87, width: 0.16, height: 0.03))
        ]))

        XCTAssertEqual(action.kind, .closeViewer)
        XCTAssertGreaterThan(action.point.y, 0.80)
        XCTAssertTrue(action.requiredSafeRegion?.contains(action.point) == true)
    }

    func testAdMarkerBandCannotBecomeMomentGridTarget() throws {
        let mark = CalibrationMark(
            context: .momentsFeed,
            kind: .safeMomentThumbnailGrid,
            bounds: NormalizedRect(x: 0.057, y: 0.20, width: 0.78, height: 0.66),
            confirmed: true
        )
        let image = try makeMomentGridImage(rows: 3, finalRowColumns: 3)
        let adMarker = OCRObservation(
            text: "Download Now · Ad-Free Experience · AD X",
            confidence: 0.98,
            bounds: NormalizedRect(x: 0.62, y: 0.59, width: 0.31, height: 0.03)
        )

        let targets = MomentThumbnailTargetDetector().targets(
            in: image,
            from: [mark],
            observations: [adMarker]
        )

        XCTAssertFalse(targets.isEmpty)
        XCTAssertTrue(targets.allSatisfy { abs($0.point.y - adMarker.bounds.center.y) > 0.075 })
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

    private func makeMomentGridImage(
        rows: Int,
        finalRowColumns: Int,
        scale: Int = 1,
        includeThreeColumnDistractor: Bool = false,
        darkGutters: Bool = false
    ) throws -> CGImage {
        let width = 420 * scale
        let height = 932 * scale
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
        context.fill(CGRect(
            x: 24 * scale,
            y: 170 * scale,
            width: 326 * scale,
            height: 120 * scale
        ))

        let cell = 106 * scale
        let gutter = 5 * scale
        let left = 24 * scale
        let top = 360 * scale
        if darkGutters {
            context.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1))
            context.fill(CGRect(
                x: left,
                y: top,
                width: cell * 3 + gutter * 2,
                height: rows * cell + max(0, rows - 1) * gutter
            ))
        }
        if includeThreeColumnDistractor {
            context.setFillColor(CGColor(red: 0.45, green: 0.25, blue: 0.65, alpha: 1))
            for column in 0..<3 {
                context.fill(CGRect(
                    x: left + column * (cell + gutter),
                    y: 205 * scale,
                    width: cell,
                    height: cell
                ))
            }
        }
        for row in 0..<rows {
            let columnCount = row == rows - 1 ? finalRowColumns : 3
            for column in 0..<columnCount {
                let red = CGFloat(0.2 + Double((row + column) % 3) * 0.2)
                context.setFillColor(CGColor(red: red, green: 0.25, blue: 0.55, alpha: 1))
                context.fill(CGRect(
                    x: left + column * (cell + gutter),
                    y: top + row * (cell + gutter),
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
