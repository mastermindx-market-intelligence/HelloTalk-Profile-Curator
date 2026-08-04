import Foundation
@preconcurrency import GRDB

public enum ProfileStatus: String, Codable, CaseIterable, Sendable {
    case new
    case analyzing
    case review
    case shortlisted
    case rejected
    case contacted
    case rejectedNoFace = "rejected_no_face"

    public var isManualDecision: Bool {
        self == .shortlisted || self == .rejected || self == .contacted
    }
}

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case profileTop = "profile_top"
    case pfp
    case moment
    case faceCrop = "face_crop"
    case diagnostic
}

public enum AnalysisType: String, Codable, CaseIterable, Sendable {
    case faceVerification = "face_verification"
    case visualAppeal = "visual_appeal"
    case tattooDetection = "tattoo_detection"
    case lifestyle
}

public struct ProfileRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "profiles"

    public var id: String
    public var usernameRaw: String?
    public var usernameNormalized: String
    public var displayName: String?
    public var age: Int?
    public var gender: String?
    public var mbti: String?
    public var mbtiGroup: String?
    public var locationRaw: String?
    public var cityNormalized: String?
    public var provinceNormalized: String?
    public var countryNormalized: String?
    public var locationTier: Int?
    public var locationScore: Int?
    public var bio: String?
    public var hobbiesJSON: String
    public var education: String?
    public var occupation: String?
    public var hobbyScore: Double?
    public var educationScore: Double?
    public var occupationScore: Double?
    public var profileSignalsScore: Double?
    public var faceScore: Double?
    public var lifestyleScore: Double?
    public var hasVisibleTattoo: Bool
    public var profileCompletenessScore: Double
    public var overallScore: Double?
    public var analysisConfidence: Double
    public var status: String
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var lastAnalyzedAt: Date?
    public var visitCount: Int
    public var rejectionReason: String?
    public var notes: String

    public var typedStatus: ProfileStatus { ProfileStatus(rawValue: status) ?? .new }
    public var typedMBTI: MBTIType? { mbti.flatMap(MBTIType.init(rawValue:)) }
    public var typedGroup: MBTIGroup? { mbtiGroup.flatMap(MBTIGroup.init(rawValue:)) }
    public var isPreferredLocationNoMBTI: Bool {
        mbti == nil && (locationScore ?? 0) >= ProfileEligibilityPolicy.minimumNoMBTILocationScore
    }
    public var isLocationMissing: Bool { (locationScore ?? 10) <= 10 }
    public var isUnknownLocationNoMBTI: Bool { mbti == nil && isLocationMissing }
    public var hobbies: [String] {
        guard let data = hobbiesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case usernameRaw = "username_raw"
        case usernameNormalized = "username_normalized"
        case displayName = "display_name"
        case age, gender, mbti
        case mbtiGroup = "mbti_group"
        case locationRaw = "location_raw"
        case cityNormalized = "city_normalized"
        case provinceNormalized = "province_normalized"
        case countryNormalized = "country_normalized"
        case locationTier = "location_tier"
        case locationScore = "location_score"
        case bio
        case hobbiesJSON = "hobbies_json"
        case education, occupation
        case hobbyScore = "hobby_score"
        case educationScore = "education_score"
        case occupationScore = "occupation_score"
        case profileSignalsScore = "profile_signals_score"
        case faceScore = "face_score"
        case lifestyleScore = "lifestyle_score"
        case hasVisibleTattoo = "has_visible_tattoo"
        case profileCompletenessScore = "profile_completeness_score"
        case overallScore = "overall_score"
        case analysisConfidence = "analysis_confidence"
        case status
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
        case lastAnalyzedAt = "last_analyzed_at"
        case visitCount = "visit_count"
        case rejectionReason = "rejection_reason"
        case notes
    }
}

public struct ProfileDraft: Hashable, Sendable {
    public var usernameRaw: String
    public var displayName: String?
    public var age: Int?
    public var gender: GenderBadgeHint
    public var mbti: MBTIType?
    public var location: NormalizedLocation?
    /// When true, the caller has completed a badge-only location observation.
    /// A nil location then means "verified no badge" and must clear stale OCR
    /// data instead of inheriting a prior value.
    public var replaceLocation: Bool
    public var bio: String?
    public var hobbies: [String]
    public var education: String?
    public var occupation: String?
    public var profileCompletenessScore: Double
    public var status: ProfileStatus

