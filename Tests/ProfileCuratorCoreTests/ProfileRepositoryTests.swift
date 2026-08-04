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

    func testProfileMetadataPersistsMergesAndBecomesSearchable() throws {
        let context = try temporaryRepository()
        let first = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@signals",
            age: 20,
            gender: .female,
            mbti: .entp,
            location: NormalizedLocation(
                rawText: "Canada",
                city: nil,
                province: nil,
                country: "Canada",
                tier: 1,
                score: 100,
                confidence: 0.95
            ),
            bio: "I enjoy learning languages.",
            hobbies: ["Psychology", "Tennis"],
            education: "International Student",
            occupation: "Student"
        ))
        let merged = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@signals",
            bio: "Short",
            hobbies: ["tennis", "Traveling"]
        ))

        XCTAssertEqual(merged.id, first.id)
        XCTAssertEqual(merged.countryNormalized, "Canada")
        XCTAssertEqual(merged.bio, "I enjoy learning languages.")
        XCTAssertEqual(merged.hobbies, ["Psychology", "Tennis", "Traveling"])
        XCTAssertEqual(merged.education, "International Student")
        XCTAssertEqual(merged.occupation, "Student")
        XCTAssertGreaterThan(try XCTUnwrap(merged.profileSignalsScore), 85)
        XCTAssertEqual(try context.repository.page(ProfileQuery(search: "psychology")).totalCount, 1)
        XCTAssertEqual(try context.repository.page(ProfileQuery(city: "Canada")).totalCount, 1)
        XCTAssertEqual(try context.repository.page(ProfileQuery(secondaryHighPriorityOnly: true)).totalCount, 1)
    }

    func testPreferredLocationNoMBTIFilterDoesNotIncludeTargetMBTIProfiles() throws {
        let context = try temporaryRepository()
        let shenzhen = NormalizedLocation(
            rawText: "Shenzhen",
            city: "Shenzhen",
            province: "Guangdong",
            country: "China",
            tier: 1,
            score: 100,
            confidence: 0.95
        )
        _ = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@exception",
            age: 20,
            gender: .female,
            location: shenzhen
        ))
        _ = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@target",
            age: 20,
            gender: .female,
            mbti: .infj,
            location: shenzhen
        ))

        let page = try context.repository.page(ProfileQuery(preferredLocationNoMBTIOnly: true))

        XCTAssertEqual(page.records.map(\.usernameNormalized), ["@exception"])
    }

    func testBalancedFinalizationCanReplaceFirstTenRetentionFlags() throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(usernameRaw: "@retention", age: 19, gender: .female, mbti: .infj))
        let first = MediaRecord(
            id: UUID().uuidString,
            profileID: profile.id,
            kind: MediaKind.pfp.rawValue,
            filePath: "/tmp/first.png",
            perceptualHash: "first",
            sourceSequence: 1,
            faceCount: 1,
            largestFaceRatio: 0.2,
            faceCaptureQuality: 0.8,
            usableFace: true,
            retained: true,
            createdAt: Date()
        )
        var second = first
        second.id = UUID().uuidString
        second.kind = MediaKind.moment.rawValue
        second.filePath = "/tmp/second.png"
        second.perceptualHash = "second"
        second.sourceSequence = 2
        XCTAssertTrue(try context.repository.insertMedia(first))
        XCTAssertTrue(try context.repository.insertMedia(second))

        try context.repository.setRetainedMedia(profileID: profile.id, mediaIDs: [second.id])
        let media = try context.repository.media(profileID: profile.id)
        XCTAssertEqual(media.first(where: { $0.id == first.id })?.retained, false)
        XCTAssertEqual(media.first(where: { $0.id == second.id })?.retained, true)
    }

    private func temporaryRepository() throws -> (repository: ProfileRepository, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try ProfileRepository(databasePath: root.appendingPathComponent("test.sqlite").path), root)
    }
}
