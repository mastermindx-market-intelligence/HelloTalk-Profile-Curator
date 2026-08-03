import XCTest
@testable import ProfileCuratorCore

final class ActionSafetyTests: XCTestCase {
    private let validator = ActionSafetyValidator()
    private let safeRegion = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)

    func testDryRunBlocksOtherwiseSafeAction() {
        let action = PlannedAction(
            kind: .openAvatar,
            point: NormalizedPoint(x: 0.3, y: 0.3),
            requiredSafeRegion: safeRegion,
            rationale: "test"
        )

        let decision = validator.validate(
            action,
            exclusionZones: [],
            emergencyStopActive: false,
            liveInputEnabled: false
        )

        XCTAssertEqual(decision.rejection, .dryRunRequired)
    }

    func testExclusionZoneWinsBeforeLiveInputGate() {
        let action = PlannedAction(
            kind: .openRecommendationCard,
            point: NormalizedPoint(x: 0.3, y: 0.3),
            requiredSafeRegion: safeRegion,
            rationale: "test"
        )
        let exclusion = ExclusionZone(
            label: "Say Hi",
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        )

        let decision = validator.validate(
            action,
            exclusionZones: [exclusion],
            emergencyStopActive: false,
            liveInputEnabled: true
        )

        XCTAssertEqual(decision.rejection, .intersectsExclusionZone("Say Hi"))
    }

    func testEmergencyStopBlocksAction() {
        let action = PlannedAction(
            kind: .selectMoments,
            point: NormalizedPoint(x: 0.3, y: 0.3),
            requiredSafeRegion: safeRegion,
            rationale: "test"
        )

        let decision = validator.validate(
            action,
            exclusionZones: [],
            emergencyStopActive: true,
            liveInputEnabled: true
        )

        XCTAssertEqual(decision.rejection, .emergencyStopActive)
    }

    func testSafeLiveActionCanPassAllGeometryGates() {
        let action = PlannedAction(
            kind: .closeViewer,
            point: NormalizedPoint(x: 0.3, y: 0.3),
            requiredSafeRegion: safeRegion,
            rationale: "test"
        )

        let decision = validator.validate(
            action,
            exclusionZones: [],
            emergencyStopActive: false,
            liveInputEnabled: true
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.rejection)
    }
}
