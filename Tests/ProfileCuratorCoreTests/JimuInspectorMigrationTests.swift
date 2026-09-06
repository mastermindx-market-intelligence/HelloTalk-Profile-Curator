import Foundation
import XCTest
@preconcurrency import GRDB
@testable import ProfileCuratorCore

final class JimuInspectorMigrationTests: XCTestCase {
    func testImmutableHistoryUsesExistingRepositoryDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try ProfileRepository(databasePath: directory.appendingPathComponent("curator.sqlite").path)
        let verification = try DatabaseQueue(path: repository.databasePath)
        try verification.read { database in
            XCTAssertTrue(try database.tableExists("profiles"), "Legacy repository remains the owner")
            XCTAssertTrue(try database.tableExists("profile_observations"), "W1 immutable observations are missing")
            XCTAssertTrue(try database.tableExists("observation_corrections"), "W1 append-only corrections are missing")
            XCTAssertTrue(try database.tableExists("preference_feedback"), "W1 scope-separated feedback is missing")
        }
    }
}
