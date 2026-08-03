import Foundation
import XCTest
@testable import ProfileCuratorCore

final class NavigationEventLogTests: XCTestCase {
    func testStoreAppendsOneJSONEventPerLine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("events.jsonl")
        let store = NavigationEventLogStore(fileURL: fileURL)
        try await store.append(NavigationEvent(kind: .observation, state: .profileTop, summary: "first"))
        try await store.append(NavigationEvent(kind: .transition, state: .evaluateMBTI, summary: "second"))

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("first"))
        XCTAssertTrue(lines[1].contains("second"))
    }
}
