import AppKit
import Foundation
import SwiftUI
import XCTest
import ProfileCuratorCore
@testable import ProfileCuratorApp

final class JimuInspectorNativeViewTests: XCTestCase {
    func testNativeConsumerImportsCorrectsAndRecoversHistoryAfterRestart() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let databasePath = root.appendingPathComponent("curator.sqlite").path
            let model = JimuOfflineInspectorModel(repository: try ProfileRepository(databasePath: databasePath))
            let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let data = try Data(contentsOf: sourceRoot.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))
            let policy = JimuReplayPolicy(policyID: "synthetic-review-v1", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
            model.loadPolicy(try JSONEncoder().encode(policy))
            XCTAssertNil(model.errorCode)
            model.importObservation(data)
            XCTAssertNil(model.errorCode)
            let imported = try XCTUnwrap(model.snapshot)
            XCTAssertTrue(imported.preferenceLabelsAllowed)
            model.label(.approve, scope: .fullProfile)
            XCTAssertNil(model.errorCode)
            XCTAssertEqual(model.feedback.count, 1)
            let originalLabel = try XCTUnwrap(model.feedback.first)
            try Self.render(model: model, name: "01-original-and-label.png", height: 1_500)
            model.correct(fieldID: "field-bio-001", state: "PRESENT", valueJSON: "\"Music.\"", reason: "Shorter manual transcript correction")
            XCTAssertNil(model.errorCode)
            XCTAssertEqual(model.snapshot?.corrections.count, 1)
            model.label(.hold, scope: .scarceAction, context: "Attention capacity full; offline recommendation only")
            XCTAssertNil(model.errorCode)
            model.label(.approve, scope: .visualOnly)
            XCTAssertEqual(model.errorCode, "visual_evidence_unavailable")
            model.select(imported.id)

            let restarted = JimuOfflineInspectorModel(repository: try ProfileRepository(databasePath: databasePath))
            XCTAssertEqual(restarted.policy?.policyID, policy.policyID)
            restarted.select(imported.id)
            XCTAssertNil(restarted.errorCode)
            let recovered = try XCTUnwrap(restarted.snapshot)
            XCTAssertEqual(recovered.observation.rawData, data)
            XCTAssertEqual(recovered.effectiveFields.first { $0.name == "bio" }?.value, .string("Music."))
            XCTAssertEqual(recovered.report.fields.first { $0.name == "bio" }?.value, .string("I enjoy hiking and live music."))
            XCTAssertEqual(restarted.feedback.count, 2)
            XCTAssertEqual(restarted.feedback.first?.basis.revision, originalLabel.basis.revision)
            XCTAssertEqual(restarted.feedback.first?.basis.presentationKind, "TEXT_EVIDENCE_ONLY_V1")
            XCTAssertEqual(restarted.feedback.first?.basis.modelScoresVisible, false)
            XCTAssertEqual(recovered.report.enabledActions, [])
            XCTAssertEqual(recovered.report.engagementState, "DISABLED_OFFLINE")
            try Self.render(model: restarted, name: "02-restarted-history.png", height: 1_800)
            try Self.render(model: restarted, name: "03-standard-window.png", height: 900)
        }
    }

    func testInvalidPolicyAndMalformedFileDoNotDisplayOrPersistProfile() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = JimuOfflineInspectorModel(repository: try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path))
            model.loadPolicy(Data("{\"policy_id\":\"bad\",\"minimum_age\":17,\"maximum_age\":24,\"allowed_rights_scope_ids\":[]}".utf8))
            XCTAssertEqual(model.errorCode, "invalid_policy")
            XCTAssertNil(model.policy)
            model.importObservation(Data("{\"private\":\"do-not-echo\"}".utf8))
            XCTAssertNotNil(model.errorCode)
            XCTAssertFalse(model.errorCode?.contains("do-not-echo") ?? true)
            XCTAssertNil(model.snapshot)
            XCTAssertTrue(model.observations.isEmpty)
        }
    }

    @MainActor
    private static func render(model: JimuOfflineInspectorModel, name: String, height: CGFloat) throws {
        guard let directory = ProcessInfo.processInfo.environment["JIMU_UI_PROOF_DIR"] else { return }
        _ = NSApplication.shared
        let view = NSHostingView(rootView: JimuOfflineInspectorView(model: model))
        let rect = NSRect(x: 0, y: 0, width: 1_280, height: height)
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.frame = rect
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(0.35)
        while Date() < end { _ = RunLoop.current.run(mode: .default, before: end) }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent(name))
        window.orderOut(nil)
        XCTAssertGreaterThan(png.count, 10_000, "Native render should contain the actual evidence interface")
    }
}
