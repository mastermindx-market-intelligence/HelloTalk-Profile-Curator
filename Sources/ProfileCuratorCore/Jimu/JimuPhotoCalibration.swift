import Foundation
import CoreGraphics
@preconcurrency import GRDB

public struct JimuPhotoRect: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public enum JimuPhotoContextExposure: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case profileShown = "PROFILE_CONTEXT_SHOWN_THIS_SESSION"
    case notShownThisSession = "NOT_SHOWN_THIS_SESSION_PRIOR_EXPOSURE_UNKNOWN"
}
public struct JimuPhotoCrop: Codable, Identifiable, Sendable {
    public let id: String
    public let observationID: String
    public let frameSHA256: String
    public let rect: JimuPhotoRect
    public let pixelSHA256: String
    public let isolationMethod: String
    public let supersedesID: String?
    public let createdAt: Date
}
public struct JimuPhotoEvidence: Codable, Equatable, Sendable {
    public let cropID: String
    public let frameSHA256: String
    public let rect: JimuPhotoRect
    public let pixelSHA256: String
    public let isolationMethod: String
    public let renderingVersion: String
    public let contextExposure: JimuPhotoContextExposure
}
public struct JimuPhotoPresentation {
    public let id: String
    public let basis: JimuFeedbackBasis
    public let crop: JimuPhotoCrop
    public let image: CGImage
}
enum JimuPhotoSchema {
    static func install(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE jimu_photo_crops (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
                observation_id TEXT NOT NULL REFERENCES profile_observations(id) ON DELETE CASCADE,
                supersedes_id TEXT UNIQUE, payload BLOB NOT NULL
            );
            CREATE INDEX jimu_photo_observation ON jimu_photo_crops(observation_id, sequence);
            CREATE TRIGGER jimu_photo_crops_immutable BEFORE UPDATE ON jimu_photo_crops
                BEGIN SELECT RAISE(ABORT, 'immutable_photo_crop'); END;
            """)
    }
    static func crops(id: String, database: Database) throws -> [JimuPhotoCrop] {
        try Data.fetchAll(database, sql: "SELECT payload FROM jimu_photo_crops WHERE observation_id = ? ORDER BY sequence",
            arguments: [id]).map { try JimuInspectorCoding.decode(JimuPhotoCrop.self, from: $0) }
    }
}

enum JimuPhotoRaster {
    static let version = "RGBA8_SRGB_SOURCE_PIXELS_V1"
    static func render(_ image: CGImage, rect: JimuPhotoRect) throws -> (image: CGImage, digest: String) {
        guard rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
              rect.width <= image.width, rect.height <= image.height,
              rect.x <= image.width - rect.width, rect.y <= image.height - rect.height else {
            throw JimuReplayError(code: "invalid_photo_crop")
        }
        let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        guard let crop = image.cropping(to: bounds) else { throw JimuReplayError(code: "invalid_photo_crop") }
        let color = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: rect.width, height: rect.height,
                bitsPerComponent: 8, bytesPerRow: rect.width * 4, space: color, bitmapInfo: info) else {
                throw JimuReplayError(code: "photo_render_failed")
            }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(crop, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let output = CGImage(width: rect.width, height: rect.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: rect.width * 4, space: color,
                bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw JimuReplayError(code: "photo_render_failed")
        }
        let prefix = Data("\(version):\(rect.width):\(rect.height):".utf8)
        return (output, JimuInspectorCoding.digest(prefix + data))
    }
}
public extension ProfileRepository {
    func jimuPhotoCrops(observationID: String) throws -> [JimuPhotoCrop] {
        try databaseQueue.read { try JimuPhotoSchema.crops(id: observationID, database: $0) }
    }
}
public extension MediaStore {
    func saveJimuPhotoCrop(snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?,
        rect: JimuPhotoRect, confirmedPhotoOnly: Bool, expectedCropID: String? = nil) throws -> JimuPhotoCrop {
        guard confirmedPhotoOnly else { throw JimuReplayError(code: "photo_isolation_confirmation_required") }
        return try repository.databaseQueue.write { database in
            let current = try ProfileRepository.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            try checkJimuSourceAdmission(snapshot: snapshot, current: current)
            guard let record = try JimuSourceMediaSchema.record(id: snapshot.id, database: database) else {
                throw JimuReplayError(code: "source_asset_missing")
            }
            let source = try readBoundJimuFrame(record, snapshot: current)
            let previous = try JimuPhotoSchema.crops(id: snapshot.id, database: database).last
            guard previous?.id == expectedCropID else { throw JimuReplayError(code: "stale_photo_crop") }
            let raster = try JimuPhotoRaster.render(source.image, rect: rect)
            if let previous, previous.rect == rect, previous.pixelSHA256 == raster.digest { return previous }
            let crop = JimuPhotoCrop(id: UUID().uuidString, observationID: snapshot.id,
                frameSHA256: record.frameSHA256, rect: rect, pixelSHA256: raster.digest,
                isolationMethod: "HUMAN_CONFIRMED_PHOTO_REGION_V1", supersedesID: previous?.id, createdAt: Date())
            try database.execute(sql: "INSERT INTO jimu_photo_crops (id, observation_id, supersedes_id, payload) VALUES (?, ?, ?, ?)",
                arguments: [crop.id, crop.observationID, crop.supersedesID, try JimuInspectorCoding.encode(crop)])
            return crop
        }
    }
    func prepareJimuPhotoPresentation(snapshot: JimuInspectorSnapshot, policy: JimuReplayPolicy?,
        exposure: JimuPhotoContextExposure = .unknown) throws -> JimuPhotoPresentation {
        try repository.databaseQueue.read { database in
            let current = try ProfileRepository.jimuSnapshot(id: snapshot.id, policy: policy, database: database)
            try checkJimuSourceAdmission(snapshot: snapshot, current: current)
            return try photoPresentation(current: current, exposure: exposure, database: database)
        }
    }
    func recordJimuPhotoFeedback(presentation: JimuPhotoPresentation, policy: JimuReplayPolicy?,
        choice: JimuFeedbackChoice, comparison: JimuPhotoPresentation? = nil,
        supersedesID: String? = nil) throws -> JimuFeedback {
        let allowed: [JimuFeedbackChoice] = comparison == nil ? [.approve, .reject] : [.left, .right, .tie, .neither]
        guard allowed.contains(choice) else { throw JimuReplayError(code: "invalid_feedback_choice") }
        guard comparison?.crop.observationID != presentation.crop.observationID else {
            throw JimuReplayError(code: "same_observation_comparison")
        }
        return try repository.databaseQueue.write { database in
            let current = try validatePhotoPresentation(presentation, policy: policy, database: database)
            if let comparison {
                let other = try validatePhotoPresentation(comparison, policy: policy, database: database)
                guard current.observation.platform == other.observation.platform,
                      current.observation.accountID == other.observation.accountID else {
                    throw JimuReplayError(code: "comparison_namespace_mismatch")
                }
            }
            let id = "photo-" + presentation.id
            if let data = try Data.fetchOne(database, sql: "SELECT payload FROM preference_feedback WHERE id = ?", arguments: [id]) {
                let existing = try JimuInspectorCoding.decode(JimuFeedback.self, from: data)
                guard existing.scope == .visualOnly, existing.choice == choice,
                      try JimuInspectorCoding.encode(existing.basis) == JimuInspectorCoding.encode(presentation.basis),
                      try JimuInspectorCoding.encode(existing.comparison) == JimuInspectorCoding.encode(comparison?.basis),
                      existing.supersedesID == supersedesID else { throw JimuReplayError(code: "photo_submission_conflict") }
                return existing
            }
            let feedback = JimuFeedback(id: id, scope: .visualOnly, choice: choice,
                basis: presentation.basis, comparison: comparison?.basis, actionContext: nil,
                supersedesID: supersedesID, createdAt: Date())
            try ProfileRepository.insertJimuFeedback(feedback, database: database)
            return feedback
        }
    }
    private func validatePhotoPresentation(_ shown: JimuPhotoPresentation, policy: JimuReplayPolicy?,
        database: Database) throws -> JimuInspectorSnapshot {
        let current = try ProfileRepository.jimuSnapshot(id: shown.crop.observationID, policy: policy, database: database)
        guard current.preferenceLabelsAllowed else { throw JimuReplayError(code: "adult_evidence_required") }
        let fresh = try photoPresentation(current: current,
            exposure: shown.basis.photo?.contextExposure ?? .unknown, database: database)
        guard fresh.crop.id == shown.crop.id,
              try JimuInspectorCoding.encode(fresh.basis) == JimuInspectorCoding.encode(shown.basis),
              try JimuInspectorCoding.encode(fresh.crop) == JimuInspectorCoding.encode(shown.crop) else {
            throw JimuReplayError(code: "stale_photo_presentation")
        }
        return current
    }
    private func photoPresentation(current: JimuInspectorSnapshot, exposure: JimuPhotoContextExposure,
        database: Database) throws -> JimuPhotoPresentation {
        guard current.preferenceLabelsAllowed else { throw JimuReplayError(code: "adult_evidence_required") }
        guard let crop = try JimuPhotoSchema.crops(id: current.id, database: database).last,
              let record = try JimuSourceMediaSchema.record(id: current.id, database: database) else {
            throw JimuReplayError(code: "photo_crop_required")
        }
        let frame = try readBoundJimuFrame(record, snapshot: current)
        let raster = try JimuPhotoRaster.render(frame.image, rect: crop.rect)
        guard crop.frameSHA256 == record.frameSHA256, crop.pixelSHA256 == raster.digest,
              crop.isolationMethod == "HUMAN_CONFIRMED_PHOTO_REGION_V1" else {
            throw JimuReplayError(code: "photo_crop_integrity_failed")
        }
        let evidence = JimuPhotoEvidence(cropID: crop.id, frameSHA256: crop.frameSHA256,
            rect: crop.rect, pixelSHA256: crop.pixelSHA256, isolationMethod: crop.isolationMethod,
            renderingVersion: JimuPhotoRaster.version, contextExposure: exposure)
        struct Revision: Encodable { let evidenceRevision: String; let photo: JimuPhotoEvidence }
        let revision = JimuInspectorCoding.digest(try JimuInspectorCoding.encode(
            Revision(evidenceRevision: current.revision, photo: evidence)))
        let basis = JimuFeedbackBasis(observationID: current.id, inputSHA256: current.observation.inputSHA256,
            correctionIDs: current.basis.correctionIDs, policy: current.basis.policy, revision: revision,
            presentationKind: "HUMAN_CONFIRMED_PHOTO_ONLY_V1", modelScoresVisible: false, photo: evidence)
        return JimuPhotoPresentation(id: UUID().uuidString, basis: basis, crop: crop, image: raster.image)
    }
}