    public init(
        usernameRaw: String,
        displayName: String? = nil,
        age: Int? = nil,
        gender: GenderBadgeHint = .unknown,
        mbti: MBTIType? = nil,
        location: NormalizedLocation? = nil,
        replaceLocation: Bool = false,
        bio: String? = nil,
        hobbies: [String] = [],
        education: String? = nil,
        occupation: String? = nil,
        profileCompletenessScore: Double = 0,
        status: ProfileStatus = .new
    ) {
        self.usernameRaw = usernameRaw
        self.displayName = displayName
        self.age = age
        self.gender = gender
        self.mbti = mbti
        self.location = location
        self.replaceLocation = replaceLocation
        self.bio = bio
        self.hobbies = hobbies
        self.education = education
        self.occupation = occupation
        self.profileCompletenessScore = min(100, max(0, profileCompletenessScore))
        self.status = status
    }

    public var normalizedUsername: String {
        usernameRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct MediaRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "media"

    public var id: String
    public var profileID: String
    public var kind: String
    public var filePath: String
    public var perceptualHash: String
    public var sourceSequence: Int
    public var faceCount: Int
    public var largestFaceRatio: Double
    public var faceCaptureQuality: Double?
    public var usableFace: Bool
    public var retained: Bool
    public var createdAt: Date

    public var typedKind: MediaKind { MediaKind(rawValue: kind) ?? .diagnostic }

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case kind
        case filePath = "file_path"
        case perceptualHash = "perceptual_hash"
        case sourceSequence = "source_sequence"
        case faceCount = "face_count"
        case largestFaceRatio = "largest_face_ratio"
        case faceCaptureQuality = "face_capture_quality"
        case usableFace = "usable_face"
        case retained
        case createdAt = "created_at"
    }
}

public struct AnalysisRunRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    public static let databaseTableName = "analysis_runs"

    public var id: String
    public var profileID: String
    public var analysisType: String
    public var modelName: String
    public var promptVersion: String
    public var requestJSON: String
    public var responseJSON: String?
    public var startedAt: Date
    public var completedAt: Date?
    public var success: Bool
    public var error: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case analysisType = "analysis_type"
        case modelName = "model_name"
        case promptVersion = "prompt_version"
        case requestJSON = "request_json"
        case responseJSON = "response_json"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case success, error
    }
}

public enum ProfileSort: String, CaseIterable, Sendable {
    case overallScore
    case faceScore
    case lifestyleScore
    case profileSignalsScore
    case locationScore
    case confidenceAdjustedScore
    case newest
    case recentlyUpdated
    case username

    fileprivate var sql: String {
        switch self {
        case .overallScore: "overall_score DESC, last_seen_at DESC"
        case .faceScore: "face_score DESC, last_seen_at DESC"
        case .lifestyleScore: "lifestyle_score DESC, last_seen_at DESC"
        case .profileSignalsScore: "profile_signals_score DESC, last_seen_at DESC"
        case .locationScore: "location_score DESC, last_seen_at DESC"
        case .confidenceAdjustedScore:
            "(COALESCE(overall_score, 0) * (0.75 + 0.25 * analysis_confidence)) DESC, last_seen_at DESC"
        case .newest: "first_seen_at DESC"
        case .recentlyUpdated: "last_seen_at DESC"
        case .username: "username_normalized ASC"
        }
    }
}

public struct ProfileQuery: Hashable, Sendable {
    public var search: String
    public var mbti: Set<MBTIType>
    public var groups: Set<MBTIGroup>
    public var statuses: Set<ProfileStatus>
    public var minimumAge: Int?
    public var maximumAge: Int?
    public var city: String?
    public var secondaryHighPriorityOnly: Bool
    public var preferredLocationNoMBTIOnly: Bool
    public var missingLocationOnly: Bool
    public var minimumFaceScore: Double?
    public var minimumLifestyleScore: Double?
    public var minimumOverallScore: Double?
    public var minimumConfidence: Double?
    public var usableFaceRequired: Bool
    public var sort: ProfileSort
    public var page: Int
    public var pageSize: Int

