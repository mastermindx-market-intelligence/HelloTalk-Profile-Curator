import AppKit
import Foundation
import ProfileCuratorCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case all = "All"
    case primary = "Primary"
    case secondary = "Secondary"
    case highPrioritySecondary = "High-priority Secondary"
    case shortlist = "Shortlist"
    case contacted = "Contacted"
    case rejected = "Rejected"

    var id: String { rawValue }
}

struct DashboardProfile: Identifiable {
    let profile: ProfileRecord
    let mediaCount: Int
    let facePhotoCount: Int
    let momentPhotoCount: Int
    let previewPath: String?

    var id: String { profile.id }
}

@MainActor
final class ReviewDashboardViewModel: ObservableObject {
    @Published var records: [DashboardProfile] = []
    @Published var selectedProfileID: String?
    @Published var selectedMedia: [MediaRecord] = []
    @Published var selectedAnalysisRuns: [AnalysisRunRecord] = []
    @Published var search = ""
    @Published var section: DashboardSection = .all
    @Published var sort: ProfileSort = .recentlyUpdated
    @Published var pageSize = 20
    @Published var page = 0
    @Published var minimumAgeText = ""
    @Published var maximumAgeText = ""
    @Published var city = ""
    @Published var minimumFaceScoreText = ""
    @Published var minimumLifestyleScoreText = ""
    @Published var minimumOverallScoreText = ""
    @Published var minimumConfidenceText = ""
    @Published var usableFaceRequired = false
    @Published var totalCount = 0
    @Published var statusMessage = "Loading local collection…"
    @Published var notesDraft = ""
    @Published var errorMessage: String?

    let repository: ProfileRepository?
    let dataRoot: URL?

    init(repository: ProfileRepository? = nil) {
        do {
            let resolved = try repository ?? ProfileRepository.defaultRepository()
            self.repository = resolved
            dataRoot = URL(fileURLWithPath: resolved.databasePath).deletingLastPathComponent()
            refresh()
        } catch {
            self.repository = nil
            dataRoot = nil
            statusMessage = "Local database unavailable"
            errorMessage = error.localizedDescription
        }
    }

    var selected: DashboardProfile? {
        records.first { $0.id == selectedProfileID }
    }

    var totalPages: Int { max(1, Int(ceil(Double(totalCount) / Double(pageSize)))) }
    var canGoBack: Bool { page > 0 }
    var canGoForward: Bool { page + 1 < totalPages }

