import Foundation
import XCTest
@preconcurrency import GRDB
@testable import ProfileCuratorCore

final class JimuInspectorTests: XCTestCase {
    private var root: URL!
    private var repository: ProfileRepository!
    private let policy = JimuReplayPolicy(policyID: "synthetic-review-v1", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repository = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
    }
    override func tearDownWithError() throws {
        repository = nil
        try FileManager.default.removeItem(at: root)
    }
    private func fixture(id: String = "obs-synthetic-001", age: Int = 29) throws -> Data {
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: sourceRoot.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["observation_id"] = id
        var fields = try XCTUnwrap(object["fields"] as? [[String: Any]])
        fields[0]["value"] = age
        fields[0]["raw_text"] = String(age)
        object["fields"] = fields
        var eligibility = try XCTUnwrap(object["eligibility"] as? [String: Any])
        eligibility["displayed_age"] = age
        eligibility["status"] = age >= 18 ? "ACCEPTED_ADULT_DISPLAY" : "INELIGIBLE"
        object["eligibility"] = eligibility
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func imported(id: String = "obs-synthetic-001", age: Int = 29) throws -> JimuInspectorSnapshot {
        let stored = try repository.importJimuObservation(fixture(id: id, age: age), policy: policy)
        return try repository.jimuSnapshot(id: stored.id, policy: policy)
    }
    private func assertCode(_ expected: String, _ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual((error as? JimuReplayError)?.code, expected, file: file, line: line)
        }
    }