    public init(
        search: String = "",
        mbti: Set<MBTIType> = [],
        groups: Set<MBTIGroup> = [],
        statuses: Set<ProfileStatus> = [],
        minimumAge: Int? = nil,
        maximumAge: Int? = nil,
        city: String? = nil,
        secondaryHighPriorityOnly: Bool = false,
        preferredLocationNoMBTIOnly: Bool = false,
        missingLocationOnly: Bool = false,
        minimumFaceScore: Double? = nil,
        minimumLifestyleScore: Double? = nil,
        minimumOverallScore: Double? = nil,
        minimumConfidence: Double? = nil,
        usableFaceRequired: Bool = false,
        sort: ProfileSort = .recentlyUpdated,
        page: Int = 0,
        pageSize: Int = 20
    ) {
        self.search = search
        self.mbti = mbti
        self.groups = groups
        self.statuses = statuses
        self.minimumAge = minimumAge
        self.maximumAge = maximumAge
        self.city = city
        self.secondaryHighPriorityOnly = secondaryHighPriorityOnly
        self.preferredLocationNoMBTIOnly = preferredLocationNoMBTIOnly
        self.missingLocationOnly = missingLocationOnly
        self.minimumFaceScore = minimumFaceScore
        self.minimumLifestyleScore = minimumLifestyleScore
        self.minimumOverallScore = minimumOverallScore
        self.minimumConfidence = minimumConfidence
        self.usableFaceRequired = usableFaceRequired
        self.sort = sort
        self.page = max(0, page)
        self.pageSize = [20, 50, 100].contains(pageSize) ? pageSize : 20
    }
}

public struct ProfilePage: Sendable {
    public let records: [ProfileRecord]
    public let totalCount: Int
    public let page: Int
    public let pageSize: Int
}

public final class ProfileRepository: @unchecked Sendable {
    private static let defaultRepositoryLock = NSLock()

    public let databasePath: String
    private let databaseQueue: DatabaseQueue

    public init(databasePath: String) throws {
        self.databasePath = databasePath
        databaseQueue = try DatabaseQueue(path: databasePath)
        try Self.migrator.migrate(databaseQueue)
    }

