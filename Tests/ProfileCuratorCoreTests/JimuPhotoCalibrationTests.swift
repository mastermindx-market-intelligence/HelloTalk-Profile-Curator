import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@preconcurrency import GRDB
@testable import ProfileCuratorCore

final class JimuPhotoCalibrationTests: XCTestCase {
    func testPhotoCropHistoryUsesExistingDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
        let queue = try DatabaseQueue(path: repository.databasePath)
        XCTAssertTrue(try queue.read { try $0.tableExists("jimu_photo_crops") },
            "Photo-only calibration must have immutable crop history under the existing database owner")
    }
}
extension JimuPhotoCalibrationTests {
    private var policy: JimuReplayPolicy {
        JimuReplayPolicy(policyID: "synthetic-photo-v1", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
    }
    private var rect: JimuPhotoRect { JimuPhotoRect(x: 8, y: 4, width: 32, height: 24) }
    private func withStore(_ body: (ProfileRepository, MediaStore, Data) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
        let store = try MediaStore(rootURL: root.appendingPathComponent("media"), repository: repository)
        var pixels = [UInt8]()
        for y in 0..<48 { for x in 0..<64 { pixels += [UInt8(x), UInt8(y), 100, 255] } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try body(repository, store, output as Data)
    }
    private func rejects(_ code: String, _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual(($0 as? JimuReplayError)?.code, code, file: file, line: line)
        }
    }
    private func imported(_ repository: ProfileRepository, _ store: MediaStore, _ bytes: Data,
        id: String = "synthetic-photo-a", account: String = "synthetic-account") throws -> JimuInspectorSnapshot {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try Data(contentsOf: root.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["observation_id"] = id; object["encounter_id"] = id + "-encounter"
        object["account_id"] = account; object["frame_sha256"] = JimuInspectorCoding.digest(bytes)
        let stored = try repository.importJimuObservation(JSONSerialization.data(withJSONObject: object), policy: policy)
        let snapshot = try repository.jimuSnapshot(id: stored.id, policy: policy)
        _ = try store.bindJimuSourceFrame(bytes, snapshot: snapshot, policy: policy)
        return try repository.jimuSnapshot(id: stored.id, policy: policy)
    }
    private func prepared(_ repository: ProfileRepository, _ store: MediaStore, _ bytes: Data,
        id: String = "synthetic-photo-a", account: String = "synthetic-account") throws -> JimuPhotoPresentation {
        let snapshot = try imported(repository, store, bytes, id: id, account: account)
        _ = try store.saveJimuPhotoCrop(snapshot: snapshot, policy: policy, rect: rect, confirmedPhotoOnly: true)
        return try store.prepareJimuPhotoPresentation(snapshot: snapshot, policy: policy, exposure: .profileShown)
    }
    func testCropRequiresExplicitPhotoOnlyConfirmation() throws {
        try withStore { repo, store, bytes in
            let snapshot = try imported(repo, store, bytes)
            rejects("photo_isolation_confirmation_required") {
                _ = try store.saveJimuPhotoCrop(snapshot: snapshot, policy: policy, rect: rect, confirmedPhotoOnly: false)
            }
            XCTAssertTrue(try repo.jimuPhotoCrops(observationID: snapshot.id).isEmpty)
        }
    }
    func testCropRejectsOverflowZeroAndOutOfBoundsRatherThanClipping() throws {
        try withStore { repo, store, bytes in
            let snapshot = try imported(repo, store, bytes)
            let bad = [JimuPhotoRect(x: -1, y: 0, width: 10, height: 10),
                JimuPhotoRect(x: 0, y: 0, width: 0, height: 10),
                JimuPhotoRect(x: 63, y: 0, width: 2, height: 10),
                JimuPhotoRect(x: Int.max, y: 0, width: Int.max, height: 10)]
            for value in bad { rejects("invalid_photo_crop") {
                _ = try store.saveJimuPhotoCrop(snapshot: snapshot, policy: policy, rect: value, confirmedPhotoOnly: true)
            } }
            XCTAssertTrue(try repo.jimuPhotoCrops(observationID: snapshot.id).isEmpty)
        }
    }
    func testPreparedCropHasExactPixelsAndNoTextOnlyBasis() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            XCTAssertEqual(view.image.width, 32); XCTAssertEqual(view.image.height, 24)
            let pixels = try XCTUnwrap(view.image.dataProvider?.data) as Data
            XCTAssertEqual(Array(pixels.prefix(4)), [8, 4, 100, 255], "Source pixels use top-left coordinates")
            XCTAssertEqual(view.basis.presentationKind, "HUMAN_CONFIRMED_PHOTO_ONLY_V1")
            XCTAssertEqual(view.basis.photo?.frameSHA256, JimuInspectorCoding.digest(bytes))
            XCTAssertEqual(view.basis.photo?.cropID, view.crop.id)
            XCTAssertEqual(view.basis.photo?.rect, rect)
            XCTAssertEqual(view.basis.photo?.contextExposure, .profileShown)
            XCTAssertFalse(view.basis.modelScoresVisible)
        }
    }
    func testAbsoluteVisualLabelPersistsInExistingFeedbackOwner() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let label = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            XCTAssertEqual(label.scope, .visualOnly)
            XCTAssertEqual(label.basis.photo?.pixelSHA256, view.crop.pixelSHA256)
            XCTAssertNil(label.actionContext); XCTAssertNil(label.comparison)
            let reopened = try ProfileRepository(databasePath: repo.databasePath)
            let saved = try XCTUnwrap(reopened.jimuFeedback(observationID: view.crop.observationID).first)
            XCTAssertEqual(saved.id, label.id); XCTAssertEqual(saved.basis.revision, view.basis.revision)
        }
    }
    func testPairwiseTieAndNeitherBindBothOrderedImages() throws {
        try withStore { repo, store, bytes in
            let left = try prepared(repo, store, bytes)
            let right = try prepared(repo, store, bytes, id: "synthetic-photo-b")
            let tie = try store.recordJimuPhotoFeedback(presentation: left, policy: policy, choice: .tie, comparison: right)
            XCTAssertEqual(tie.basis.photo?.cropID, left.crop.id)
            XCTAssertEqual(tie.comparison?.photo?.cropID, right.crop.id)
            let newLeft = try store.prepareJimuPhotoPresentation(snapshot: repo.jimuSnapshot(id: left.crop.observationID, policy: policy), policy: policy)
            let neither = try store.recordJimuPhotoFeedback(presentation: newLeft, policy: policy, choice: .neither, comparison: right)
            XCTAssertEqual(neither.choice, .neither)
            XCTAssertEqual(try repo.jimuFeedback(observationID: right.crop.observationID).count, 2)
        }
    }
    func testDuplicateSubmissionIsIdempotentButChangedChoiceConflicts() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let first = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            let duplicate = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            XCTAssertEqual(first.id, duplicate.id)
            rejects("photo_submission_conflict") {
                _ = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .reject)
            }
            XCTAssertEqual(try repo.jimuFeedback(observationID: view.crop.observationID).count, 1)
        }
    }
    func testVisualChoicesCannotBecomeActionsOrUnpairedPreferences() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            for choice in [JimuFeedbackChoice.note, .instant, .rightSwipe, .left, .tie] {
                rejects("invalid_feedback_choice") {
                    _ = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: choice)
                }
            }
            XCTAssertEqual(try repo.jimuFeedback(observationID: view.crop.observationID).count, 0)
        }
    }
    func testRecropInvalidatesOldPresentationWithoutChangingHistoricalLabel() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let old = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            let snapshot = try repo.jimuSnapshot(id: view.crop.observationID, policy: policy)
            let next = try store.saveJimuPhotoCrop(snapshot: snapshot, policy: policy,
                rect: JimuPhotoRect(x: 9, y: 5, width: 20, height: 20), confirmedPhotoOnly: true, expectedCropID: view.crop.id)
            XCTAssertEqual(next.supersedesID, view.crop.id)
            rejects("stale_photo_presentation") {
                _ = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .reject)
            }
            XCTAssertEqual(try repo.jimuPhotoCrops(observationID: snapshot.id).count, 2)
            XCTAssertEqual(try repo.jimuFeedback(observationID: snapshot.id).first?.basis.photo?.cropID, old.basis.photo?.cropID)
        }
    }
    func testStaleCropEditorCannotOverwriteNewerRegion() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let snapshot = try repo.jimuSnapshot(id: view.crop.observationID, policy: policy)
            rejects("stale_photo_crop") {
                _ = try store.saveJimuPhotoCrop(snapshot: snapshot, policy: policy, rect: rect, confirmedPhotoOnly: true)
            }
            XCTAssertEqual(try repo.jimuPhotoCrops(observationID: snapshot.id).count, 1)
        }
    }
    func testPolicyAndManualAgeChangeInvalidateVisualSubmission() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let changed = JimuReplayPolicy(policyID: "changed", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
            rejects("stale_photo_presentation") {
                _ = try store.recordJimuPhotoFeedback(presentation: view, policy: changed, choice: .approve)
            }
            let snapshot = try repo.jimuSnapshot(id: view.crop.observationID, policy: policy)
            _ = try repo.appendJimuCorrection(snapshot: snapshot, policy: policy, fieldID: "field-age-001",
                state: "PRESENT", value: .number(29), reason: "Human age is not fresh platform evidence")
            rejects("adult_evidence_required") {
                _ = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            }
        }
    }
    func testChangedOrMissingSourceCannotYieldVisualLabel() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let snapshot = try repo.jimuSnapshot(id: view.crop.observationID, policy: policy)
            let source = try XCTUnwrap(store.jimuSourceFrame(snapshot: snapshot, policy: policy))
            try Data("corrupted".utf8).write(to: URL(fileURLWithPath: source.record.filePath))
            rejects("source_asset_integrity_failed") {
                _ = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            }
            XCTAssertTrue(try repo.jimuFeedback(observationID: snapshot.id).isEmpty)
        }
    }
    func testPairRequiresDifferentObservationsInSameAccount() throws {
        try withStore { repo, store, bytes in
            let left = try prepared(repo, store, bytes)
            rejects("same_observation_comparison") {
                _ = try store.recordJimuPhotoFeedback(presentation: left, policy: policy, choice: .tie, comparison: left)
            }
            let right = try prepared(repo, store, bytes, id: "other-account-photo", account: "other-account")
            rejects("comparison_namespace_mismatch") {
                _ = try store.recordJimuPhotoFeedback(presentation: left, policy: policy, choice: .tie, comparison: right)
            }
        }
    }
    func testSupersedingVisualJudgmentPreservesEarlierChoice() throws {
        try withStore { repo, store, bytes in
            let view = try prepared(repo, store, bytes)
            let old = try store.recordJimuPhotoFeedback(presentation: view, policy: policy, choice: .approve)
            let next = try store.prepareJimuPhotoPresentation(snapshot: repo.jimuSnapshot(id: view.crop.observationID, policy: policy), policy: policy)
            let replacement = try store.recordJimuPhotoFeedback(presentation: next, policy: policy, choice: .reject, supersedesID: old.id)
            XCTAssertEqual(replacement.supersedesID, old.id)
            XCTAssertEqual(try repo.jimuFeedback(observationID: view.crop.observationID).map(\.choice), [.approve, .reject])
        }
    }
    func testDeleteCascadesCropAndPairwiseFeedbackWithoutSecondAssetCopy() throws {
        try withStore { repo, store, bytes in
            let left = try prepared(repo, store, bytes)
            let right = try prepared(repo, store, bytes, id: "synthetic-photo-b")
            _ = try store.recordJimuPhotoFeedback(presentation: left, policy: policy, choice: .left, comparison: right)
            try repo.deleteJimuObservation(id: right.crop.observationID)
            XCTAssertTrue(try repo.jimuPhotoCrops(observationID: right.crop.observationID).isEmpty)
            XCTAssertTrue(try repo.jimuFeedback(observationID: left.crop.observationID).isEmpty)
            XCTAssertEqual(try repo.jimuPhotoCrops(observationID: left.crop.observationID).count, 1)
        }
    }
    func testLegacyTextBasisDecodesWithoutPhotoAndRemainsTextOnly() throws {
        try withStore { repo, store, bytes in
            let snapshot = try imported(repo, store, bytes)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JimuInspectorCoding.encode(snapshot.basis)) as? [String: Any])
            object.removeValue(forKey: "photo")
            let recovered = try JimuInspectorCoding.decode(JimuFeedbackBasis.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(recovered.photo)
            XCTAssertEqual(recovered.presentationKind, "TEXT_EVIDENCE_ONLY_V1")
        }
    }
}

extension JimuPhotoCalibrationTests {
    func testSubmissionRejectsForgedBasisFieldsEvenWithUnchangedRevision() throws {
        try withStore { repo, store, bytes in
            let shown = try prepared(repo, store, bytes)
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JimuInspectorCoding.encode(shown.basis)) as? [String: Any])
            let mutations: [(String, Any)] = [("observationID", "wrong-observation"),
                ("inputSHA256", String(repeating: "0", count: 64)),
                ("correctionIDs", ["invented-correction"]), ("policy", NSNull())]
            for (key, value) in mutations {
                var payload = original; payload[key] = value
                let forged = try JimuInspectorCoding.decode(JimuFeedbackBasis.self,
                    from: JSONSerialization.data(withJSONObject: payload))
                let presentation = JimuPhotoPresentation(id: UUID().uuidString,
                    basis: forged, crop: shown.crop, image: shown.image)
                rejects("stale_photo_presentation") {
                    _ = try store.recordJimuPhotoFeedback(presentation: presentation,
                        policy: policy, choice: .approve)
                }
            }
            XCTAssertTrue(try repo.jimuFeedback(observationID: shown.crop.observationID).isEmpty)
        }
    }
}
