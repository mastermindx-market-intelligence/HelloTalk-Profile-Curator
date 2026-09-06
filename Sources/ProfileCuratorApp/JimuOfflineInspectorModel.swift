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
    @Published private(set) var sourceFrame: JimuSourceFrame?
    @Published private(set) var photoCrop: JimuPhotoCrop?
    @Published private(set) var photoMode = false
    @Published private(set) var photoLeft: JimuPhotoPresentation?
    @Published private(set) var photoRight: JimuPhotoPresentation?
    @Published private(set) var photoSubmissionID: String?
    @Published private(set) var photoProgress = ""
    private var shownProfileIDs = Set<String>()
    private var photoDeck: [String] = []
    private var photoIndex = 0
    private var photoPaired = false
    private var photoSupersedesID: String?
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
        snapshot = nil; comparison = nil; feedback = []; sourceFrame = nil; photoCrop = nil
        guard let id else { return }
        perform {
            let repository = try requiredRepository()
            let value = try repository.jimuSnapshot(id: id, policy: policy)
            let labels = try repository.jimuFeedback(observationID: id)
            snapshot = value; feedback = labels
            photoCrop = try repository.jimuPhotoCrops(observationID: id).last
            shownProfileIDs.insert(id)
            sourceFrame = try requiredMediaStore().jimuSourceFrame(snapshot: value, policy: policy)
            notice = "Stored observation loaded. Original evidence and \(value.corrections.count) correction(s) preserved."
        }
    }
    func compare(with id: String?) {
        comparison = nil
        guard let id, id != snapshot?.id else { return }
        perform { comparison = try requiredRepository().jimuSnapshot(id: id, policy: policy); shownProfileIDs.insert(id) }
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
            comparison = nil; sourceFrame = nil
            if let snapshot { sourceFrame = try requiredMediaStore().jimuSourceFrame(snapshot: snapshot, policy: policy) }
            photoCrop = try requiredRepository().jimuPhotoCrops(observationID: result.id).last
            shownProfileIDs.insert(result.id)
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
            photoLeft = nil; photoRight = nil; photoSubmissionID = nil
            photoSupersedesID = nil; photoDeck = []; photoIndex = 0
            photoProgress = "Policy changed. Exit and start a new calibration session."
            let selected = snapshot?.id
            snapshot = nil; comparison = nil; feedback = []; sourceFrame = nil
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
    func correct(fieldID: String, state: String, valueJSON: String, reason: String, valueIsText: Bool = false) {
        perform {
            guard let snapshot else { throw JimuReplayError(code: "observation_not_selected") }
            guard valueJSON.utf8.count <= 65_536 else { throw JimuReplayError(code: "correction_too_large") }
            let value: JimuJSON
            if state != "PRESENT" { value = .null }
            else if valueIsText { value = .string(valueJSON) }
            else { value = try JSONDecoder().decode(JimuJSON.self, from: Data(valueJSON.utf8)) }
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
    func importSourceFile(_ url: URL) {
        perform {
            guard let snapshot else { throw JimuReplayError(code: "observation_not_selected") }
            guard snapshot.preferenceLabelsAllowed else { throw JimuReplayError(code: "adult_evidence_required") }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try MediaStore.readJimuSourceFile(url)
            let media = try requiredMediaStore()
            _ = try media.bindJimuSourceFrame(data, snapshot: snapshot, policy: policy)
            let refreshed = try requiredRepository().jimuSnapshot(id: snapshot.id, policy: policy)
            self.snapshot = refreshed
            sourceFrame = try media.jimuSourceFrame(snapshot: refreshed, policy: policy)
            notice = "Source bytes verified and stored locally. Capture origin and photo-only calibration remain unverified."
        }
    }


    func savePhotoCrop(_ rect: JimuPhotoRect, confirmed: Bool) {
        perform {
            guard let snapshot else { throw JimuReplayError(code: "observation_not_selected") }
            photoCrop = try requiredMediaStore().saveJimuPhotoCrop(snapshot: snapshot, policy: policy,
                rect: rect, confirmedPhotoOnly: confirmed, expectedCropID: photoCrop?.id)
            notice = "Photo region saved. Human confirmation is recorded; no visual label or action was created."
        }
    }
    func beginPhotoCalibration(paired: Bool, observationIDs: [String]? = nil) {
        photoMode = true; photoLeft = nil; photoRight = nil; photoSubmissionID = nil
        photoSupersedesID = nil; photoIndex = 0; photoPaired = paired
        perform {
            let repository = try requiredRepository()
            if let observationIDs { photoDeck = observationIDs }
            else {
                photoDeck = try repository.jimuObservations(limit: 200)
                    .filter { try !repository.jimuPhotoCrops(observationID: $0.id).isEmpty }.map(\.id).shuffled()
            }
            guard Set(photoDeck).count == photoDeck.count else {
                photoDeck = []
                throw JimuReplayError(code: "photo_selection_conflict")
            }
        }
        if errorCode == nil { nextPhotoCalibration() }
    }
    func nextPhotoCalibration() {
        guard photoMode else { errorCode = "photo_session_required"; return }
        photoLeft = nil; photoRight = nil; photoSubmissionID = nil; photoSupersedesID = nil
        let needed = photoPaired ? 2 : 1
        guard photoIndex + needed <= photoDeck.count else {
            errorCode = nil; photoProgress = "No more prepared photos in this session."
            return
        }
        let ids = Array(photoDeck[photoIndex..<(photoIndex + needed)])
        photoIndex += needed
        photoProgress = "Photos \(photoIndex - needed + 1)–\(photoIndex) of \(photoDeck.count)"
        perform { try preparePhotoSelection(ids) }
    }
    private func preparePhotoSelection(_ ids: [String]) throws {
        let repository = try requiredRepository()
        let media = try requiredMediaStore()
        let views = try ids.map { id in
            try media.prepareJimuPhotoPresentation(snapshot: repository.jimuSnapshot(id: id, policy: policy),
                policy: policy, exposure: shownProfileIDs.contains(id) ? .profileShown : .notShownThisSession)
        }
        photoLeft = views.first; photoRight = views.count == 2 ? views[1] : nil
    }
    func recordPhotoLabel(_ choice: JimuFeedbackChoice) {
        perform {
            guard photoMode, let left = photoLeft else { throw JimuReplayError(code: "photo_session_required") }
            guard photoSubmissionID == nil else { throw JimuReplayError(code: "photo_judgment_already_recorded") }
            let label = try requiredMediaStore().recordJimuPhotoFeedback(presentation: left, policy: policy,
                choice: choice, comparison: photoRight, supersedesID: photoSupersedesID)
            photoSubmissionID = label.id
            notice = "Visual preference saved. No profile action was performed."
        }
    }
    func revisePhotoLabel() {
        guard photoMode, let left = photoLeft, let prior = photoSubmissionID else {
            errorCode = "photo_judgment_required"; return
        }
        let ids = [left.crop.observationID] + (photoRight.map { [$0.crop.observationID] } ?? [])
        photoLeft = nil; photoRight = nil; photoSubmissionID = nil
        photoSupersedesID = prior
        perform { try preparePhotoSelection(ids) }
    }
    func beginPhotoRevision(_ label: JimuFeedback) {
        guard label.scope == .visualOnly else { errorCode = "invalid_feedback_scope"; return }
        let ids = [label.basis.observationID] + (label.comparison.map { [$0.observationID] } ?? [])
        beginPhotoCalibration(paired: ids.count == 2, observationIDs: ids)
        if errorCode == nil { photoSupersedesID = label.id }
    }
    func stopPhotoCalibration() {
        photoMode = false; photoLeft = nil; photoRight = nil
        photoSubmissionID = nil; photoSupersedesID = nil; photoDeck = []
        let selected = snapshot?.id
        if let selected { select(selected) }
        else { errorCode = nil }
    }
    private func requiredMediaStore() throws -> MediaStore {
        let repository = try requiredRepository()
        let root = URL(fileURLWithPath: repository.databasePath).deletingLastPathComponent().appendingPathComponent("media")
        return try MediaStore(rootURL: root, repository: repository)
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
