import Foundation
import XCTest
@testable import ProfileCuratorCore

final class ProfileRepositoryTests: XCTestCase {
    func testUsernameUpsertMergesAndPreservesManualStatus() throws {
        let context = try temporaryRepository()
        let first = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@Example",
            age: 19,
            gender: .female,
            mbti: .infj
        ))
        try context.repository.updateStatus(id: first.id, status: .shortlisted)
        let merged = try context.repository.upsert(ProfileDraft(
            usernameRaw: " @EXAMPLE ",
            displayName: "Example",
            gender: .unknown
        ))

        XCTAssertEqual(merged.id, first.id)
        XCTAssertEqual(merged.visitCount, 2)
        XCTAssertEqual(merged.age, 19)
        XCTAssertEqual(merged.typedStatus, .shortlisted)
        XCTAssertEqual(try context.repository.page(ProfileQuery()).totalCount, 1)
    }

    func testComposedFiltersAndPaginationRunInDatabase() throws {
        let context = try temporaryRepository()
        for index in 0..<25 {
            _ = try context.repository.upsert(ProfileDraft(
                usernameRaw: "@user\(index)",
                age: 18 + index % 4,
                gender: .female,
                mbti: index.isMultiple(of: 2) ? .infj : .entp
            ))
        }
        let page = try context.repository.page(ProfileQuery(
            search: "user",
            groups: [.primary],
            minimumAge: 18,
            maximumAge: 21,
            page: 0,
            pageSize: 20
        ))
        XCTAssertEqual(page.totalCount, 13)
        XCTAssertEqual(page.records.count, 13)
        XCTAssertTrue(page.records.allSatisfy { $0.typedGroup == .primary })
    }

    private func temporaryRepository() throws -> (repository: ProfileRepository, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try ProfileRepository(databasePath: root.appendingPathComponent("test.sqlite").path), root)
    }
}