    func refresh(resetPage: Bool = false) {
        guard let repository else { return }
        if resetPage { page = 0 }
        do {
            let result = try repository.page(makeQuery())
            records = try result.records.map { profile in
                let media = try repository.media(profileID: profile.id, retainedOnly: true)
                let preview = media.first(where: { $0.typedKind == .pfp || $0.typedKind == .faceCrop }) ?? media.first
                return DashboardProfile(
                    profile: profile,
                    mediaCount: media.count,
                    facePhotoCount: media.filter(\.usableFace).count,
                    momentPhotoCount: media.filter { $0.typedKind == .moment }.count,
                    previewPath: preview?.filePath
                )
            }
            totalCount = result.totalCount
            statusMessage = totalCount == 0 ? "No collected profiles yet" : "\(totalCount) matching profile\(totalCount == 1 ? "" : "s")"
            if let selectedProfileID, !records.contains(where: { $0.id == selectedProfileID }) {
                self.selectedProfileID = nil
                selectedMedia = []
                selectedAnalysisRuns = []
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ item: DashboardProfile) {
        selectedProfileID = item.id
        notesDraft = item.profile.notes
        do {
            selectedMedia = try repository?.media(profileID: item.id, retainedOnly: true) ?? []
            selectedAnalysisRuns = try repository?.analysisRuns(profileID: item.id) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setStatus(_ status: ProfileStatus) {
        guard let id = selectedProfileID else { return }
        do {
            try repository?.updateStatus(id: id, status: status)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func saveNotes() {
        guard let id = selectedProfileID else { return }
        do {
            try repository?.updateNotes(id: id, notes: notesDraft)
            refresh()
            statusMessage = "Notes saved locally"
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteSelectedMedia() {
        guard let id = selectedProfileID else { return }
        do {
            try repository?.purgeMedia(profileID: id)
            selectedMedia = []
            selectedAnalysisRuns = []
            refresh()
            statusMessage = "Selected profile media deleted; profile record retained"
        } catch { errorMessage = error.localizedDescription }
    }

    func nextPage() { guard canGoForward else { return }; page += 1; refresh() }
    func previousPage() { guard canGoBack else { return }; page -= 1; refresh() }

    func revealDataFolder() {
        guard let dataRoot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dataRoot])
    }

    func export(format: ExportFormat) {
        guard let repository, let dataRoot else { return }
        do {
            var query = makeQuery()
            query.page = 0
            query.pageSize = 100
            var profiles: [ProfileRecord] = []
            while true {
                let result = try repository.page(query)
                profiles += result.records
                if profiles.count >= result.totalCount { break }
                query.page += 1
            }
            let exports = dataRoot.appendingPathComponent("exports", isDirectory: true)
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = exports.appendingPathComponent("profiles-\(stamp).\(format.rawValue)")
            switch format {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(profiles).write(to: url, options: .atomic)
            case .csv:
                let header = "username,display_name,age,mbti,group,city,face_score,lifestyle_score,overall_score,confidence,status,first_seen,last_seen\n"
                let rows = profiles.map(Self.csvRow).joined(separator: "\n")
                try Data((header + rows).utf8).write(to: url, options: .atomic)
            }
            statusMessage = "Exported \(profiles.count) profiles to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteAllData() {
        do {
            try repository?.deleteAll()
            selectedProfileID = nil
            selectedMedia = []
            refresh(resetPage: true)
            statusMessage = "All collected profiles and media deleted"
        } catch { errorMessage = error.localizedDescription }
    }

    private func makeQuery() -> ProfileQuery {
        var groups = Set<MBTIGroup>()
        var statuses = Set<ProfileStatus>()
        var highPriority = false
        switch section {
        case .primary: groups = [.primary]
        case .secondary: groups = [.secondary]
        case .highPrioritySecondary: highPriority = true
        case .shortlist: statuses = [.shortlisted]
        case .contacted: statuses = [.contacted]
        case .rejected: statuses = [.rejected, .rejectedNoFace]
        case .all: break
        }
        return ProfileQuery(
            search: search,
            groups: groups,
            statuses: statuses,
            minimumAge: Int(minimumAgeText),
            maximumAge: Int(maximumAgeText),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : city.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryHighPriorityOnly: highPriority,
            minimumFaceScore: Double(minimumFaceScoreText),
            minimumLifestyleScore: Double(minimumLifestyleScoreText),
            minimumOverallScore: Double(minimumOverallScoreText),
            minimumConfidence: Double(minimumConfidenceText).map { min(1, max(0, $0 > 1 ? $0 / 100 : $0)) },
            usableFaceRequired: usableFaceRequired,
            sort: sort,
            page: page,
            pageSize: pageSize
        )
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") ? "\"\(escaped)\"" : escaped
    }

    private static func csvRow(_ profile: ProfileRecord) -> String {
        let age = profile.age.map { String($0) } ?? ""
        let face = profile.faceScore.map { String($0) } ?? ""
        let lifestyle = profile.lifestyleScore.map { String($0) } ?? ""
        let overall = profile.overallScore.map { String($0) } ?? ""
        let fields: [String] = [
            profile.usernameNormalized,
            profile.displayName ?? "",
            age,
            profile.mbti ?? "",
            profile.mbtiGroup ?? "",
            profile.cityNormalized ?? "",
            face,
            lifestyle,
            overall,
            String(profile.analysisConfidence),
            profile.status,
            profile.firstSeenAt.ISO8601Format(),
            profile.lastSeenAt.ISO8601Format()
        ]
        return fields.map(csvEscape).joined(separator: ",")
    }
}

enum ExportFormat: String { case csv, json }

@MainActor
final class VLMSettingsViewModel: ObservableObject {
    @Published var endpoint = ""
    @Published var model = "qwen3.5:9b"
    @Published var enforceNoFaceForPrimary = true
    @Published var status = "Not configured — collection remains fully offline"
    @Published var isTesting = false

    private let store: VLMConfigurationStore?

    init() {
        store = try? VLMConfigurationStore.defaultStore()
        if let configuration = try? store?.load() {
            endpoint = configuration.baseURL?.absoluteString ?? ""
            model = configuration.model
            enforceNoFaceForPrimary = configuration.enforceNoFaceForPrimary
            if configuration.baseURL != nil { status = "Saved locally; connection not tested" }
        }
    }

    func save() -> VLMConfiguration? {
        do {
            let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let configuration = VLMConfiguration(
                baseURL: trimmed.isEmpty ? nil : URL(string: trimmed),
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                enforceNoFaceForPrimary: enforceNoFaceForPrimary
            )
            try store?.save(configuration)
            status = configuration.baseURL == nil ? "Offline mode saved" : "Qwen settings saved locally"
            return configuration
        } catch {
            status = error.localizedDescription
            return nil
        }
    }

    func saveCollectionSettings() {
        guard save() != nil else { return }
        status = enforceNoFaceForPrimary
            ? "Primary and Secondary no-face rejection saved"
            : "Primary no-face rejection disabled · Secondary remains mandatory"
    }

    func testConnection() {
        guard let configuration = save(), configuration.baseURL != nil else { return }
        isTesting = true
        status = "Testing private endpoint…"
        Task {
            do {
                let health = try await OllamaVLMClient(configuration: configuration).health()
                status = health.configuredModelAvailable
                    ? "Connected · \(configuration.model) available"
                    : "Connected · model missing; available: \(health.availableModels.joined(separator: ", "))"
            } catch {
                status = "Offline · queued analysis will wait · \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
