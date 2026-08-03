import Foundation
import XCTest
@testable import ProfileCuratorCore

final class CalibrationStoreTests: XCTestCase {
    func testCalibrationRoundTripPreservesNormalizedMarks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileCuratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = CalibrationStore(fileURL: directory.appendingPathComponent("calibration.json"))
        let expectedMark = CalibrationMark(
            context: .momentViewer,
            kind: .excludeSayHi,
            bounds: NormalizedRect(x: 0.1, y: 0.75, width: 0.3, height: 0.08),
            confirmed: true
        )
        let profile = CalibrationProfile(
            referencePixelWidth: 1_290,
            referencePixelHeight: 2_796,
            marks: [expectedMark]
        )

        try store.save(profile)
        let restored = try XCTUnwrap(store.load())

        XCTAssertEqual(restored.schemaVersion, 1)
        XCTAssertEqual(restored.referencePixelWidth, 1_290)
        XCTAssertEqual(restored.referencePixelHeight, 2_796)
        XCTAssertEqual(restored.marks, [expectedMark])
        XCTAssertEqual(restored.marks.first?.context, .momentViewer)
    }
}
