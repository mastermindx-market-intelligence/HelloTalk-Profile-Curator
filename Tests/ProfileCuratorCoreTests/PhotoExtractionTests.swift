import CoreGraphics
import ImageIO
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
        XCTAssertEqual(region.bounds.minY, 0.19, accuracy: 0.001)
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

    func testLiveMomentViewerWithoutGalleryCounterIsRecognized() {
        let analysis = FixtureAnalysis(
            imageWidth: 420,
            imageHeight: 932,
            text: [
                OCRObservation(text: "LIVE", confidence: 0.95, bounds: NormalizedRect(x: 0.05, y: 0.16, width: 0.1, height: 0.03)),
                OCRObservation(text: "AI", confidence: 0.95, bounds: NormalizedRect(x: 0.68, y: 0.91, width: 0.08, height: 0.03)),
                OCRObservation(text: "Like", confidence: 0.95, bounds: NormalizedRect(x: 0.05, y: 0.91, width: 0.1, height: 0.03))
            ],
            faces: []
        )
        XCTAssertEqual(NavigationStateDetector().classify(analysis).kind, .momentViewer)
        let region = try! XCTUnwrap(ViewerPhotoRegionDetector().region(for: .momentViewer, observations: analysis.text))
        XCTAssertEqual(region.bounds.minY, 0.22, accuracy: 0.001)
        XCTAssertEqual(region.bounds.maxY, 0.795, accuracy: 0.001)
    }

    func testMomentsFeedLikeCommentAnchorsAreRecognized() {
        let analysis = FixtureAnalysis(
            imageWidth: 420,
            imageHeight: 932,
            text: [
                OCRObservation(text: "Moments 11", confidence: 0.95, bounds: NormalizedRect(x: 0.35, y: 0.5, width: 0.2, height: 0.03)),
                OCRObservation(text: "96 Like", confidence: 0.95, bounds: NormalizedRect(x: 0.05, y: 0.55, width: 0.15, height: 0.03)),
                OCRObservation(text: "3 Comment", confidence: 0.95, bounds: NormalizedRect(x: 0.2, y: 0.55, width: 0.18, height: 0.03))
            ],
            faces: []
        )
        XCTAssertEqual(NavigationStateDetector().classify(analysis).kind, .momentsFeed)
    }

    func testMomentsFeedDateDoesNotMimicGalleryCounter() {
        let analysis = FixtureAnalysis(
            imageWidth: 420,
            imageHeight: 932,
            text: [
                OCRObservation(text: "Moments 8", confidence: 0.95, bounds: NormalizedRect(x: 0.35, y: 0.39, width: 0.2, height: 0.03)),
                OCRObservation(text: "121 Like", confidence: 0.95, bounds: NormalizedRect(x: 0.05, y: 0.43, width: 0.15, height: 0.03)),
                OCRObservation(text: "7 Comment", confidence: 0.95, bounds: NormalizedRect(x: 0.2, y: 0.43, width: 0.18, height: 0.03)),
                OCRObservation(text: "25/07", confidence: 0.95, bounds: NormalizedRect(x: 0.85, y: 0.51, width: 0.1, height: 0.03))
            ],
            faces: []
        )

        XCTAssertEqual(NavigationStateDetector().classify(analysis).kind, .momentsFeed)
    }

    func testHiddenChromeMomentViewerUsesVisualPaginationFallback() throws {
        let image = try makeHiddenViewerImage(includePagination: true)
        let analysis = FixtureAnalysis(
            imageWidth: image.width,
            imageHeight: image.height,
            text: [OCRObservation(
                text: "6:24",
                confidence: 0.95,
                bounds: NormalizedRect(x: 0.11, y: 0.06, width: 0.1, height: 0.03)
            )],
            faces: []
        )

        XCTAssertEqual(NavigationStateDetector().classify(analysis, image: image).kind, .momentViewer)
    }

    func testDarkViewerLikeFrameWithoutPaginationFailsClosed() throws {
        let image = try makeHiddenViewerImage(includePagination: false)
        let analysis = FixtureAnalysis(imageWidth: image.width, imageHeight: image.height, text: [], faces: [])

        XCTAssertEqual(NavigationStateDetector().classify(analysis, image: image).kind, .unknown)
    }

    func testPrivateHiddenChromeViewerWhenFixtureIsAvailable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot
            .appendingPathComponent("fixtures/private/live_regression/moment_viewer_hidden_chrome.jpg")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Private hidden-chrome viewer fixture is not present")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(fixture as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let analysis = try VisionFixtureAnalyzer().analyze(image)

        XCTAssertEqual(NavigationStateDetector().classify(analysis, image: image).kind, .momentViewer)
    }

    private func makeHiddenViewerImage(includePagination: Bool) throws -> CGImage {
        let width = 420
        let height = 932
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 0.01, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.72, green: 0.48, blue: 0.22, alpha: 1))
        context.fill(CGRect(x: 24, y: 325, width: 372, height: 305))
        if includePagination {
            for index in 0..<7 {
                context.setFillColor(CGColor(gray: index == 0 ? 0.95 : 0.38, alpha: 1))
                context.fillEllipse(in: CGRect(
                    x: 145 + index * 18,
                    y: 818,
                    width: 7,
                    height: 7
                ))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }
}
