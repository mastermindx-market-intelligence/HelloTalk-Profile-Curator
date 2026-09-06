import Foundation
import CryptoKit

public struct JimuObservationSummary: Identifiable, Sendable {
    public let id: String
    public let platform: String
    public let accountID: String
    public let observedAt: String
    public let importedAt: Date
}

public struct JimuStoredObservation: Identifiable, Sendable {
    public let id: String
    public let platform: String
    public let accountID: String
    public let encounterID: String
    public let profileID: String?
    public let rawData: Data
    public let inputSHA256: String
    public let importedAt: Date
    public let importReport: JimuReplayReport
    public let importPolicy: JimuReplayPolicy?
}

public struct JimuCorrection: Identifiable, Codable, Sendable {
    public let id: String
    public let observationID: String
    public let fieldID: String
    public let state: String
    public let value: JimuJSON
    public let reason: String
    public let supersedesID: String?
    public let createdAt: Date
}

public struct JimuInspectorSnapshot: Identifiable, Sendable {
    public var id: String { observation.id }
    public let observation: JimuStoredObservation
    /// Recomputed from original evidence under the current local policy, not manual age edits.
    public let report: JimuReplayReport
    public let corrections: [JimuCorrection]
    public let basis: JimuFeedbackBasis
    public var revision: String { basis.revision }
    public var preferenceLabelsAllowed: Bool {
        report.ageEligibility == "ELIGIBLE_FOR_REVIEW" &&
        report.fields.filter { $0.name == "displayed_age" }.allSatisfy { $0.sourceKind != "HUMAN_CORRECTION" } &&
        !corrections.contains { correction in
            report.fields.contains { $0.fieldID == correction.fieldID && $0.name == "displayed_age" }
        }
    }
    public var effectiveFields: [JimuReplayField] {
        report.fields.map { original in
            guard let correction = corrections.last(where: { $0.fieldID == original.fieldID }) else { return original }
            return JimuReplayField(fieldID: original.fieldID, name: original.name, state: correction.state,
                value: correction.value, sourceKind: "HUMAN_CORRECTION", sourceObservationIDs: original.sourceObservationIDs,
                rawText: nil, extractorVersion: "manual-correction-v1", extractionConfidence: nil)
        }
    }
}

/// A training label names the exact evidence version shown. Corrections never rewrite this basis.
public struct JimuFeedbackBasis: Codable, Sendable {
    public let observationID: String
    public let inputSHA256: String
    public let correctionIDs: [String]
    public let policy: JimuReplayPolicy?
    public let revision: String
    public let presentationKind: String
    public let modelScoresVisible: Bool
}

public enum JimuFeedbackScope: String, Codable, CaseIterable, Sendable {
    case visualOnly = "visual_only", fullProfile = "full_profile", scarceAction = "scarce_action"
}
public enum JimuFeedbackChoice: String, Codable, Sendable {
    case approve, reject, left, right, tie, neither, pass, rightSwipe = "right_swipe", note, instant, inspect, hold
}
public struct JimuFeedback: Identifiable, Codable, Sendable {
    public let id: String
    public let scope: JimuFeedbackScope
    public let choice: JimuFeedbackChoice
    public let basis: JimuFeedbackBasis
    public let comparison: JimuFeedbackBasis?
    public let actionContext: String?
    public let supersedesID: String?
    public let createdAt: Date
}

public extension JimuJSON {
    var inspectorText: String {
        switch self {
        case .null: return "Unknown / not supplied"
        case .string(let value): return value
        default: return (try? String(decoding: JimuInspectorCoding.encode(self), as: UTF8.self)) ?? "Unrenderable value"
        }
    }
    var inspectorJSON: String {
        (try? String(decoding: JimuInspectorCoding.encode(self), as: UTF8.self)) ?? "null"
    }
}

enum JimuInspectorCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func basis(observation: JimuStoredObservation, corrections: [JimuCorrection], policy: JimuReplayPolicy?) throws -> JimuFeedbackBasis {
        struct Revision: Encodable { let input: String; let corrections: [String]; let policy: JimuReplayPolicy? }
        let correctionIDs = corrections.map(\.id)
        let revision = digest(try encode(Revision(input: observation.inputSHA256, corrections: correctionIDs, policy: policy)))
        return JimuFeedbackBasis(observationID: observation.id, inputSHA256: observation.inputSHA256,
            correctionIDs: correctionIDs, policy: policy, revision: revision,
            presentationKind: "TEXT_EVIDENCE_ONLY_V1", modelScoresVisible: false)
    }
}
