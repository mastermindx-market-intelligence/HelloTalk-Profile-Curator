import Foundation
@preconcurrency import GRDB

public final class ProfileRepository: @unchecked Sendable {
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
        return directory
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
        return migrator
    }
}
