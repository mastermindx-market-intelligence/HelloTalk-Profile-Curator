import Foundation
import XCTest
@preconcurrency import GRDB
@testable import ProfileCuratorCore

final class JimuSourceMediaTests: XCTestCase {
    func testSourceImagesUseTheExistingDatabaseAndMigrationOwner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("curator.sqlite").path
        let repository = try ProfileRepository(databasePath: path)
        XCTAssertTrue(try repository.jimuObservations().isEmpty)
        let database = try DatabaseQueue(path: path)
        try database.read { db in
            XCTAssertTrue(try db.tableExists("jimu_source_media"),
                "W1 must bind source image bytes inside the existing observation/database owner")
        }
    }
}

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension JimuSourceMediaTests {
    private func withStore(_ body: (ProfileRepository, MediaStore, Data) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
        let store = try MediaStore(rootURL: root.appendingPathComponent("media"), repository: repository)
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8,
            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let data = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try body(repository, store, data as Data)
    }
    private var policy: JimuReplayPolicy {
        JimuReplayPolicy(policyID: "synthetic-image-v1", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
    }
    private func observation(_ repository: ProfileRepository, bytes: Data, age: Int = 29) throws -> JimuInspectorSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["frame_sha256"] = JimuInspectorCoding.digest(bytes)
        var fields = try XCTUnwrap(object["fields"] as? [[String: Any]])
        fields[0]["value"] = age; fields[0]["raw_text"] = String(age)
        object["fields"] = fields
        var eligibility = try XCTUnwrap(object["eligibility"] as? [String: Any])
        eligibility["displayed_age"] = age
        eligibility["status"] = age >= 18 ? "ACCEPTED_ADULT_DISPLAY" : "INELIGIBLE"
        object["eligibility"] = eligibility
        let stored = try repository.importJimuObservation(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), policy: policy)
        return try repository.jimuSnapshot(id: stored.id, policy: policy)
    }
    private func rejects(_ code: String, _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual(($0 as? JimuReplayError)?.code, code, file: file, line: line)
        }
    }
    func testMatchingSourceBytesPersistAndRecoverAfterDatabaseReopen() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let record = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: record.filePath)), bytes)
            XCTAssertEqual(record.frameSHA256, snapshot.report.frameSHA256)
            XCTAssertEqual(record.width, 64); XCTAssertEqual(record.height, 48)
            let reopened = try ProfileRepository(databasePath: repository.databasePath)
            let recovered = try XCTUnwrap(MediaStore(rootURL: store.rootURL, repository: reopened)
                .jimuSourceFrame(snapshot: reopened.jimuSnapshot(id: snapshot.id, policy: policy), policy: policy))
            XCTAssertEqual(recovered.image.width, 64)
            XCTAssertEqual(recovered.record.frameSHA256, record.frameSHA256)
            XCTAssertEqual(try reopened.jimuSnapshot(id: snapshot.id, policy: policy).observation.rawData, snapshot.observation.rawData)
        }
    }
    func testWrongImageHashCannotAttachOrChangeObservation() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            rejects("source_asset_hash_mismatch") {
                _ = try store.bindJimuSourceFrame(bytes + Data([0]), snapshot: snapshot, policy: policy)
            }
            XCTAssertNil(try store.jimuSourceFrame(snapshot: snapshot, policy: policy))
        }
    }
    func testMalformedImageWithMatchingClaimIsRejected() throws {
        try withStore { repository, store, _ in
            let bytes = Data("not an image".utf8)
            let snapshot = try observation(repository, bytes: bytes)
            rejects("invalid_source_image") {
                _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            }
        }
    }
    func testRepeatedBindingIsIdempotent() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let first = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            let second = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            XCTAssertEqual(first.filePath, second.filePath)
            XCTAssertEqual(first.addedAt, second.addedAt)
        }
    }
    func testUnderageObservationCannotRetainSourceImage() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes, age: 17)
            rejects("adult_evidence_required") {
                _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            }
        }
    }
    func testCorruptedStoredImageCannotBeDisplayed() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let record = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            try Data("changed".utf8).write(to: URL(fileURLWithPath: record.filePath))
            rejects("source_asset_integrity_failed") {
                _ = try store.jimuSourceFrame(snapshot: snapshot, policy: policy)
            }
        }
    }
    func testMissingStoredImageRemainsUnavailable() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let record = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            try FileManager.default.removeItem(atPath: record.filePath)
            rejects("source_asset_missing") {
                _ = try store.jimuSourceFrame(snapshot: snapshot, policy: policy)
            }
        }
    }
    func testDeletingObservationAlsoRemovesSourceBytes() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let record = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            try repository.deleteJimuObservation(id: snapshot.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.filePath))
            XCTAssertTrue(try repository.jimuObservations().isEmpty)
        }
    }
    func testDeleteAllAlsoRemovesSourceBytes() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let record = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            try repository.deleteAll()
            XCTAssertFalse(FileManager.default.fileExists(atPath: record.filePath))
        }
    }
    func testAttachingSourceFrameDoesNotEnableVisualLabelsOrActions() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            rejects("visual_evidence_unavailable") {
                _ = try repository.recordJimuFeedback(snapshot: snapshot, policy: policy, scope: .visualOnly, choice: .approve)
            }
            XCTAssertEqual(snapshot.report.enabledActions, [])
        }
    }
    func testStaleSnapshotCannotAttachSource() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            _ = try repository.appendJimuCorrection(snapshot: snapshot, policy: policy,
                fieldID: "field-bio-001", state: "ABSENT", value: .null, reason: "Changed evidence")
            rejects("stale_presentation") {
                _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            }
        }
    }
    func testOversizedSourceIsRefusedBeforeDecoding() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            rejects("source_image_too_large") {
                _ = try store.bindJimuSourceFrame(Data(repeating: 0, count: 8 * 1024 * 1024 + 1), snapshot: snapshot, policy: policy)
            }
        }
    }
    func testStoredSourceMetadataCannotBeUpdated() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            let other = try DatabaseQueue(path: repository.databasePath)
            XCTAssertThrowsError(try other.write { try $0.execute(sql: "UPDATE jimu_source_media SET payload = X'00'") })
        }
    }
}

extension JimuSourceMediaTests {
    func testFullSourceImageCannotBeMisrecordedAsTextOnlyFeedback() throws {
        try withStore { repository, store, bytes in
            let before = try observation(repository, bytes: bytes)
            let historical = try repository.recordJimuFeedback(snapshot: before, policy: policy, scope: .fullProfile, choice: .approve)
            _ = try store.bindJimuSourceFrame(bytes, snapshot: before, policy: policy)
            let current = try repository.jimuSnapshot(id: before.id, policy: policy)
            rejects("source_image_label_presentation_pending") {
                _ = try repository.recordJimuFeedback(snapshot: current, policy: policy, scope: .fullProfile, choice: .reject)
            }
            XCTAssertEqual(try repository.jimuFeedback(observationID: current.id).map(\.id), [historical.id])
        }
    }
    func testPreexistingManagedSymlinkIsNotAdoptedAsOwnedMedia() throws {
        try withStore { repository, store, bytes in
            let snapshot = try observation(repository, bytes: bytes)
            let folder = JimuSourceImageIO.folder(root: store.rootURL, observationID: snapshot.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let alternate = store.rootURL.appendingPathComponent("unowned-image.png")
            try bytes.write(to: alternate)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(snapshot.report.frameSHA256 + ".image"), withDestinationURL: alternate)
            rejects("local_regular_file_required") {
                _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
            }
        }
    }
}