    public static func defaultDataDirectory(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("ProfileCurator", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for child in ["media", "diagnostics", "exports"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(child, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    public static func defaultRepository(fileManager: FileManager = .default) throws -> ProfileRepository {
        // Inspector and dashboard models are created independently at launch.
        // Serialize their first-open migrations so both cannot race for the
        // same SQLite schema lock when a new app version adds a migration.
        defaultRepositoryLock.lock()
        defer { defaultRepositoryLock.unlock() }
        let root = try defaultDataDirectory(fileManager: fileManager)
        return try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
    }

    @discardableResult
    public func upsert(_ draft: ProfileDraft, now: Date = Date()) throws -> ProfileRecord {
        guard !draft.normalizedUsername.isEmpty else {
            throw RepositoryError.emptyUsername
        }
        return try databaseQueue.write { database in
            let existing = try ProfileRecord.fetchOne(
                database,
                sql: "SELECT * FROM profiles WHERE username_normalized = ?",
                arguments: [draft.normalizedUsername]
            )
            let mergedHobbies = Self.mergedHobbies(existing?.hobbies ?? [], draft.hobbies)
            let mergedBio = Self.longerText(existing?.bio, draft.bio)
            let mergedEducation = Self.longerText(existing?.education, draft.education)
            let mergedOccupation = Self.longerText(existing?.occupation, draft.occupation)
            let signalScores = ProfileSignalScorer().score(
                hobbies: mergedHobbies,
                education: mergedEducation,
                occupation: mergedOccupation
            )
            let record = ProfileRecord(
                id: existing?.id ?? UUID().uuidString,
                usernameRaw: draft.usernameRaw,
                usernameNormalized: draft.normalizedUsername,
                displayName: draft.displayName ?? existing?.displayName,
                age: draft.age ?? existing?.age,
                gender: draft.gender == .unknown ? existing?.gender : draft.gender.rawValue,
                mbti: draft.mbti?.rawValue ?? existing?.mbti,
                mbtiGroup: draft.mbti?.group?.rawValue ?? existing?.mbtiGroup,
                locationRaw: draft.replaceLocation ? draft.location?.rawText : (draft.location?.rawText ?? existing?.locationRaw),
                cityNormalized: draft.replaceLocation ? draft.location?.city : (draft.location?.city ?? existing?.cityNormalized),
                provinceNormalized: draft.replaceLocation ? draft.location?.province : (draft.location?.province ?? existing?.provinceNormalized),
                countryNormalized: draft.replaceLocation ? draft.location?.country : (draft.location?.country ?? existing?.countryNormalized),
                locationTier: draft.replaceLocation ? draft.location?.tier : (draft.location?.tier ?? existing?.locationTier),
                locationScore: draft.replaceLocation ? draft.location?.score : (draft.location?.score ?? existing?.locationScore),
                bio: mergedBio,
                hobbiesJSON: Self.encodeHobbies(mergedHobbies),
                education: mergedEducation,
                occupation: mergedOccupation,
                hobbyScore: signalScores.hobbies,
                educationScore: signalScores.education,
                occupationScore: signalScores.occupation,
                profileSignalsScore: signalScores.combined,
                faceScore: existing?.faceScore,
                lifestyleScore: existing?.lifestyleScore,
                hasVisibleTattoo: existing?.hasVisibleTattoo ?? false,
                profileCompletenessScore: max(draft.profileCompletenessScore, existing?.profileCompletenessScore ?? 0),
                overallScore: existing?.overallScore,
                analysisConfidence: existing?.analysisConfidence ?? 0,
                status: existing?.typedStatus.isManualDecision == true ? existing!.status : draft.status.rawValue,
                firstSeenAt: existing?.firstSeenAt ?? now,
                lastSeenAt: now,
                lastAnalyzedAt: existing?.lastAnalyzedAt,
                visitCount: (existing?.visitCount ?? 0) + 1,
                rejectionReason: existing?.rejectionReason,
                notes: existing?.notes ?? ""
            )
            if existing == nil { try record.insert(database) } else { try record.update(database) }
            return record
        }
    }

    private static func mergedHobbies(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        return (existing + incoming).filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()).inserted
        }
    }

    private static func encodeHobbies(_ hobbies: [String]) -> String {
        guard let data = try? JSONEncoder().encode(hobbies) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func longerText(_ existing: String?, _ incoming: String?) -> String? {
        let oldValue = existing?.nilIfBlank
        let newValue = incoming?.nilIfBlank
        guard let newValue else { return oldValue }
        guard let oldValue else { return newValue }
        return newValue.count >= oldValue.count ? newValue : oldValue
    }

    public func profile(id: String) throws -> ProfileRecord? {
        try databaseQueue.read { try ProfileRecord.fetchOne($0, key: id) }
    }

    public func profile(username: String) throws -> ProfileRecord? {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try databaseQueue.read {
            try ProfileRecord.fetchOne(
                $0,
                sql: "SELECT * FROM profiles WHERE username_normalized = ?",
                arguments: [normalized]
            )
        }
    }

    public func page(_ query: ProfileQuery) throws -> ProfilePage {
        let parts = Self.queryParts(query)
        return try databaseQueue.read { database in
            let total = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM profiles \(parts.whereSQL)",
                arguments: parts.arguments
            ) ?? 0
            let records = try ProfileRecord.fetchAll(
                database,
                sql: "SELECT * FROM profiles \(parts.whereSQL) ORDER BY \(query.sort.sql) LIMIT ? OFFSET ?",
                arguments: parts.arguments + [query.pageSize, query.page * query.pageSize]
            )
            return ProfilePage(records: records, totalCount: total, page: query.page, pageSize: query.pageSize)
        }
    }

    public func updateStatus(id: String, status: ProfileStatus, reason: String? = nil) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE profiles SET status = ?, rejection_reason = ?, last_seen_at = ? WHERE id = ?",
                arguments: [status.rawValue, reason, Date(), id]
            )
        }
    }

    public func updateNotes(id: String, notes: String) throws {
        try databaseQueue.write {
            try $0.execute(sql: "UPDATE profiles SET notes = ? WHERE id = ?", arguments: [notes, id])
        }
    }

    public func updateScores(
        id: String,
        face: Double?,
        lifestyle: Double?,
        overall: Double?,
        confidence: Double,
        hasVisibleTattoo: Bool? = nil,
        analyzedAt: Date = Date()
    ) throws {
        try databaseQueue.write {
            try $0.execute(
                sql: "UPDATE profiles SET face_score = ?, lifestyle_score = ?, overall_score = ?, analysis_confidence = ?, has_visible_tattoo = COALESCE(?, has_visible_tattoo), last_analyzed_at = ?, status = CASE WHEN status IN ('shortlisted','rejected','contacted') THEN status ELSE 'review' END WHERE id = ?",
                arguments: [face, lifestyle, overall, min(1, max(0, confidence)), hasVisibleTattoo, analyzedAt, id]
            )
        }
    }

    @discardableResult
    public func insertMedia(_ record: MediaRecord) throws -> Bool {
        try databaseQueue.write { database in
            let duplicate = try Int.fetchOne(
                database,
                sql: "SELECT 1 FROM media WHERE profile_id = ? AND perceptual_hash = ? LIMIT 1",
                arguments: [record.profileID, record.perceptualHash]
            ) != nil
            guard !duplicate else { return false }
            try record.insert(database)
            return true
        }
    }

    public func media(profileID: String, retainedOnly: Bool = false) throws -> [MediaRecord] {
        try databaseQueue.read { database in
            let suffix = retainedOnly ? " AND retained = 1" : ""
            return try MediaRecord.fetchAll(
                database,
                sql: "SELECT * FROM media WHERE profile_id = ?\(suffix) ORDER BY source_sequence, created_at",
                arguments: [profileID]
            )
        }
    }

    public func setRetainedMedia(profileID: String, mediaIDs: Set<String>) throws {
        try databaseQueue.write { database in
            let records = try MediaRecord.fetchAll(
                database,
                sql: "SELECT * FROM media WHERE profile_id = ? AND kind IN (?, ?)",
                arguments: [profileID, MediaKind.pfp.rawValue, MediaKind.moment.rawValue]
            )
            for record in records {
                try database.execute(
                    sql: "UPDATE media SET retained = ? WHERE id = ?",
                    arguments: [mediaIDs.contains(record.id), record.id]
                )
            }
        }
    }

    public func saveAnalysisRun(_ record: AnalysisRunRecord) throws {
        try databaseQueue.write { try record.save($0) }
    }

    public func analysisRuns(profileID: String) throws -> [AnalysisRunRecord] {
        try databaseQueue.read {
            try AnalysisRunRecord.fetchAll(
                $0,
                sql: "SELECT * FROM analysis_runs WHERE profile_id = ? ORDER BY started_at DESC",
                arguments: [profileID]
            )
        }
    }

    public func pendingAnalysisRuns(limit: Int = 20) throws -> [AnalysisRunRecord] {
        try databaseQueue.read {
            try AnalysisRunRecord.fetchAll(
                $0,
                sql: "SELECT * FROM analysis_runs WHERE success = 0 AND completed_at IS NULL ORDER BY started_at LIMIT ?",
                arguments: [max(1, limit)]
            )
        }
    }

    @discardableResult
    public func enqueueAnalysis(
        profileID: String,
        type: AnalysisType,
        modelName: String,
        promptVersion: String,
        mediaPaths: [String],
        now: Date = Date()
    ) throws -> AnalysisJobRecord {
        let record = AnalysisJobRecord(
            id: UUID().uuidString,
            profileID: profileID,
            analysisType: type,
            modelName: modelName,
            promptVersion: promptVersion,
            mediaPaths: mediaPaths,
            state: .pending,
            attemptCount: 0,
            nextAttemptAt: nil,
            lastError: nil,
            createdAt: now,
            updatedAt: now
        )
        try databaseQueue.write { try record.insert($0) }
        return record
    }

    public func nextAnalysisJob(now: Date = Date()) throws -> AnalysisJobRecord? {
        try databaseQueue.read {
            try AnalysisJobRecord.fetchOne(
                $0,
                sql: "SELECT * FROM analysis_jobs WHERE state = 'pending' OR (state = 'retry_waiting' AND next_attempt_at <= ?) ORDER BY created_at LIMIT 1",
                arguments: [now]
            )
        }
    }

    public func updateAnalysisJob(
        id: String,
        state: AnalysisJobState,
        attemptCount: Int,
        nextAttemptAt: Date?,
        error: String?,
        now: Date = Date()
    ) throws {
        try databaseQueue.write {
            try $0.execute(
                sql: "UPDATE analysis_jobs SET state = ?, attempt_count = ?, next_attempt_at = ?, last_error = ?, updated_at = ? WHERE id = ?",
                arguments: [state.rawValue, attemptCount, nextAttemptAt, error, now, id]
            )
        }
    }

    public func analysisJobs(profileID: String? = nil) throws -> [AnalysisJobRecord] {
        try databaseQueue.read { database in
            if let profileID {
                return try AnalysisJobRecord.fetchAll(
                    database,
                    sql: "SELECT * FROM analysis_jobs WHERE profile_id = ? ORDER BY created_at DESC",
                    arguments: [profileID]
                )
            }
            return try AnalysisJobRecord.fetchAll(database, sql: "SELECT * FROM analysis_jobs ORDER BY created_at DESC")
        }
    }

    public func purgeMedia(profileID: String, fileManager: FileManager = .default) throws {
        let paths = try media(profileID: profileID).map(\.filePath)
        try databaseQueue.write {
            try $0.execute(sql: "DELETE FROM media WHERE profile_id = ?", arguments: [profileID])
        }
        for path in paths where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }

    public func deleteProfile(id: String, fileManager: FileManager = .default) throws {
        try purgeMedia(profileID: id, fileManager: fileManager)
        try databaseQueue.write { try $0.execute(sql: "DELETE FROM profiles WHERE id = ?", arguments: [id]) }
    }

    public func deleteAll(fileManager: FileManager = .default) throws {
        let paths = try databaseQueue.read { try String.fetchAll($0, sql: "SELECT file_path FROM media") }
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM analysis_jobs")
            try database.execute(sql: "DELETE FROM analysis_runs")
            try database.execute(sql: "DELETE FROM media")
            try database.execute(sql: "DELETE FROM profiles")
        }
        for path in paths where fileManager.fileExists(atPath: path) { try? fileManager.removeItem(atPath: path) }
    }

    private static func queryParts(_ query: ProfileQuery) -> (whereSQL: String, arguments: StatementArguments) {
        var clauses: [String] = []
        var arguments = StatementArguments()
        if !query.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clauses.append("(username_normalized LIKE ? OR display_name LIKE ? OR bio LIKE ? OR hobbies_json LIKE ? OR education LIKE ? OR occupation LIKE ?)")
            let value = "%\(query.search.lowercased())%"
            arguments += [value, value, value, value, value, value]
        }
        Self.appendSetFilter(column: "mbti", values: query.mbti.map(\.rawValue), clauses: &clauses, arguments: &arguments)
        Self.appendSetFilter(column: "mbti_group", values: query.groups.map(\.rawValue), clauses: &clauses, arguments: &arguments)
        Self.appendSetFilter(column: "status", values: query.statuses.map(\.rawValue), clauses: &clauses, arguments: &arguments)
        if let minimumAge = query.minimumAge { clauses.append("age >= ?"); arguments += [minimumAge] }
        if let maximumAge = query.maximumAge { clauses.append("age <= ?"); arguments += [maximumAge] }
        if let city = query.city, !city.isEmpty {
            clauses.append("(city_normalized = ? COLLATE NOCASE OR country_normalized = ? COLLATE NOCASE)")
            arguments += [city, city]
        }
        if query.secondaryHighPriorityOnly {
            clauses.append("mbti_group = 'secondary' AND (face_score >= 82 OR lifestyle_score >= 82 OR profile_signals_score >= 82 OR overall_score >= 76 OR location_score >= 100)")
        }
        if query.preferredLocationNoMBTIOnly {
            clauses.append("mbti IS NULL AND location_score >= \(ProfileEligibilityPolicy.minimumNoMBTILocationScore)")
        }
        if query.missingLocationOnly {
            clauses.append("COALESCE(location_score, 10) <= 10")
        }
        if let value = query.minimumFaceScore { clauses.append("face_score >= ?"); arguments += [value] }
        if let value = query.minimumLifestyleScore { clauses.append("lifestyle_score >= ?"); arguments += [value] }
        if let value = query.minimumOverallScore { clauses.append("overall_score >= ?"); arguments += [value] }
        if let value = query.minimumConfidence { clauses.append("analysis_confidence >= ?"); arguments += [value] }
        if query.usableFaceRequired {
            clauses.append("EXISTS (SELECT 1 FROM media WHERE media.profile_id = profiles.id AND media.usable_face = 1 AND media.retained = 1)")
        }
        return (clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND "), arguments)
    }

    private static func appendSetFilter(
        column: String,
        values: [String],
        clauses: inout [String],
        arguments: inout StatementArguments
    ) {
        guard !values.isEmpty else { return }
        clauses.append("\(column) IN (\(Array(repeating: "?", count: values.count).joined(separator: ",")))")
        arguments += StatementArguments(values)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-core-schema") { database in
            try database.create(table: "profiles") { table in
                table.column("id", .text).primaryKey()
                table.column("username_raw", .text)
                table.column("username_normalized", .text).notNull().unique()
                table.column("display_name", .text)
                table.column("age", .integer)
                table.column("gender", .text)
                table.column("mbti", .text)
                table.column("mbti_group", .text)
                table.column("location_raw", .text)
                table.column("city_normalized", .text)
                table.column("province_normalized", .text)
                table.column("location_tier", .integer)
                table.column("location_score", .integer)
                table.column("face_score", .double)
                table.column("lifestyle_score", .double)
                table.column("profile_completeness_score", .double).notNull().defaults(to: 0)
                table.column("overall_score", .double)
                table.column("analysis_confidence", .double).notNull().defaults(to: 0)
                table.column("status", .text).notNull().defaults(to: "new")
                table.column("first_seen_at", .datetime).notNull()
                table.column("last_seen_at", .datetime).notNull()
                table.column("last_analyzed_at", .datetime)
                table.column("visit_count", .integer).notNull().defaults(to: 1)
                table.column("rejection_reason", .text)
                table.column("notes", .text).notNull().defaults(to: "")
            }

            try database.create(table: "media") { table in
                table.column("id", .text).primaryKey()
                table.column("profile_id", .text).notNull().indexed().references("profiles", onDelete: .cascade)
                table.column("kind", .text).notNull()
                table.column("file_path", .text).notNull()
                table.column("perceptual_hash", .text).notNull().indexed()
                table.column("source_sequence", .integer).notNull()
                table.column("face_count", .integer).notNull().defaults(to: 0)
                table.column("largest_face_ratio", .double).notNull().defaults(to: 0)
                table.column("face_capture_quality", .double)
                table.column("usable_face", .boolean).notNull().defaults(to: false)
                table.column("retained", .boolean).notNull().defaults(to: false)
                table.column("created_at", .datetime).notNull()
                table.uniqueKey(["profile_id", "perceptual_hash"])
            }

            try database.create(table: "analysis_runs") { table in
                table.column("id", .text).primaryKey()
                table.column("profile_id", .text).notNull().indexed().references("profiles", onDelete: .cascade)
                table.column("analysis_type", .text).notNull()
                table.column("model_name", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("request_json", .text).notNull()
                table.column("response_json", .text)
                table.column("started_at", .datetime).notNull()
                table.column("completed_at", .datetime)
                table.column("success", .boolean).notNull().defaults(to: false)
                table.column("error", .text)
            }
        }
        migrator.registerMigration("v2-offline-analysis-queue") { database in
            try database.create(table: "analysis_jobs") { table in
                table.column("id", .text).primaryKey()
                table.column("profile_id", .text).notNull().indexed().references("profiles", onDelete: .cascade)
                table.column("analysis_type", .text).notNull()
                table.column("model_name", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("media_paths", .text).notNull()
                table.column("state", .text).notNull().indexed()
                table.column("attempt_count", .integer).notNull().defaults(to: 0)
                table.column("next_attempt_at", .datetime).indexed()
                table.column("last_error", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v3-profile-metadata-signals") { database in
            try database.alter(table: "profiles") { table in
                table.add(column: "country_normalized", .text)
                table.add(column: "bio", .text)
                table.add(column: "hobbies_json", .text).notNull().defaults(to: "[]")
                table.add(column: "education", .text)
                table.add(column: "occupation", .text)
                table.add(column: "hobby_score", .double)
                table.add(column: "education_score", .double)
                table.add(column: "occupation_score", .double)
                table.add(column: "profile_signals_score", .double)
            }
        }
        migrator.registerMigration("v4-location-eligibility-tiers") { database in
            // Reclassify saved profiles from the original ranking so existing
            // records use the same collection gates as newly OCR'd profiles.
            try database.execute(sql: """
                UPDATE profiles
                SET location_tier = 4, location_score = 55
                WHERE city_normalized IN ('Xi''an', 'Xiamen')
                """)
            try database.execute(sql: """
                UPDATE profiles
                SET location_tier = 3, location_score = 70
                WHERE city_normalized IN ('Wuhan', 'Ningbo', 'Nanjing', 'Qingdao', 'Zhengzhou')
                """)
            try database.execute(sql: """
                UPDATE profiles
                SET location_tier = 2, location_score = 85
                WHERE city_normalized IN (
                    'Hong Kong', 'Guangzhou', 'Dongguan', 'Foshan', 'Zhuhai',
                    'Beijing', 'Shanghai', 'Chengdu', 'Chongqing', 'Hangzhou', 'Suzhou'
                ) OR province_normalized = 'Guangdong'
                """)
            try database.execute(sql: """
                UPDATE profiles
                SET location_tier = 1, location_score = 100
                WHERE city_normalized = 'Shenzhen'
                   OR country_normalized IN ('United States', 'Australia', 'United Kingdom', 'Canada')
                """)
            try database.execute(sql: """
                UPDATE profiles
                SET overall_score = CASE
                    WHEN mbti_group = 'primary' AND COALESCE(location_score, 10) <= 10 THEN
                        face_score * 0.5625 + lifestyle_score * 0.3125
                        + profile_completeness_score * 0.125
                    WHEN mbti_group = 'secondary' AND COALESCE(location_score, 10) <= 10 THEN
                        MAX(0, face_score * 0.625 + lifestyle_score * 0.375
                            - CASE WHEN face_score >= 90 THEN 0 ELSE 8 END)
                    WHEN mbti IS NULL AND COALESCE(location_score, 10) <= 10 THEN
                        MAX(0, face_score * (0.55 / 0.90) + lifestyle_score * (0.35 / 0.90)
                            - 8 - CASE WHEN face_score >= 90 THEN 0 ELSE 8 END)
                    WHEN mbti_group = 'primary' THEN
                        face_score * 0.45 + lifestyle_score * 0.25
                        + location_score * 0.20 + profile_completeness_score * 0.10
                    WHEN mbti_group = 'secondary' THEN
                        face_score * 0.50 + lifestyle_score * 0.30 + location_score * 0.20
                    WHEN mbti IS NULL AND location_score >= 85 THEN
                        MAX(0, face_score * 0.55 + lifestyle_score * 0.35 + location_score * 0.10 - 8)
                    ELSE overall_score
                END
                WHERE face_score IS NOT NULL AND lifestyle_score IS NOT NULL
                """)
        }
        migrator.registerMigration("v5-visible-tattoo-flag") { database in
            try database.alter(table: "profiles") { table in
                table.add(column: "has_visible_tattoo", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public enum RepositoryError: Error, LocalizedError, Sendable {
    case emptyUsername

    public var errorDescription: String? {
        switch self {
        case .emptyUsername: "A normalized username is required before a profile can be persisted."
        }
    }
}
