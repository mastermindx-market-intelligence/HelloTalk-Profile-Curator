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
}

private actor CountingInputDriver: InputDriving {
    private var emitted = 0
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws { emitted += 1 }
    func count() -> Int { emitted }
}
