import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin
@preconcurrency import GRDB

/// Local byte integrity, not independent authentication of capture origin.
public struct JimuSourceMediaRecord: Codable, Sendable {
    public let observationID: String
    public let frameSHA256: String
    public let filePath: String
    public let byteCount: Int
    public let width: Int
    public let height: Int
    public let addedAt: Date
}
public struct JimuSourceFrame {
    public let record: JimuSourceMediaRecord
    public let image: CGImage
}

enum JimuSourceMediaSchema {
    static func install(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE jimu_source_media (
                observation_id TEXT PRIMARY KEY NOT NULL REFERENCES profile_observations(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL UNIQUE, payload BLOB NOT NULL
            );
            CREATE TRIGGER jimu_source_media_immutable BEFORE UPDATE ON jimu_source_media
                BEGIN SELECT RAISE(ABORT, 'immutable_source_media'); END;
            """)
    }
    static func record(id: String, database: Database) throws -> JimuSourceMediaRecord? {
        guard let data = try Data.fetchOne(database, sql: "SELECT payload FROM jimu_source_media WHERE observation_id = ?", arguments: [id]) else { return nil }
        return try JimuInspectorCoding.decode(JimuSourceMediaRecord.self, from: data)
    }
}

enum JimuSourceImageIO {
    static let maximumBytes = 8 * 1024 * 1024
    static func folder(root: URL, observationID: String) -> URL {
        root.appendingPathComponent("jimu-sources", isDirectory: true)
            .appendingPathComponent(JimuInspectorCoding.digest(Data(observationID.utf8)), isDirectory: true)
    }
    static func checkedPath(_ url: URL, root: URL) throws -> URL {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(base) else { throw JimuReplayError(code: "source_asset_path_mismatch") }
        let original = url.standardizedFileURL
        let originalBase = root.standardizedFileURL.path + "/"
        guard original.path.hasPrefix(originalBase) else { throw JimuReplayError(code: "source_asset_path_mismatch") }
        var component = root.standardizedFileURL
        for name in original.path.dropFirst(originalBase.count).split(separator: "/") {
            component.appendPathComponent(String(name))
            if (try? component.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw JimuReplayError(code: "local_regular_file_required")
            }
        }
        return original
    }
    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw JimuReplayError(code: "local_file_required") }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw JimuReplayError(code: errno == ENOENT ? "source_asset_missing" : "local_regular_file_required") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw JimuReplayError(code: "local_regular_file_required")
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw JimuReplayError(code: "source_image_too_large") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw JimuReplayError(code: "source_image_too_large") }
        guard data.count == info.st_size else { throw JimuReplayError(code: "source_asset_changed_during_read") }
        return data
    }
    static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= maximumBytes else { throw JimuReplayError(code: "source_image_too_large") }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw JimuReplayError(code: "invalid_source_image")
        }
        guard let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type), CGImageSourceGetCount(source) == 1 else {
            throw JimuReplayError(code: "unsupported_source_image")
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0, width <= 8_192, height <= 8_192, width <= 16_000_000 / height else {
            throw JimuReplayError(code: "source_image_dimensions_exceeded")
        }
        guard ((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) == 1 else {
            throw JimuReplayError(code: "unsupported_source_orientation")
        }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldCache: true] as CFDictionary),
              image.width == width, image.height == height else { throw JimuReplayError(code: "invalid_source_image") }
        return image
    }
}

public extension MediaStore {
    static func readJimuSourceFile(_ url: URL) throws -> Data { try JimuSourceImageIO.read(url) }

    func bindJimuSourceFrame(_ data: Data, snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?) throws -> JimuSourceMediaRecord {
        guard data.count <= JimuSourceImageIO.maximumBytes else { throw JimuReplayError(code: "source_image_too_large") }
        return try repository.databaseQueue.write { database in
            let current = try ProfileRepository.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            try checkJimuSourceAdmission(snapshot: snapshot, current: current)
            guard JimuInspectorCoding.digest(data) == current.report.frameSHA256 else {
                throw JimuReplayError(code: "source_asset_hash_mismatch")
            }
            let image = try JimuSourceImageIO.decode(data)
            if let existing = try JimuSourceMediaSchema.record(id: snapshot.id, database: database) {
                return try readBoundJimuFrame(existing, snapshot: current).record
            }
            let url = try jimuSourceURL(snapshot: current)
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let existed = FileManager.default.fileExists(atPath: url.path)
            if existed {
                guard try JimuSourceImageIO.read(url) == data else { throw JimuReplayError(code: "source_asset_integrity_failed") }
            } else {
                try data.write(to: url, options: [.atomic])
            }
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                let record = JimuSourceMediaRecord(observationID: snapshot.id, frameSHA256: current.report.frameSHA256,
                    filePath: url.path, byteCount: data.count, width: image.width, height: image.height,
                    addedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)))
                try database.execute(sql: "INSERT INTO jimu_source_media (observation_id, file_path, payload) VALUES (?, ?, ?)",
                    arguments: [snapshot.id, url.path, try JimuInspectorCoding.encode(record)])
                return record
            } catch {
                if !existed {
                    do { try FileManager.default.removeItem(at: url) }
                    catch { throw JimuReplayError(code: "source_asset_cleanup_failed") }
                }
                throw error
            }
        }
    }
    func jimuSourceFrame(snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?) throws -> JimuSourceFrame? {
        try repository.databaseQueue.read { database in
            let current = try ProfileRepository.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            guard let record = try JimuSourceMediaSchema.record(id: snapshot.id, database: database) else { return nil }
            try checkJimuSourceAdmission(snapshot: snapshot, current: current)
            return try readBoundJimuFrame(record, snapshot: current)
        }
    }
    private func checkJimuSourceAdmission(snapshot: JimuInspectorSnapshot, current: JimuInspectorSnapshot) throws {
        guard snapshot.revision == current.revision else { throw JimuReplayError(code: "stale_presentation") }
        guard current.preferenceLabelsAllowed else { throw JimuReplayError(code: "adult_evidence_required") }
    }
    private func jimuSourceURL(snapshot: JimuInspectorSnapshot) throws -> URL {
        let expectedRoot = URL(fileURLWithPath: repository.databasePath).deletingLastPathComponent().appendingPathComponent("media")
        guard rootURL.resolvingSymlinksInPath().standardizedFileURL == expectedRoot.resolvingSymlinksInPath().standardizedFileURL else {
            throw JimuReplayError(code: "source_media_root_mismatch")
        }
        let candidate = JimuSourceImageIO.folder(root: rootURL, observationID: snapshot.id)
            .appendingPathComponent(snapshot.report.frameSHA256 + ".image")
        return try JimuSourceImageIO.checkedPath(candidate, root: rootURL)
    }
    private func readBoundJimuFrame(_ record: JimuSourceMediaRecord, snapshot: JimuInspectorSnapshot) throws -> JimuSourceFrame {
        let url = try jimuSourceURL(snapshot: snapshot)
        guard record.observationID == snapshot.id, record.frameSHA256 == snapshot.report.frameSHA256,
              record.filePath == url.path else { throw JimuReplayError(code: "source_asset_metadata_mismatch") }
        let data = try JimuSourceImageIO.read(url)
        guard data.count == record.byteCount, JimuInspectorCoding.digest(data) == record.frameSHA256 else {
            throw JimuReplayError(code: "source_asset_integrity_failed")
        }
        let image = try JimuSourceImageIO.decode(data)
        guard image.width == record.width, image.height == record.height else {
            throw JimuReplayError(code: "source_asset_metadata_mismatch")
        }
        return JimuSourceFrame(record: record, image: image)
    }
}

extension ProfileRepository {
    /// Remove managed bytes before row deletion. A failure leaves the record visible for reconciliation.
    /// Also removes a known observation's unbound file left by interruption before SQLite commit.
    func removeJimuSourceMedia(database: Database, observationID: String? = nil) throws {
        let ids = try observationID.map { [$0] } ?? String.fetchAll(database, sql: "SELECT id FROM profile_observations")
        let root = URL(fileURLWithPath: databasePath).deletingLastPathComponent().appendingPathComponent("media")
        for id in ids {
            let folder = try JimuSourceImageIO.checkedPath(JimuSourceImageIO.folder(root: root, observationID: id), root: root)
            if FileManager.default.fileExists(atPath: folder.path) {
                do { try FileManager.default.removeItem(at: folder) }
                catch { throw JimuReplayError(code: "source_asset_cleanup_failed") }
            }
        }
    }
}
