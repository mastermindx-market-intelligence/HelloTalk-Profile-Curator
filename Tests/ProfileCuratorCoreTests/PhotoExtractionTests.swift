import CoreGraphics
import XCTest
@testable import ProfileCuratorCore

final class PhotoExtractionTests: XCTestCase {
    func testPFPRegionStopsAboveActionRows() throws {
        let observations = [
            OCRObservation(
                text: "AI Photo Gift",
                confidence: 0.95,
                bounds: NormalizedRect(x: 0.1, y: 0.75, width: 0.3, height: 0.04)
            )
        ]
        let region = try XCTUnwrap(ViewerPhotoRegionDetector().region(for: .pfpViewer, observations: observations))
        XCTAssertLessThan(region.bounds.maxY, 0.75)
        XCTAssertGreaterThan(region.confidence, 0.9)
    }

    func testCropUsesNormalizedTopLeftContract() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 100,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let crop = try XCTUnwrap(WindowPhotoCropper().crop(
            image,
            to: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        ))
        XCTAssertEqual(crop.width, 50)
        XCTAssertEqual(crop.height, 80)
    }

    func testMomentScreensHaveExplicitRecognition() {
        let analysis = FixtureAnalysis(
            imageWidth: 400,
            imageHeight: 800,
            text: [
                OCRObservation(text: "Moments", confidence: 0.95, bounds: NormalizedRect(x: 0.1, y: 0.05, width: 0.2, height: 0.04)),
                OCRObservation(text: "1/5", confidence: 0.95, bounds: NormalizedRect(x: 0.45, y: 0.08, width: 0.1, height: 0.03)),
                OCRObservation(text: "Like", confidence: 0.95, bounds: NormalizedRect(x: 0.7, y: 0.9, width: 0.1, height: 0.03))
            ],
            faces: []
        )
        XCTAssertEqual(NavigationStateDetector().classify(analysis).kind, .momentViewer)
    }
}
