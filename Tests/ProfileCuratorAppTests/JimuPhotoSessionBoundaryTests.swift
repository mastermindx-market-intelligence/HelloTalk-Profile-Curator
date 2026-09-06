import AppKit
import Foundation
import CryptoKit
import XCTest
import ProfileCuratorCore
@testable import ProfileCuratorApp

final class JimuPhotoSessionBoundaryTests: XCTestCase {}

extension JimuPhotoSessionBoundaryTests {
    @MainActor
    private static func importCalibrationFixture(model: JimuOfflineInspectorModel, root: URL, suffix: String) throws -> String {
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8,
            bytesPerRow: 2560, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        context.setFillColor(CGColor(red: 0.12, green: suffix == "a" ? 0.38 : 0.25, blue: 0.48, alpha: 1))
        context.fill(CGRect(x: 160, y: 40, width: 320, height: 320))
        context.setFillColor(CGColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 1))
        if suffix == "a" { context.fillEllipse(in: CGRect(x: 230, y: 120, width: 170, height: 170)) }
        else { context.fill(CGRect(x: 230, y: 120, width: 170, height: 170)) }
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let file = root.appendingPathComponent("synthetic-photo-\(suffix).png"); try bytes.write(to: file)
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: sourceRoot.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))) as? [String: Any])
        let id = "synthetic-calibration-\(suffix)"
        document["observation_id"] = id; document["encounter_id"] = id; document["frame_sha256"] = hash
        model.importObservation(try JSONSerialization.data(withJSONObject: document))
        model.importSourceFile(file)
        XCTAssertNil(model.errorCode)
        return id
    }
}

extension JimuPhotoSessionBoundaryTests {
    func testPolicyChangeClearsAnActivePhotoPresentationBeforeAnotherJudgment() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let repo = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
            let model = JimuOfflineInspectorModel(repository: repo)
            let policy = JimuReplayPolicy(policyID: "synthetic-calibration", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
            model.loadPolicy(try JSONEncoder().encode(policy))
            let id = try Self.importCalibrationFixture(model: model, root: root, suffix: "a")
            model.savePhotoCrop(JimuPhotoRect(x: 160, y: 40, width: 320, height: 320), confirmed: true)
            model.beginPhotoCalibration(paired: false, observationIDs: [id])
            XCTAssertNotNil(model.photoLeft)
            model.loadPolicy(try JSONEncoder().encode(JimuReplayPolicy(policyID: "changed", minimumAge: 30, maximumAge: 40, allowedRightsScopeIDs: [])))
            XCTAssertNil(model.photoLeft, "Changed policy must not leave an old eligible photo onscreen")
            XCTAssertNil(model.photoRight)
            model.recordPhotoLabel(.approve)
            XCTAssertEqual(model.errorCode, "photo_session_required")
            XCTAssertTrue(try repo.jimuFeedback(observationID: id).isEmpty)
        }
    }
}

extension JimuPhotoSessionBoundaryTests {
    func testInvalidPhotoDeckCannotBeAdvancedAfterSelectionError() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let repo = try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path)
            let model = JimuOfflineInspectorModel(repository: repo)
            model.loadPolicy(try JSONEncoder().encode(JimuReplayPolicy(policyID: "synthetic", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])))
            let id = try Self.importCalibrationFixture(model: model, root: root, suffix: "a")
            model.savePhotoCrop(JimuPhotoRect(x: 160, y: 40, width: 320, height: 320), confirmed: true)
            model.beginPhotoCalibration(paired: false, observationIDs: [id, id])
            XCTAssertEqual(model.errorCode, "photo_selection_conflict")
            model.nextPhotoCalibration()
            XCTAssertNil(model.photoLeft, "An invalid deck must not become usable through Next")
            XCTAssertNil(model.photoRight)
            XCTAssertTrue(try repo.jimuFeedback(observationID: id).isEmpty)
            model.stopPhotoCalibration()
        }
    }
}
