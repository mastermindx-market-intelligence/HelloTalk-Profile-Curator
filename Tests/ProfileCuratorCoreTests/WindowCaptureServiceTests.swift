import CoreGraphics
import XCTest
@testable import ProfileCuratorCore

final class WindowCaptureServiceTests: XCTestCase {
    func testCaptureUsesWindowPointDimensionsWithoutRetinaPadding() {
        let size = WindowCaptureService.targetPixelSize(
            for: CGRect(x: 681, y: 122, width: 418, height: 920)
        )

        XCTAssertEqual(size.width, 418)
        XCTAssertEqual(size.height, 920)
    }

    func testCaptureDimensionsRoundFractionalWindowGeometry() {
        let size = WindowCaptureService.targetPixelSize(
            for: CGRect(x: 0, y: 0, width: 417.6, height: 919.6)
        )

        XCTAssertEqual(size.width, 418)
        XCTAssertEqual(size.height, 920)
    }
}
