import Foundation

/// JSON evidence, not a model assessment. Keeps null distinct from zero and false.
public enum JimuJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JimuJSON]), object([String: JimuJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JimuJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JimuJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    fileprivate var text: String? { if case .string(let v) = self { return v }; return nil }
    fileprivate var number: Double? { if case .number(let v) = self { return v }; return nil }
    fileprivate var integer: Int? { number.flatMap(Int.init(exactly:)) }
    fileprivate var object: [String: JimuJSON]? { if case .object(let v) = self { return v }; return nil }
    fileprivate var array: [JimuJSON]? { if case .array(let v) = self { return v }; return nil }
}

/// Loaded explicitly from a local file. No individual's preferences are compiled into source.
/// Scope admission permits offline inspection only, never platform access or live action.
public struct JimuReplayPolicy: Codable, Sendable {
    public let policyID: String
    public let minimumAge: Int
    public let maximumAge: Int
    public let allowedRightsScopeIDs: [String]

    enum CodingKeys: String, CodingKey {
        case policyID = "policy_id", minimumAge = "minimum_age", maximumAge = "maximum_age"
        case allowedRightsScopeIDs = "allowed_rights_scope_ids"
    }
    public init(policyID: String, minimumAge: Int, maximumAge: Int, allowedRightsScopeIDs: [String]) {
        self.policyID = policyID; self.minimumAge = minimumAge; self.maximumAge = maximumAge
        self.allowedRightsScopeIDs = allowedRightsScopeIDs
    }
    fileprivate func validate() throws {
        guard !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              minimumAge >= 18, maximumAge >= minimumAge, maximumAge <= 130,
              allowedRightsScopeIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw JimuReplayError(code: "invalid_policy")
        }
    }
}

public struct JimuReplayField: Codable, Equatable, Sendable {
    public let fieldID: String
    public let name: String
    public let state: String
    public let value: JimuJSON
    public let sourceKind: String
    public let sourceObservationIDs: [String]
    public let rawText: String?
    public let extractorVersion: String
    public let extractionConfidence: Double?
    enum CodingKeys: String, CodingKey {
        case fieldID = "field_id", name, state, value, sourceKind = "source_kind"
        case sourceObservationIDs = "source_observation_ids", rawText = "raw_text"
        case extractorVersion = "extractor_version", extractionConfidence = "extraction_confidence"
    }
}

/// An inert inspection projection. It intentionally has no executor or active capability grant.
public struct JimuReplayReport: Codable, Sendable {
    public let observationID: String
    public let platform: String
    public let dataClassification: String
    public let observedAt: String
    public let frameSHA256: String
    public let policyID: String?
    public let fields: [JimuReplayField]
    public let ageEligibility: String
    public let reasonCodes: [String]
    public let engagementState: String
    public let enabledActions: [String]
    public let candidateEligibility: String
    public let nativeCapabilityState: String
    enum CodingKeys: String, CodingKey {
        case observationID = "observation_id", platform, dataClassification = "data_classification"
        case observedAt = "observed_at", frameSHA256 = "frame_sha256", policyID = "policy_id", fields
        case ageEligibility = "age_eligibility", reasonCodes = "reason_codes"
        case engagementState = "engagement_state", enabledActions = "enabled_actions"
        case candidateEligibility = "candidate_eligibility", nativeCapabilityState = "native_capability_state"
    }
}

public struct JimuReplayError: Error, LocalizedError, Sendable {
    public let code: String
    public init(code: String) { self.code = code }
    public var errorDescription: String? { code }
}

public enum JimuReplay {
    public static let maximumInputBytes = 2 * 1024 * 1024
    public static let schemaVersion = "1.0.0"
    private static let observationKeys: Set<String> = [
        "schema_version", "record_type", "data_classification", "observation_id", "encounter_id", "profile_id",
        "platform", "account_id", "device_id", "device_boot_id", "session_id", "lease_epoch", "app_version",
        "adapter_manifest_id", "observed_at", "frame_sha256", "source_envelope_ids", "fields", "eligibility",
        "rights_scope_id", "reachability"
    ]
    private static let fieldKeys: Set<String> = [
        "field_id", "name", "state", "value", "source_kind", "source_observation_ids", "raw_text",
        "extractor_version", "extraction_confidence"
    ]

