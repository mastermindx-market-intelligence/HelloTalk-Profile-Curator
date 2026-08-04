import AppKit
import Foundation
import XCTest
@testable import ProfileCuratorCore

final class PrivateFixtureReplayTests: XCTestCase {
    func testEveryAvailablePrivateFixtureManifest() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let privateFixtures = repositoryRoot.appendingPathComponent("fixtures/private", isDirectory: true)
        let harness = FixtureReplayHarness()
        let manifests = try harness.manifestURLs(in: privateFixtures)

        guard !manifests.isEmpty else {
            throw XCTSkip("No private fixture manifests are present on this machine.")
        }

        for manifestURL in manifests {
            let result = try harness.replay(manifestURL: manifestURL)
            XCTAssertTrue(
                result.validationFailures.isEmpty,
                "\(manifestURL.lastPathComponent): \(result.validationFailures.joined(separator: "; "))\nOCR: \(result.combinedOCRText)"
            )
        }
    }

    func testActualProfileFixtureExtractsBioAndHobbies() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent(
            "fixtures/private/personal_info/age25_infp_personal_info.png"
        )
        guard let image = NSImage(contentsOf: fixture),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw XCTSkip("The private profile fixture is unavailable.")
        }

        let analysis = try VisionFixtureAnalyzer().analyze(cgImage)
        let metadata = ProfileMetadataParser().parse(analysis.text)

        XCTAssertTrue(metadata.bio?.contains("international student") == true, analysis.text.map(\.text).joined(separator: " | "))
        XCTAssertTrue(metadata.hobbies.contains(where: { $0.localizedCaseInsensitiveContains("Dancing") }))
    }
}
