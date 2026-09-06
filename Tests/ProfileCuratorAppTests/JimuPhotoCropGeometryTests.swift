import XCTest
import CoreGraphics
import ProfileCuratorCore
@testable import ProfileCuratorApp

final class JimuPhotoCropGeometryTests: XCTestCase {
    func testAspectFitUsesCenteredLetterbox() throws {
        let box = try XCTUnwrap(JimuPhotoCropGeometry.imageRect(width: 640, height: 400,
            in: CGSize(width: 1000, height: 400)))
        XCTAssertEqual(box, CGRect(x: 180, y: 0, width: 640, height: 400))
    }
    func testForwardAndReverseDragYieldTheSameTopLeftPixelRegion() {
        let size = CGSize(width: 1000, height: 400)
        for points in [(CGPoint(x: 340, y: 40), CGPoint(x: 660, y: 360)),
                       (CGPoint(x: 660, y: 360), CGPoint(x: 340, y: 40))] {
            XCTAssertEqual(JimuPhotoCropGeometry.selection(from: points.0, to: points.1,
                width: 640, height: 400, in: size), JimuPhotoRect(x: 160, y: 40, width: 320, height: 320))
        }
    }
    func testScaledDragMapsToSourcePixelsNotScreenPoints() {
        XCTAssertEqual(JimuPhotoCropGeometry.selection(from: CGPoint(x: 100, y: 50),
            to: CGPoint(x: 200, y: 150), width: 640, height: 400,
            in: CGSize(width: 320, height: 200)), JimuPhotoRect(x: 200, y: 100, width: 200, height: 200))
    }
    func testRejectsLetterboxStartsAndInvalidGeometry() {
        let size = CGSize(width: 1000, height: 400)
        XCTAssertNil(JimuPhotoCropGeometry.selection(from: .zero, to: CGPoint(x: 500, y: 200),
            width: 640, height: 400, in: size))
        XCTAssertNil(JimuPhotoCropGeometry.selection(from: CGPoint(x: 300, y: 100),
            to: CGPoint(x: 300, y: 100), width: 640, height: 400, in: size))
        XCTAssertNil(JimuPhotoCropGeometry.imageRect(width: 0, height: 400, in: size))
        XCTAssertNil(JimuPhotoCropGeometry.imageRect(width: 640, height: 400,
            in: CGSize(width: CGFloat.infinity, height: 400)))
        XCTAssertNil(JimuPhotoCropGeometry.selection(from: CGPoint(x: CGFloat.nan, y: 0),
            to: .zero, width: 640, height: 400, in: size))
    }
    func testEndOutsideImageClampsWithoutIncludingLetterbox() {
        XCTAssertEqual(JimuPhotoCropGeometry.selection(from: CGPoint(x: 500, y: 200),
            to: CGPoint(x: 1000, y: 900), width: 640, height: 400,
            in: CGSize(width: 1000, height: 400)), JimuPhotoRect(x: 320, y: 200, width: 320, height: 200))
    }
}
