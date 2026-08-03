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
}