    func testImportPreservesExactBytesAndUnknownCounts() throws {
        let bytes = try fixture()
        let record = try repository.importJimuObservation(bytes, policy: policy)
        XCTAssertEqual(record.rawData, bytes)
        XCTAssertEqual(record.accountID, "account-synthetic")
        XCTAssertNil(record.profileID)
        let snapshot = try repository.jimuSnapshot(id: record.id, policy: policy)
        let posts = try XCTUnwrap(snapshot.effectiveFields.first { $0.name == "post_count" })
        XCTAssertEqual(posts.state, "NOT_OBSERVED")
        XCTAssertEqual(posts.value, .null)
        XCTAssertEqual(snapshot.report.enabledActions, [])
    }
    func testIdenticalImportIsIdempotentAndCannotRewriteImportPolicy() throws {
        let data = try fixture()
        let first = try repository.importJimuObservation(data, policy: policy, now: Date(timeIntervalSince1970: 100))
        let second = try repository.importJimuObservation(data, policy: nil)
        XCTAssertEqual(first.importedAt, second.importedAt)
        XCTAssertEqual(second.importReport.policyID, policy.policyID)
        XCTAssertEqual(try repository.jimuObservations().count, 1)
    }
    func testSameIdentifierDifferentBytesConflictsWithoutOverwrite() throws {
        let first = try repository.importJimuObservation(fixture(), policy: policy)
        assertCode("observation_id_conflict") {
            _ = try repository.importJimuObservation(self.fixture(age: 30), policy: self.policy)
        }
        XCTAssertEqual(try repository.jimuSnapshot(id: first.id, policy: policy).observation.rawData, first.rawData)
    }
    func testMalformedImportLeavesNoPartialRow() throws {
        XCTAssertThrowsError(try repository.importJimuObservation(Data("{}".utf8), policy: policy))
        XCTAssertTrue(try repository.jimuObservations().isEmpty)
    }
    func testShorterCorrectionAppendsAndOriginalSurvivesRestart() throws {
        let before = try imported()
        let change = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("Music."), reason: "Corrected transcript")
        repository = try ProfileRepository(databasePath: repository.databasePath)
        let after = try repository.jimuSnapshot(id: before.id, policy: policy)
        XCTAssertEqual(after.observation.rawData, before.observation.rawData)
        XCTAssertEqual(after.corrections.map(\.id), [change.id])
        XCTAssertEqual(after.effectiveFields.first { $0.name == "bio" }?.value, .string("Music."))
        XCTAssertEqual(after.report.fields.first { $0.name == "bio" }?.value, .string("I enjoy hiking and live music."))
        XCTAssertNotEqual(after.revision, before.revision)
    }
    func testCorrectionsKeepSameFieldSupersessionChain() throws {
        let before = try imported()
        let first = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "field-bio-001", state: "UNREADABLE", value: .null, reason: "Unreadable evidence")
        let next = try repository.jimuSnapshot(id: before.id, policy: policy)
        let second = try repository.appendJimuCorrection(snapshot: next, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("Corrected"), reason: "Manual correction")
        XCTAssertEqual(second.supersedesID, first.id)
        XCTAssertEqual(try repository.jimuSnapshot(id: before.id, policy: policy).corrections.count, 2)
    }
    func testStaleCorrectionAndUnknownFieldCannotWrite() throws {
        let before = try imported()
        assertCode("unknown_field") {
            _ = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "missing", state: "PRESENT", value: .string("x"), reason: "test")
        }
        _ = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("x"), reason: "test")
        assertCode("stale_presentation") {
            _ = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("y"), reason: "stale")
        }
        XCTAssertEqual(try repository.jimuSnapshot(id: before.id, policy: policy).corrections.count, 1)
    }
    func testCorrectionRequiresReasonAndConsistentNullState() throws {
        let snapshot = try imported()
        assertCode("correction_reason_required") {
            _ = try repository.appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("x"), reason: " ")
        }
        assertCode("field_state_value_mismatch") {
            _ = try repository.appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: "field-bio-001", state: "NOT_OBSERVED", value: .number(0), reason: "test")
        }
        XCTAssertTrue(try repository.jimuSnapshot(id: snapshot.id, policy: policy).corrections.isEmpty)
    }
    func testAgeCorrectionNeverCreatesNewPlatformAdultEvidence() throws {
        let snapshot = try imported(age: 17)
        _ = try repository.appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: "field-age-001", state: "PRESENT", value: .number(29), reason: "Manual estimate must not establish eligibility")
        let after = try repository.jimuSnapshot(id: snapshot.id, policy: policy)
        XCTAssertFalse(after.preferenceLabelsAllowed)
        assertCode("adult_evidence_required") {
            _ = try repository.recordJimuFeedback(snapshot: after, policy: policy, scope: .fullProfile, choice: .approve)
        }
    }
    func testHumanAuthoredAgeFieldIsNotPlatformAdultEvidence() throws {
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var fields = try XCTUnwrap(document["fields"] as? [[String: Any]])
        fields[0]["source_kind"] = "HUMAN_CORRECTION"
        document["fields"] = fields
        let stored = try repository.importJimuObservation(JSONSerialization.data(withJSONObject: document), policy: policy)
        let snapshot = try repository.jimuSnapshot(id: stored.id, policy: policy)
        XCTAssertFalse(snapshot.preferenceLabelsAllowed)
    }
    func testVisualOnlyFeedbackRefusesMissingIsolatedMedia() throws {
        let snapshot = try imported()
        assertCode("visual_evidence_unavailable") {
            _ = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .visualOnly, choice: .approve)
        }
        XCTAssertTrue(try repository.jimuFeedback(observationID: snapshot.id).isEmpty)
    }
    func testFullProfileAndScarceActionRemainSeparateAndNoActionsEnabled() throws {
        let snapshot = try imported()
        let preference = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .fullProfile, choice: .approve)
        assertCode("action_context_required") {
            _ = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .scarceAction, choice: .note)
        }
        let action = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .scarceAction, choice: .hold, actionContext: "Attention capacity full; recommendation only")
        XCTAssertEqual(preference.scope, .fullProfile)
        XCTAssertEqual(action.scope, .scarceAction)
        XCTAssertEqual(action.basis.revision, snapshot.revision)
        XCTAssertEqual(try repository.jimuSnapshot(id: snapshot.id, policy: policy).report.enabledActions, [])
        XCTAssertEqual(try repository.jimuFeedback(observationID: snapshot.id).count, 2)
    }
    func testFeedbackPreservesShownBasisAcrossLaterCorrectionAndRestart() throws {
        let before = try imported()
        let label = try repository.recordJimuFeedback(snapshot: before, policy: policy, scope: .fullProfile, choice: .approve)
        _ = try repository.appendJimuCorrection(snapshot: before, policy: policy, fieldID: "field-bio-001", state: "PRESENT", value: .string("Shorter"), reason: "New correction")
        repository = try ProfileRepository(databasePath: repository.databasePath)
        let historical = try XCTUnwrap(repository.jimuFeedback(observationID: before.id).first)
        XCTAssertEqual(historical.id, label.id)
        XCTAssertEqual(historical.basis.revision, before.revision)
        XCTAssertEqual(historical.basis.correctionIDs, [])
        assertCode("stale_presentation") {
            _ = try repository.recordJimuFeedback(snapshot: before, policy: policy, scope: .fullProfile, choice: .reject)
        }
    }
    func testChangedPolicyRequiresNewPresentationButDoesNotRewriteOldLabel() throws {
        let before = try imported()
        let label = try repository.recordJimuFeedback(snapshot: before, policy: policy, scope: .fullProfile, choice: .approve)
        let changed = JimuReplayPolicy(policyID: "same-id-not-same-content", minimumAge: 18, maximumAge: 24, allowedRightsScopeIDs: [])
        let current = try repository.jimuSnapshot(id: before.id, policy: changed)
        XCTAssertFalse(current.preferenceLabelsAllowed)
        XCTAssertNotEqual(current.revision, before.revision)
        XCTAssertEqual(try repository.jimuFeedback(observationID: before.id).first?.basis.policy?.policyID, label.basis.policy?.policyID)
    }
    func testPairwiseTieAndNeitherAreBoundToBothPresentedVersions() throws {
        let left = try imported()
        let right = try imported(id: "second-observation")
        let label = try repository.recordJimuFeedback(snapshot: left, policy: policy, scope: .fullProfile, choice: .tie, comparison: right)
        XCTAssertEqual(label.comparison?.observationID, right.id)
        XCTAssertEqual(label.comparison?.revision, right.revision)
        assertCode("invalid_feedback_choice") {
            _ = try repository.recordJimuFeedback(snapshot: left, policy: policy, scope: .fullProfile, choice: .neither)
        }
        assertCode("same_observation_comparison") {
            _ = try repository.recordJimuFeedback(snapshot: left, policy: policy, scope: .fullProfile, choice: .left, comparison: left)
        }
    }
    func testSupersedingFeedbackAppendsWithoutMutatingEarlierChoice() throws {
        let snapshot = try imported()
        let first = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .fullProfile, choice: .approve)
        let second = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .fullProfile, choice: .reject, supersedesID: first.id)
        XCTAssertEqual(second.supersedesID, first.id)
        XCTAssertEqual(try repository.jimuFeedback(observationID: snapshot.id).map(\.choice), [.approve, .reject])
        assertCode("feedback_supersession_conflict") {
            _ = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .fullProfile, choice: .approve, supersedesID: first.id)
        }
    }
    func testObservationDeleteCascadesHistoryAndGlobalDeleteAllIncludesJimu() throws {
        let snapshot = try imported()
        _ = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .fullProfile, choice: .approve)
        _ = try repository.appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: "field-bio-001", state: "ABSENT", value: .null, reason: "Test")
        try repository.deleteJimuObservation(id: snapshot.id)
        XCTAssertTrue(try repository.jimuObservations().isEmpty)
        XCTAssertTrue(try repository.jimuFeedback(observationID: snapshot.id).isEmpty)
        _ = try imported()
        try repository.deleteAll()
        XCTAssertTrue(try repository.jimuObservations().isEmpty)
    }
    func testDatabaseRejectsUpdatesToImmutableRows() throws {
        let snapshot = try imported()
        let verification = try DatabaseQueue(path: repository.databasePath)
        XCTAssertThrowsError(try verification.write { database in
            try database.execute(sql: "UPDATE profile_observations SET platform = 'jimu' WHERE id = ?", arguments: [snapshot.id])
        })
    }
}