    public static func inspect(_ data: Data, policy: JimuReplayPolicy?) throws -> JimuReplayReport {
        guard data.count <= maximumInputBytes else { throw JimuReplayError(code: "input_too_large") }
        try policy?.validate()
        let document: JimuJSON
        do { document = try JSONDecoder().decode(JimuJSON.self, from: data) }
        catch { throw JimuReplayError(code: "invalid_json") }
        let o = try exactObject(document, keys: observationKeys, code: "invalid_observation_keys")
        guard o["schema_version"]?.text == schemaVersion, o["record_type"]?.text == "ProfileObservation" else {
            throw JimuReplayError(code: "unsupported_schema")
        }
        for key in ["observation_id", "encounter_id", "account_id", "device_id", "device_boot_id", "session_id", "app_version", "adapter_manifest_id", "rights_scope_id"] {
            _ = try text(o[key], code: "invalid_identifier")
        }
        try nullableText(o["profile_id"], code: "invalid_profile_id")
        guard let epoch = o["lease_epoch"]?.integer, epoch >= 0 else { throw JimuReplayError(code: "invalid_lease_epoch") }
        let observedAt = try text(o["observed_at"], code: "invalid_observation_time")
        guard validTimestamp(observedAt) else { throw JimuReplayError(code: "invalid_observation_time") }
        let hash = try text(o["frame_sha256"], code: "invalid_frame_hash")
        guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw JimuReplayError(code: "invalid_frame_hash")
        }
        let classification = try member(o["data_classification"], ["SYNTHETIC_FIXTURE", "RIGHTS_CLEARED_PROFILE"], "invalid_classification")
        let platform = try member(o["platform"], ["synthetic", "jimu", "hellotalk"], "invalid_platform")
        let rightsScope = try text(o["rights_scope_id"], code: "invalid_rights_scope")
        if classification == "SYNTHETIC_FIXTURE" {
            guard platform == "synthetic", rightsScope == "synthetic-test-only" else {
                throw JimuReplayError(code: "synthetic_platform_mismatch")
            }
        } else {
            guard platform != "synthetic", policy?.allowedRightsScopeIDs.contains(rightsScope) == true else {
                throw JimuReplayError(code: "rights_scope_not_admitted")
            }
        }
        let envelopes = try strings(o["source_envelope_ids"], allowEmpty: false, code: "invalid_envelope_ids")
        guard Set(envelopes).count == envelopes.count else { throw JimuReplayError(code: "duplicate_envelope_id") }
        guard let rawFields = o["fields"]?.array else { throw JimuReplayError(code: "invalid_fields") }
        var fields: [JimuReplayField] = []
        var fieldIDs = Set<String>()
        for rawField in rawFields {
            let f = try exactObject(rawField, keys: fieldKeys, code: "invalid_field_keys")
            let id = try text(f["field_id"], code: "invalid_field_id")
            guard fieldIDs.insert(id).inserted else { throw JimuReplayError(code: "duplicate_field_id") }
            let state = try member(f["state"], ["PRESENT", "ABSENT", "NOT_OBSERVED", "UNREADABLE", "CONFLICT"], "invalid_field_state")
            guard let value = f["value"], (state == "PRESENT") == (value != .null) else {
                throw JimuReplayError(code: "field_state_value_mismatch")
            }
            let source = try member(f["source_kind"], ["UI_TREE", "OCR", "PLATFORM_DISPLAY", "HUMAN_CORRECTION"], "invalid_source_kind")
            let references = try strings(f["source_observation_ids"], allowEmpty: false, code: "invalid_source_reference")
            guard Set(references).isSubset(of: Set(envelopes)) else { throw JimuReplayError(code: "dangling_source_reference") }
            try nullableText(f["raw_text"], code: "invalid_raw_text")
            let confidence = f["extraction_confidence"]?.number
            guard f["extraction_confidence"] == .null || (confidence.map { $0.isFinite && (0...1).contains($0) } == true) else {
                throw JimuReplayError(code: "invalid_extraction_confidence")
            }
            fields.append(JimuReplayField(fieldID: id, name: try text(f["name"], code: "invalid_field_name"),
                state: state, value: value, sourceKind: source, sourceObservationIDs: references,
                rawText: f["raw_text"]?.text, extractorVersion: try text(f["extractor_version"], code: "invalid_extractor_version"),
                extractionConfidence: confidence))
        }
        let claim = try exactObject(o["eligibility"], keys: ["status", "displayed_age", "source_field_ids", "rule_version"], code: "invalid_eligibility_keys")
        let status = try member(claim["status"], ["ACCEPTED_ADULT_DISPLAY", "INELIGIBLE", "UNKNOWN"], "invalid_eligibility_status")
        let claimedAge = claim["displayed_age"]?.integer
        guard claim["displayed_age"] == .null || (claimedAge.map { (0...130).contains($0) } == true) else {
            throw JimuReplayError(code: "invalid_eligibility_age")
        }
        let ageReferences = try strings(claim["source_field_ids"], allowEmpty: true, code: "invalid_age_reference")
        guard Set(ageReferences).isSubset(of: fieldIDs) else { throw JimuReplayError(code: "dangling_age_reference") }
        _ = try text(claim["rule_version"], code: "invalid_rule_version")
        if status == "ACCEPTED_ADULT_DISPLAY" {
            guard claimedAge.map({ $0 >= 18 }) == true, !ageReferences.isEmpty else {
                throw JimuReplayError(code: "invalid_eligibility_claim")
            }
        }
        let reach = try exactObject(o["reachability"], keys: ["state", "revisit_contract_id", "reachable_until"], code: "invalid_reachability_keys")
        let reachState = try member(reach["state"], ["CURRENT_CARD", "VERIFIED_REVISIT", "NOT_REACHABLE", "UNKNOWN"], "invalid_reachability_state")
        try nullableText(reach["revisit_contract_id"], code: "invalid_revisit_contract")
        try nullableText(reach["reachable_until"], code: "invalid_reachability_time")
        if let until = reach["reachable_until"]?.text, !validTimestamp(until) { throw JimuReplayError(code: "invalid_reachability_time") }
        if reachState == "VERIFIED_REVISIT" { _ = try text(reach["revisit_contract_id"], code: "missing_revisit_contract") }

