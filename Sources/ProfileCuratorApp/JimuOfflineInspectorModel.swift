import Foundation
import Combine
import ProfileCuratorCore

@MainActor
final class JimuOfflineInspectorModel: ObservableObject {
    @Published private(set) var observations: [JimuObservationSummary] = []
    @Published private(set) var snapshot: JimuInspectorSnapshot?
    @Published private(set) var comparison: JimuInspectorSnapshot?
    @Published private(set) var feedback: [JimuFeedback] = []
    @Published private(set) var policy: JimuReplayPolicy?
    @Published private(set) var errorCode: String?
    @Published private(set) var notice = "Import an authorized offline observation to begin."
    @Published private(set) var offset = 0
    private let repository: ProfileRepository?
    private let policyURL: URL?

    init(repository: ProfileRepository? = nil) {
        let resolved: ProfileRepository
        do { resolved = try repository ?? ProfileRepository.defaultRepository() }
        catch {
            self.repository = nil; self.policyURL = nil
            errorCode = "database_unavailable"
            return
        }
        self.repository = resolved
        let url = URL(fileURLWithPath: resolved.databasePath).deletingLastPathComponent().appendingPathComponent("jimu-policy.json")
        self.policyURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            do { policy = try Self.decodePolicy(Self.boundedRead(url, limit: 65_536)) }
            catch { errorCode = "saved_policy_invalid" }
        }
        do { observations = try resolved.jimuObservations() }
        catch { errorCode = "database_read_failed" }
    }

    func select(_ id: String?) {
        snapshot = nil; comparison = nil; feedback = []
        guard let id else { return }
        perform {
            let repository = try requiredRepository()
            let value = try repository.jimuSnapshot(id: id, policy: policy)
            let labels = try repository.jimuFeedback(observationID: id)
            snapshot = value; feedback = labels
        }
    }
    func compare(with id: String?) {
        comparison = nil
        guard let id, id != snapshot?.id else { return }
        perform { comparison = try requiredRepository().jimuSnapshot(id: id, policy: policy) }
    }
    func reload() {
        perform { observations = try requiredRepository().jimuObservations(offset: offset) }
        let selected = snapshot?.id
        if let selected { select(selected) }
    }
    func page(_ delta: Int) {
        offset = max(0, offset + delta * 100)
        select(nil)
        reload()
    }
    func importObservation(_ data: Data) {
        perform {
            let result = try requiredRepository().importJimuObservation(data, policy: policy)
            offset = 0
            observations = try requiredRepository().jimuObservations()
            snapshot = try requiredRepository().jimuSnapshot(id: result.id, policy: policy)
            feedback = try requiredRepository().jimuFeedback(observationID: result.id)
            comparison = nil
            notice = "Observation stored. Original bytes are immutable; no actions were enabled."
        }
    }
    func importFile(_ url: URL) {
        perform {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Self.boundedRead(url, limit: JimuReplay.maximumInputBytes)
            // Admission/validation occurs before profile contents enter the view.
            _ = try JimuReplay.inspect(data, policy: policy)
            importObservation(data)
        }
    }
    func loadPolicy(_ data: Data) {
        perform {
            let candidate = try Self.decodePolicy(data)
            guard let policyURL else { throw JimuReplayError(code: "database_unavailable") }
            let encoded = try JSONEncoder().encode(candidate)
            try encoded.write(to: policyURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: policyURL.path)
            policy = candidate
            let selected = snapshot?.id
            snapshot = nil; comparison = nil; feedback = []
            if let selected { select(selected) }
            notice = "Local inspection policy loaded. Live engagement remains disabled."
        }
    }
    func loadPolicyFile(_ url: URL) {
        perform {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            loadPolicy(try Self.boundedRead(url, limit: 65_536))
        }
    }
    func correct(fieldID: String, state: String, valueJSON: String, reason: String) {
        perform {
            guard let snapshot else { throw JimuReplayError(code: "observation_not_selected") }
            guard valueJSON.utf8.count <= 65_536 else { throw JimuReplayError(code: "correction_too_large") }
            let value: JimuJSON = state == "PRESENT" ? try JSONDecoder().decode(JimuJSON.self, from: Data(valueJSON.utf8)) : .null
            _ = try requiredRepository().appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: fieldID, state: state, value: value, reason: reason)
            select(snapshot.id)
            notice = "Correction appended. Original evidence and earlier labels have not changed."
        }
    }
    func label(_ choice: JimuFeedbackChoice, scope: JimuFeedbackScope, paired: Bool = false,
        context: String? = nil, supersedesID: String? = nil) {
        perform {
            guard let snapshot else { throw JimuReplayError(code: "observation_not_selected") }
            if paired && comparison == nil { throw JimuReplayError(code: "comparison_not_selected") }
            _ = try requiredRepository().recordJimuFeedback(snapshot: snapshot, policy: policy, scope: scope,
                choice: choice, comparison: paired ? comparison : nil, actionContext: context, supersedesID: supersedesID)
            feedback = try requiredRepository().jimuFeedback(observationID: snapshot.id)
            notice = "Manual feedback saved with the exact evidence version shown. No action was performed."
        }
    }
    func deleteSelected() {
        perform {
            guard let snapshot else { return }
            try requiredRepository().deleteJimuObservation(id: snapshot.id)
            select(nil)
            observations = try requiredRepository().jimuObservations(offset: offset)
            notice = "Observation and its correction/comparison feedback were deleted."
        }
    }
    private func requiredRepository() throws -> ProfileRepository {
        guard let repository else { throw JimuReplayError(code: "database_unavailable") }
        return repository
    }
    private func perform(_ operation: () throws -> Void) {
        errorCode = nil
        do { try operation() }
        catch { errorCode = (error as? JimuReplayError)?.code ?? "offline_operation_failed" }
    }
    private static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        guard url.isFileURL else { throw JimuReplayError(code: "local_file_required") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw JimuReplayError(code: "input_too_large") }
        return data
    }
    private static func decodePolicy(_ data: Data) throws -> JimuReplayPolicy {
        guard data.count <= 65_536 else { throw JimuReplayError(code: "policy_too_large") }
        let value = try JSONDecoder().decode(JimuReplayPolicy.self, from: data)
        guard !value.policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.minimumAge >= 18, value.maximumAge >= value.minimumAge, value.maximumAge <= 130,
              value.allowedRightsScopeIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw JimuReplayError(code: "invalid_policy")
        }
        return value
    }
}
