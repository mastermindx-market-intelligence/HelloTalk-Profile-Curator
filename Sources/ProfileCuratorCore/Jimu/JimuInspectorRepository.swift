import Foundation
@preconcurrency import GRDB

/// Lives inside the existing ProfileRepository/GRDB owner. No separate database or migrator.
enum JimuInspectorSchema {
    static func install(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE profile_observations (
                id TEXT PRIMARY KEY NOT NULL, platform TEXT NOT NULL, account_id TEXT NOT NULL,
                encounter_id TEXT NOT NULL, profile_id TEXT, observed_at TEXT NOT NULL,
                imported_at DATETIME NOT NULL, input_sha256 TEXT NOT NULL, raw_data BLOB NOT NULL,
                import_report BLOB NOT NULL, import_policy BLOB
            );
            CREATE INDEX jimu_observation_time ON profile_observations(imported_at, id);
            CREATE TABLE observation_corrections (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                observation_id TEXT NOT NULL REFERENCES profile_observations(id) ON DELETE CASCADE,
                field_id TEXT NOT NULL, payload BLOB NOT NULL
            );
            CREATE INDEX jimu_correction_observation ON observation_corrections(observation_id, sequence);
            CREATE TABLE preference_feedback (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                observation_id TEXT NOT NULL REFERENCES profile_observations(id) ON DELETE CASCADE,
                comparison_id TEXT REFERENCES profile_observations(id) ON DELETE CASCADE,
                supersedes_id TEXT UNIQUE, payload BLOB NOT NULL
            );
            CREATE INDEX jimu_feedback_observation ON preference_feedback(observation_id, sequence);
            CREATE TRIGGER jimu_observations_immutable BEFORE UPDATE ON profile_observations
                BEGIN SELECT RAISE(ABORT, 'immutable_observation'); END;
            CREATE TRIGGER jimu_corrections_immutable BEFORE UPDATE ON observation_corrections
                BEGIN SELECT RAISE(ABORT, 'immutable_correction'); END;
            CREATE TRIGGER jimu_feedback_immutable BEFORE UPDATE ON preference_feedback
                BEGIN SELECT RAISE(ABORT, 'immutable_feedback'); END;
            """)
    }
}

public extension ProfileRepository {
    @discardableResult
    func importJimuObservation(_ data: Data, policy: JimuReplayPolicy?, now: Date = Date()) throws -> JimuStoredObservation {
        let report = try JimuReplay.inspect(data, policy: policy)
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountID = document["account_id"] as? String, let encounterID = document["encounter_id"] as? String else {
            throw JimuReplayError(code: "invalid_observation_metadata")
        }
        let inputHash = JimuInspectorCoding.digest(data)
        let reportData = try JimuInspectorCoding.encode(report)
        let policyData = try policy.map { try JimuInspectorCoding.encode($0) }
        return try databaseQueue.write { database in
            if let existing = try Self.jimuStored(id: report.observationID, database: database) {
                guard existing.inputSHA256 == inputHash, existing.rawData == data else {
                    throw JimuReplayError(code: "observation_id_conflict")
                }
                return existing
            }
            try database.execute(sql: """
                INSERT INTO profile_observations
                (id, platform, account_id, encounter_id, profile_id, observed_at, imported_at, input_sha256, raw_data, import_report, import_policy)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [report.observationID, report.platform, accountID, encounterID,
                    document["profile_id"] as? String, report.observedAt, now, inputHash, data, reportData, policyData])
            guard let stored = try Self.jimuStored(id: report.observationID, database: database) else {
                throw JimuReplayError(code: "observation_insert_failed")
            }
            return stored
        }
    }

    /// A bounded metadata list. It does not expose raw profile contents before scope admission.
    func jimuObservations(limit: Int = 100, offset: Int = 0) throws -> [JimuObservationSummary] {
        try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "SELECT id, platform, account_id, observed_at, imported_at FROM profile_observations ORDER BY imported_at DESC, id LIMIT ? OFFSET ?",
                arguments: [min(200, max(1, limit)), max(0, offset)]).map { row in
                JimuObservationSummary(id: row["id"], platform: row["platform"], accountID: row["account_id"],
                    observedAt: row["observed_at"], importedAt: row["imported_at"])
            }
        }
    }

    func jimuSnapshot(id: String, policy: JimuReplayPolicy?) throws -> JimuInspectorSnapshot {
        try databaseQueue.read { try Self.jimuSnapshot(id: id, policy: policy, database: $0) }
    }

    @discardableResult
    func appendJimuCorrection(snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?, fieldID: String,
        state: String, value: JimuJSON, reason: String, now: Date = Date()) throws -> JimuCorrection {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.utf8.count <= 4_096 else { throw JimuReplayError(code: "correction_reason_required") }
        guard ["PRESENT", "ABSENT", "NOT_OBSERVED", "UNREADABLE", "CONFLICT"].contains(state),
              (state == "PRESENT") == (value != .null) else { throw JimuReplayError(code: "field_state_value_mismatch") }
        guard try JimuInspectorCoding.encode(value).count <= 64 * 1024 else { throw JimuReplayError(code: "correction_too_large") }
        return try databaseQueue.write { database in
            let current = try Self.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            guard current.revision == snapshot.revision else { throw JimuReplayError(code: "stale_presentation") }
            guard current.report.fields.contains(where: { $0.fieldID == fieldID }) else { throw JimuReplayError(code: "unknown_field") }
            let correction = JimuCorrection(id: UUID().uuidString, observationID: snapshot.id, fieldID: fieldID,
                state: state, value: value, reason: reason,
                supersedesID: current.corrections.last(where: { $0.fieldID == fieldID })?.id, createdAt: now)
            try database.execute(sql: "INSERT INTO observation_corrections (id, observation_id, field_id, payload) VALUES (?, ?, ?, ?)",
                arguments: [correction.id, snapshot.id, fieldID, try JimuInspectorCoding.encode(correction)])
            return correction
        }
    }

    @discardableResult
    func recordJimuFeedback(snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?, scope: JimuFeedbackScope,
        choice: JimuFeedbackChoice, comparison: JimuInspectorSnapshot? = nil, actionContext: String? = nil,
        supersedesID: String? = nil, now: Date = Date()) throws -> JimuFeedback {
        // This slice has declared source references, not isolated authenticated image presentation.
        guard scope != .visualOnly else { throw JimuReplayError(code: "visual_evidence_unavailable") }
        let context = actionContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .scarceAction {
            guard let context, !context.isEmpty, context.utf8.count <= 4_096 else { throw JimuReplayError(code: "action_context_required") }
            guard comparison == nil, [.pass, .rightSwipe, .note, .instant, .inspect, .hold].contains(choice) else {
                throw JimuReplayError(code: "invalid_feedback_choice")
            }
        } else {
            let allowed: [JimuFeedbackChoice] = comparison == nil ? [.approve, .reject] : [.left, .right, .tie, .neither]
            guard allowed.contains(choice), context == nil || context == "" else { throw JimuReplayError(code: "invalid_feedback_choice") }
        }
        guard comparison?.id != snapshot.id else { throw JimuReplayError(code: "same_observation_comparison") }
        return try databaseQueue.write { database in
            let current = try Self.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            guard current.revision == snapshot.revision else { throw JimuReplayError(code: "stale_presentation") }
            guard current.preferenceLabelsAllowed else { throw JimuReplayError(code: "adult_evidence_required") }
            guard !current.sourceImageBound else { throw JimuReplayError(code: "source_image_label_presentation_pending") }
            var other: JimuInspectorSnapshot?
            if let comparison {
                other = try Self.jimuSnapshot(id: comparison.id, policy: policy, database: database)
                guard other?.revision == comparison.revision else { throw JimuReplayError(code: "stale_presentation") }
                guard other?.preferenceLabelsAllowed == true else { throw JimuReplayError(code: "adult_evidence_required") }
                guard other?.sourceImageBound == false else { throw JimuReplayError(code: "source_image_label_presentation_pending") }
                guard other?.observation.platform == current.observation.platform,
                      other?.observation.accountID == current.observation.accountID else { throw JimuReplayError(code: "comparison_namespace_mismatch") }
            }
            let feedback = JimuFeedback(id: UUID().uuidString, scope: scope, choice: choice, basis: current.basis,
                comparison: other?.basis, actionContext: scope == .scarceAction ? context : nil,
                supersedesID: supersedesID, createdAt: now)
            try Self.insertJimuFeedback(feedback, database: database)
            return feedback
        }
    }

    internal static func insertJimuFeedback(_ feedback: JimuFeedback, database: Database) throws {
        if let supersedesID = feedback.supersedesID {
            guard let oldData = try Data.fetchOne(database, sql: "SELECT payload FROM preference_feedback WHERE id = ?", arguments: [supersedesID]),
                  let old = try? JimuInspectorCoding.decode(JimuFeedback.self, from: oldData),
                  old.basis.observationID == feedback.basis.observationID, old.scope == feedback.scope,
                  old.comparison?.observationID == feedback.comparison?.observationID,
                  try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM preference_feedback WHERE supersedes_id = ?", arguments: [supersedesID]) == 0 else {
                throw JimuReplayError(code: "feedback_supersession_conflict")
            }
        }
        try database.execute(sql: "INSERT INTO preference_feedback (id, observation_id, comparison_id, supersedes_id, payload) VALUES (?, ?, ?, ?, ?)",
            arguments: [feedback.id, feedback.basis.observationID, feedback.comparison?.observationID,
                feedback.supersedesID, try JimuInspectorCoding.encode(feedback)])
    }

    func jimuFeedback(observationID: String) throws -> [JimuFeedback] {
        try databaseQueue.read { database in
            try Data.fetchAll(database, sql: "SELECT payload FROM preference_feedback WHERE observation_id = ? OR comparison_id = ? ORDER BY sequence",
                arguments: [observationID, observationID]).map { try JimuInspectorCoding.decode(JimuFeedback.self, from: $0) }
        }
    }

    /// Explicit privacy deletion is separate from append-only correction; no hidden copy remains in another store.
    func deleteJimuObservation(id: String) throws {
        try databaseQueue.write { database in
            try removeJimuSourceMedia(database: database, observationID: id)
            try database.execute(sql: "DELETE FROM profile_observations WHERE id = ?", arguments: [id])
        }
    }

    private static func jimuStored(id: String, database: Database) throws -> JimuStoredObservation? {
        guard let row = try Row.fetchOne(database, sql: "SELECT * FROM profile_observations WHERE id = ?", arguments: [id]) else { return nil }
        let policyData: Data? = row["import_policy"]
        return JimuStoredObservation(id: row["id"], platform: row["platform"], accountID: row["account_id"], encounterID: row["encounter_id"],
            profileID: row["profile_id"], rawData: row["raw_data"], inputSHA256: row["input_sha256"], importedAt: row["imported_at"],
            importReport: try JimuInspectorCoding.decode(JimuReplayReport.self, from: row["import_report"]),
            importPolicy: try policyData.map { try JimuInspectorCoding.decode(JimuReplayPolicy.self, from: $0) })
    }

    static func jimuSnapshot(id: String, policy: JimuReplayPolicy?, database: Database) throws -> JimuInspectorSnapshot {
        guard let stored = try jimuStored(id: id, database: database) else { throw JimuReplayError(code: "observation_not_found") }
        let report = try JimuReplay.inspect(stored.rawData, policy: policy)
        let corrections = try Data.fetchAll(database, sql: "SELECT payload FROM observation_corrections WHERE observation_id = ? ORDER BY sequence", arguments: [id])
            .map { try JimuInspectorCoding.decode(JimuCorrection.self, from: $0) }
        return JimuInspectorSnapshot(observation: stored, report: report, corrections: corrections,
            basis: try JimuInspectorCoding.basis(observation: stored, corrections: corrections, policy: policy),
            sourceImageBound: try JimuSourceMediaSchema.record(id: id, database: database) != nil)
    }
}
