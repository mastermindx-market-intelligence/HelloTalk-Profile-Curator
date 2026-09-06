import AppKit
import Foundation
import SwiftUI
import XCTest
import ProfileCuratorCore
@testable import ProfileCuratorApp

// Test-only host: render the real native view at the requested size even when
// the CI virtual display is smaller. Production windows keep standard AppKit constraints.
@MainActor
private final class JimuProofWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

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
            try Self.render(model: model, name: "01-original-and-label.png", height: 900)
            model.correct(fieldID: "field-bio-001", state: "PRESENT", valueJSON: "Music.", reason: "Shorter manual transcript correction", valueIsText: true)
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
            XCTAssertTrue(restarted.notice.contains("loaded"))
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
            try Self.render(model: restarted, name: "02-restarted-evidence.png", height: 900)
            try Self.render(model: restarted, name: "03-history-and-feedback.png", height: 900, scrollToBottom: true)
            try Self.render(model: restarted, name: "04-compact-window.png", height: 720, width: 1_050)
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

    func testNativePairwiseConsumerKeepsBothObservationsAndScope() async throws {
        try await MainActor.run {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = JimuOfflineInspectorModel(repository: try ProfileRepository(databasePath: root.appendingPathComponent("curator.sqlite").path))
            let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let data = try Data(contentsOf: sourceRoot.appendingPathComponent("fixtures/jimu/synthetic/profile.json"))
            let policy = JimuReplayPolicy(policyID: "synthetic-review-v1", minimumAge: 25, maximumAge: 40, allowedRightsScopeIDs: [])
            model.loadPolicy(try JSONEncoder().encode(policy))
            model.importObservation(data)
            let firstID = try XCTUnwrap(model.snapshot?.id)
            var second = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            second["observation_id"] = "obs-synthetic-comparison"
            second["encounter_id"] = "enc-synthetic-comparison"
            model.importObservation(try JSONSerialization.data(withJSONObject: second, options: [.sortedKeys]))
            XCTAssertNil(model.errorCode)
            model.compare(with: firstID)
            XCTAssertNotNil(model.comparison)
            model.label(.neither, scope: .fullProfile, paired: true)
            XCTAssertNil(model.errorCode)
            XCTAssertEqual(model.feedback.count, 1)
            XCTAssertEqual(model.feedback.first?.comparison?.observationID, firstID)
            XCTAssertEqual(model.feedback.first?.scope, .fullProfile)
            XCTAssertEqual(model.feedback.first?.basis.presentationKind, "TEXT_EVIDENCE_ONLY_V1")
            try Self.render(model: model, name: "05-pairwise-history.png", height: 900, scrollToBottom: true)
        }
    }

    @MainActor
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor
    private static func render(model: JimuOfflineInspectorModel, name: String, height: CGFloat, width: CGFloat = 1_280, scrollToBottom: Bool = false) throws {
        guard let directory = ProcessInfo.processInfo.environment["JIMU_UI_PROOF_DIR"] else { return }
        _ = NSApplication.shared
        let view = NSHostingView(rootView: JimuOfflineInspectorView(model: model))
        view.sizingOptions = []
        view.autoresizingMask = [.width, .height]
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let window = JimuProofWindow(contentRect: rect, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.setContentSize(rect.size)
        view.frame = rect
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        let end = Date().addingTimeInterval(0.35)
        while Date() < end { _ = RunLoop.current.run(mode: .default, before: end) }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        XCTAssertEqual(view.bounds.width, width, accuracy: 1)
        XCTAssertEqual(view.bounds.height, height, accuracy: 1)
        var scrollOffset: CGFloat = 0
        if scrollToBottom {
            let candidates = scrollViews(in: view).filter { ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 30 }
            let scroll = try XCTUnwrap(candidates.max { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) })
            let document = try XCTUnwrap(scroll.documentView)
            let target = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? target : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            scrollOffset = scroll.contentView.bounds.origin.y
            if document.isFlipped { XCTAssertGreaterThan(scrollOffset, 0) }
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent(name))
        let metadata: [String: Any] = ["logical_width": view.bounds.width, "logical_height": view.bounds.height,
            "pixel_width": bitmap.pixelsWide, "pixel_height": bitmap.pixelsHigh, "scroll_to_bottom": scrollToBottom,
            "scroll_offset_y": scrollOffset, "observation_id": model.snapshot?.id ?? "none",
            "corrections": model.snapshot?.corrections.count ?? 0, "labels": model.feedback.count,
            "proof_kind": "native_view_and_viewmodel_restart_not_external_clickthrough"]
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.appendingPathComponent(name + ".json"))
        window.orderOut(nil)
        XCTAssertGreaterThan(png.count, 10_000, "Native render should contain the actual evidence interface")
    }
}
