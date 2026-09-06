import Foundation
import XCTest
@testable import ProfileCuratorCore

final class JimuReplayTests: XCTestCase {
    private func fixture(age: Any = 29, state: String = "PRESENT") -> [String: Any] {
        let value: Any = state == "PRESENT" ? age : NSNull()
        return [
            "schema_version": "1.0.0", "record_type": "ProfileObservation",
            "data_classification": "SYNTHETIC_FIXTURE", "observation_id": "obs-test",
            "encounter_id": "enc-test", "profile_id": NSNull(), "platform": "synthetic",
            "account_id": "account-test", "device_id": "device-test", "device_boot_id": "boot-test",
            "session_id": "session-test", "lease_epoch": 1, "app_version": "test-1",
            "adapter_manifest_id": "test-adapter-1", "observed_at": "2026-01-01T12:00:00Z",
            "frame_sha256": String(repeating: "a", count: 64), "source_envelope_ids": ["env-test"],
            "fields": [
                ["field_id": "age-1", "name": "displayed_age", "state": state, "value": value,
                 "source_kind": "PLATFORM_DISPLAY", "source_observation_ids": ["env-test"],
                 "raw_text": state == "PRESENT" ? String(describing: age) as Any : NSNull(),
                 "extractor_version": "test-1", "extraction_confidence": 1.0],
                ["field_id": "posts-1", "name": "post_count", "state": "NOT_OBSERVED", "value": NSNull(),
                 "source_kind": "PLATFORM_DISPLAY", "source_observation_ids": ["env-test"],
                 "raw_text": NSNull(), "extractor_version": "test-1", "extraction_confidence": NSNull()]
            ],
            "eligibility": ["status": "UNKNOWN", "displayed_age": NSNull(), "source_field_ids": [], "rule_version": "test-rule-1"],
            "rights_scope_id": "synthetic-test-only",
            "reachability": ["state": "CURRENT_CARD", "revisit_contract_id": NSNull(), "reachable_until": NSNull()]
        ]
    }
    private func confirmed(_ age: Int = 29) -> [String: Any] {
        var value = fixture(age: age)
        value["eligibility"] = ["status": age >= 18 ? "ACCEPTED_ADULT_DISPLAY" : "INELIGIBLE", "displayed_age": age,
                                "source_field_ids": ["age-1"], "rule_version": "test-rule-1"]
        return value
    }
    private func data(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func policy(min: Int = 18, max: Int = 65, scopes: [String] = []) -> JimuReplayPolicy {
        JimuReplayPolicy(policyID: "test-policy-1", minimumAge: min, maximumAge: max, allowedRightsScopeIDs: scopes)
    }
    private func inspect(_ value: [String: Any], policy p: JimuReplayPolicy? = nil) throws -> JimuReplayReport {
        try JimuReplay.inspect(data(value), policy: p)
    }
    private func rejection(_ value: [String: Any], _ code: String) throws {
        XCTAssertThrowsError(try inspect(value, policy: policy())) { error in
            XCTAssertEqual((error as? JimuReplayError)?.code, code)
        }
    }
    func testValidReplayIsInspectableButCannotEngage() throws {
        let report = try inspect(confirmed(), policy: policy())
        XCTAssertEqual(report.observationID, "obs-test")
        XCTAssertEqual(report.ageEligibility, "ELIGIBLE_FOR_REVIEW")
        XCTAssertEqual(report.engagementState, "DISABLED_OFFLINE")
        XCTAssertEqual(report.enabledActions, [])
        XCTAssertEqual(report.candidateEligibility, "NOT_EVALUATED")
    }
    func testUnconfiguredPolicyCannotEngage() throws {
        XCTAssertEqual(try inspect(confirmed()).ageEligibility, "NO_ENGAGEMENT")
        XCTAssertEqual(try inspect(confirmed()).reasonCodes, ["policy_not_configured"])
    }
    func testUnknownPostsStayUnknownNotZero() throws {
        let field = try XCTUnwrap(inspect(confirmed(), policy: policy()).fields.first { $0.name == "post_count" })
        XCTAssertEqual(field.state, "NOT_OBSERVED")
        XCTAssertEqual(field.value, .null)
    }
    func testUnderageIsRejected() throws {
        XCTAssertEqual(try inspect(confirmed(17), policy: policy()).ageEligibility, "NO_ENGAGEMENT")
    }
    func testConfiguredBoundsAreInclusive() throws {
        XCTAssertEqual(try inspect(confirmed(21), policy: policy(min: 21, max: 30)).ageEligibility, "ELIGIBLE_FOR_REVIEW")
        XCTAssertEqual(try inspect(confirmed(30), policy: policy(min: 21, max: 30)).ageEligibility, "ELIGIBLE_FOR_REVIEW")
    }
    func testConfiguredOutOfRangeIsRejected() throws {
        XCTAssertEqual(try inspect(confirmed(20), policy: policy(min: 21, max: 30)).ageEligibility, "NO_ENGAGEMENT")
        XCTAssertEqual(try inspect(confirmed(31), policy: policy(min: 21, max: 30)).ageEligibility, "NO_ENGAGEMENT")
    }
    func testUnknownUnreadableAbsentAndConflictAgeCannotEngage() throws {
        for state in ["ABSENT", "NOT_OBSERVED", "UNREADABLE", "CONFLICT"] {
            XCTAssertEqual(try inspect(fixture(state: state), policy: policy()).ageEligibility, "NO_ENGAGEMENT", state)
        }
    }
    func testAssertedAdultStatusCannotOverrideMissingAge() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[0]["state"] = "NOT_OBSERVED"; fields[0]["value"] = NSNull(); value["fields"] = fields
        XCTAssertEqual(try inspect(value, policy: policy()).ageEligibility, "NO_ENGAGEMENT")
    }
    func testContradictoryAssertedAgeCannotEngage() throws {
        var value = confirmed(); var claim = value["eligibility"] as! [String: Any]
        claim["displayed_age"] = 30; value["eligibility"] = claim
        XCTAssertEqual(try inspect(value, policy: policy()).ageEligibility, "NO_ENGAGEMENT")
    }
    func testConflictingAgeSourcesCannotEngage() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        var second = fields[0]; second["field_id"] = "age-2"; second["value"] = 30
        fields.append(second); value["fields"] = fields
        XCTAssertEqual(try inspect(value, policy: policy()).ageEligibility, "NO_ENGAGEMENT")
    }
    func testStringFractionalAndBooleanAgeAreNotExplicitIntegerAge() throws {
        for age: Any in ["29", 29.5, true] {
            XCTAssertEqual(try inspect(fixture(age: age), policy: policy()).ageEligibility, "NO_ENGAGEMENT")
        }
    }
    func testVisualAgeEstimateCannotSubstituteForDisplayedAge() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[0]["name"] = "visual_age_estimate"; value["fields"] = fields
        XCTAssertEqual(try inspect(value, policy: policy()).ageEligibility, "NO_ENGAGEMENT")
    }
    func testDisallowedSourceKindIsRejected() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[0]["source_kind"] = "MODEL_GUESS"; value["fields"] = fields
        try rejection(value, "invalid_source_kind")
    }
    func testDanglingSourceReferenceIsRejected() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[0]["source_observation_ids"] = ["unknown-envelope"]; value["fields"] = fields
        try rejection(value, "dangling_source_reference")
    }
    func testDuplicateFieldIDsAreRejected() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[1]["field_id"] = "age-1"; value["fields"] = fields
        try rejection(value, "duplicate_field_id")
    }
    func testMissingNullableFieldIsNotImplicitNull() throws {
        var value = confirmed(); value.removeValue(forKey: "profile_id")
        try rejection(value, "invalid_observation_keys")
    }
    func testUnknownTopLevelPropertyIsRejected() throws {
        var value = confirmed(); value["execute_now"] = true
        try rejection(value, "invalid_observation_keys")
    }
    func testUnknownSchemaVersionIsRejected() throws {
        var value = confirmed(); value["schema_version"] = "2.0.0"
        try rejection(value, "unsupported_schema")
    }
    func testBadFrameHashIsRejected() throws {
        var value = confirmed(); value["frame_sha256"] = "not-a-hash"
        try rejection(value, "invalid_frame_hash")
    }
    func testInvalidTimestampIsRejected() throws {
        var value = confirmed(); value["observed_at"] = "yesterday"
        try rejection(value, "invalid_observation_time")
    }
    func testUnobservedValueMustBeNull() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[1]["value"] = 0; value["fields"] = fields
        try rejection(value, "field_state_value_mismatch")
    }
    func testPresentFieldCannotBeNull() throws {
        var value = confirmed(); var fields = value["fields"] as! [[String: Any]]
        fields[0]["value"] = NSNull(); value["fields"] = fields
        try rejection(value, "field_state_value_mismatch")
    }
    func testSyntheticClassificationDoesNotPermitRealPlatform() throws {
        var value = confirmed(); value["platform"] = "jimu"
        try rejection(value, "synthetic_platform_mismatch")
    }
    func testClaimedRightsClearedScopeNeedsExternalLocalAdmission() throws {
        var value = confirmed(); value["platform"] = "jimu"; value["data_classification"] = "RIGHTS_CLEARED_PROFILE"
        value["rights_scope_id"] = "consented-offline-fixture-1"
        try rejection(value, "rights_scope_not_admitted")
        let report = try inspect(value, policy: policy(scopes: ["consented-offline-fixture-1"]))
        XCTAssertEqual(report.enabledActions, [])
        XCTAssertEqual(report.engagementState, "DISABLED_OFFLINE")
    }
    func testVerifiedRevisitNeedsContract() throws {
        var value = confirmed(); var reachability = value["reachability"] as! [String: Any]
        reachability["state"] = "VERIFIED_REVISIT"; value["reachability"] = reachability
        try rejection(value, "missing_revisit_contract")
    }
    func testInvalidPolicyCannotLowerAdultFloor() throws {
        for p in [policy(min: 17), policy(min: 31, max: 30), policy(max: 131)] {
            XCTAssertThrowsError(try inspect(confirmed(), policy: p)) { error in
                XCTAssertEqual((error as? JimuReplayError)?.code, "invalid_policy")
            }
        }
    }
    func testErrorsDoNotIncludeProfileContents() throws {
        var value = confirmed(); value["secret_private_field"] = "do-not-echo-private-text"
        XCTAssertThrowsError(try inspect(value, policy: policy())) { error in
            XCTAssertFalse(error.localizedDescription.contains("do-not-echo-private-text"))
        }
    }
    func testOversizedInputFailsBeforeDecode() throws {
        XCTAssertThrowsError(try JimuReplay.inspect(Data(repeating: 32, count: JimuReplay.maximumInputBytes + 1), policy: policy())) { error in
            XCTAssertEqual((error as? JimuReplayError)?.code, "input_too_large")
        }
    }
    func testReportCanBeEncodedWithoutGrantingActions() throws {
        let report = try inspect(confirmed(), policy: policy())
        let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        XCTAssertEqual(result["engagement_state"] as? String, "DISABLED_OFFLINE")
        XCTAssertEqual(result["enabled_actions"] as? [String], [])
        XCTAssertEqual(result["age_eligibility"] as? String, "ELIGIBLE_FOR_REVIEW")
    }
    func testPolicyDecodesFromLocalConfiguration() throws {
        let data = Data(#"{"policy_id":"local-example","minimum_age":18,"maximum_age":65,"allowed_rights_scope_ids":[]}"#.utf8)
        let config = try JSONDecoder().decode(JimuReplayPolicy.self, from: data)
        XCTAssertEqual(config.maximumAge, 65)
        XCTAssertEqual(config.policyID, "local-example")
    }
}