        let reason = eligibilityReason(fields: fields, status: status, claimedAge: claimedAge, references: ageReferences, policy: policy)
        return JimuReplayReport(observationID: try text(o["observation_id"], code: "invalid_identifier"),
            platform: platform, dataClassification: classification, observedAt: observedAt, frameSHA256: hash,
            policyID: policy?.policyID, fields: fields,
            ageEligibility: reason == nil ? "ELIGIBLE_FOR_REVIEW" : "NO_ENGAGEMENT",
            reasonCodes: reason.map { [$0] } ?? [], engagementState: "DISABLED_OFFLINE", enabledActions: [],
            candidateEligibility: "NOT_EVALUATED", nativeCapabilityState: "UNVERIFIED")
    }

    private static func eligibilityReason(fields: [JimuReplayField], status: String, claimedAge: Int?, references: [String], policy: JimuReplayPolicy?) -> String? {
        guard let policy else { return "policy_not_configured" }
        let ageFields = fields.filter { $0.name == "displayed_age" }
        guard !ageFields.isEmpty, ageFields.allSatisfy({ $0.state == "PRESENT" && $0.value.integer != nil }) else {
            return "age_evidence_missing_or_ambiguous"
        }
        let ages = Set(ageFields.compactMap { $0.value.integer })
        guard ages.count == 1, let age = ages.first else { return "age_evidence_conflict" }
        guard age >= 18, age >= policy.minimumAge, age <= policy.maximumAge else { return "age_out_of_range" }
        let validSources = Set(ageFields.map(\.fieldID))
        guard status == "ACCEPTED_ADULT_DISPLAY", claimedAge == age,
              !references.isEmpty, Set(references).isSubset(of: validSources) else { return "adult_claim_not_supported" }
        return nil
    }

    private static func exactObject(_ value: JimuJSON?, keys: Set<String>, code: String) throws -> [String: JimuJSON] {
        guard let object = value?.object, Set(object.keys) == keys else { throw JimuReplayError(code: code) }
        return object
    }
    private static func text(_ value: JimuJSON?, code: String) throws -> String {
        guard let string = value?.text, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw JimuReplayError(code: code) }
        return string
    }
    private static func nullableText(_ value: JimuJSON?, code: String) throws {
        guard value == .null || value?.text != nil else { throw JimuReplayError(code: code) }
    }
    private static func strings(_ value: JimuJSON?, allowEmpty: Bool, code: String) throws -> [String] {
        guard let array = value?.array, allowEmpty || !array.isEmpty else { throw JimuReplayError(code: code) }
        return try array.map { try text($0, code: code) }
    }
    private static func member(_ value: JimuJSON?, _ allowed: Set<String>, _ code: String) throws -> String {
        let string = try text(value, code: code)
        guard allowed.contains(string) else { throw JimuReplayError(code: code) }
        return string
    }
    private static func validTimestamp(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text) != nil
    }
}
