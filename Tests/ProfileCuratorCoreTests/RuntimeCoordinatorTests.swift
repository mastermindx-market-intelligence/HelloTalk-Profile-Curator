import CoreGraphics
import XCTest
@testable import ProfileCuratorCore

final class RuntimeCoordinatorTests: XCTestCase {
    func testDeterministicCollectionPathAndCheckpointRoundTrip() throws {
        var coordinator = DeterministicRuntimeCoordinator()
        XCTAssertEqual(coordinator.handle(.screenObserved(.profileTop)).current, .scanForPersonalInfo)
        XCTAssertEqual(coordinator.handle(.screenObserved(.profilePersonalInfo)).current, .evaluateMBTI)
        XCTAssertEqual(coordinator.handle(.mbtiEvaluated(.collectPrimary)).current, .collectTargetProfile)
        XCTAssertEqual(coordinator.handle(.profileCaptureComplete).current, .inspectPFPViewer)
        XCTAssertEqual(coordinator.snapshot.pendingPostcondition, .viewerDetected)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = CollectionCheckpointStore(fileURL: root)
        let checkpoint = CollectionCheckpoint(
            navigation: coordinator.snapshot,
            currentUsername: "@test",
            currentProfileID: "id",
            scannedPhotoCount: 30,
            retainedPhotoCount: 15,
            perceptualHashes: ["abc"]
        )
        try store.save(checkpoint)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.scannedPhotoCount, 20)
        XCTAssertEqual(restored.retainedPhotoCount, 10)
        XCTAssertEqual(restored.navigation.state, .inspectPFPViewer)
    }

    func testUnknownAndTimeoutFailClosed() {
        var coordinator = DeterministicRuntimeCoordinator()
        XCTAssertEqual(coordinator.handle(.screenObserved(.unknown)).current, .pausedUnknownState)
        XCTAssertEqual(coordinator.handle(.timeout).current, .pausedUnknownState)
        XCTAssertEqual(coordinator.handle(.emergencyStop).current, .emergencyStopped)
    }

    func testFiveHundredUnsafeActionsEmitNoInput() async throws {
        let driver = CountingInputDriver()
        let executor = SafeInputExecutor(driver: driver)
        let exclusion = ExclusionZone(label: "Say Hi", bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        for index in 0..<500 {
            let value = Double(index % 100) / 100
            let action = PlannedAction(
                kind: .openRecommendationCard,
                point: NormalizedPoint(x: value, y: value),
                requiredSafeRegion: nil,
                rationale: "stress"
            )
            let decision = try await executor.executeClick(
                action: action,
                windowFrame: CGRect(x: 0, y: 0, width: 400, height: 800),
                exclusions: [exclusion],
                emergencyStopActive: false,
                sessionPauseReason: nil,
                liveInputEnabled: true
            )
            XCTAssertFalse(decision.isAllowed)
        }
        let emittedCount = await driver.count()
        XCTAssertEqual(emittedCount, 0)
    }

    func testVerticalScrollEmitsOnlyAfterSafetyGatesAndLocksUntilVerified() async throws {
        let driver = RecordingInputDriver()
        let executor = SafeInputExecutor(driver: driver)
        let safe = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let action = PlannedAction(
            kind: .verticalScroll,
            point: safe.center,
            requiredSafeRegion: safe,
            rationale: "bounded scroll"
        )
        let frame = CGRect(x: 50, y: 100, width: 420, height: 932)

        let blocked = try await executor.executeVerticalScroll(
            action: action,
            lines: -7,
            windowFrame: frame,
            exclusions: [],
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: false
        )
        XCTAssertEqual(blocked.rejection, .dryRunRequired)
        let blockedCommands = await driver.commands
        XCTAssertTrue(blockedCommands.isEmpty)

        let allowed = try await executor.executeVerticalScroll(
            action: action,
            lines: -7,
            windowFrame: frame,
            exclusions: [],
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: true
        )
        XCTAssertTrue(allowed.isAllowed)

        let unresolved = try await executor.executeVerticalScroll(
            action: action,
            lines: -7,
            windowFrame: frame,
            exclusions: [],
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: true
        )
        XCTAssertFalse(unresolved.isAllowed)
        let unresolvedCommands = await driver.commands
        XCTAssertEqual(unresolvedCommands, [.verticalScroll(lines: -7, at: safe.center)])

        await executor.resolvePostcondition(passed: true)
        let afterVerification = try await executor.executeVerticalScroll(
            action: action,
            lines: 10,
            windowFrame: frame,
            exclusions: [],
            emergencyStopActive: false,
            sessionPauseReason: nil,
            liveInputEnabled: true
        )
        XCTAssertTrue(afterVerification.isAllowed)
        let verifiedCommands = await driver.commands
        XCTAssertEqual(
            verifiedCommands,
            [.verticalScroll(lines: -7, at: safe.center), .verticalScroll(lines: 10, at: safe.center)]
        )
    }
}

private actor CountingInputDriver: InputDriving {
    private var emitted = 0
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws { emitted += 1 }
    func count() -> Int { emitted }
}

private actor RecordingInputDriver: InputDriving {
    private(set) var commands: [InputCommand] = []
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws { commands.append(command) }
}
