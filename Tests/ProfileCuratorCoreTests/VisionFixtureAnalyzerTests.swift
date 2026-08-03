import AppKit
import XCTest
@testable import ProfileCuratorCore

final class VisionFixtureAnalyzerTests: XCTestCase {
    func testSyntheticScreenshotRunsThroughVisionAndExactParsers() throws {
        let image = try makeSyntheticProfileImage()
        let analysis = try VisionFixtureAnalyzer().analyze(image)
        let combinedText = analysis.text.map(\.text).joined(separator: " ")

        XCTAssertTrue(combinedText.localizedCaseInsensitiveContains("Personal Info"))
        XCTAssertEqual(MBTIParser().firstTarget(in: analysis.text)?.type, .infj)
        XCTAssertEqual(LocationNormalizer().normalize(combinedText).city, "Shenzhen")
    }

    private func makeSyntheticProfileImage() throws -> CGImage {
        let width = 1_200
        let height = 800
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw VisionFixtureAnalyzerError.noImage
        }

        let context = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 54, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "Personal Info").draw(at: NSPoint(x: 80, y: 620), withAttributes: attributes)
        NSString(string: "Personality  INFJ").draw(at: NSPoint(x: 80, y: 500), withAttributes: attributes)
        NSString(string: "Location  Shenzhen 深圳").draw(at: NSPoint(x: 80, y: 380), withAttributes: attributes)
        NSString(string: "Suggested for You").draw(at: NSPoint(x: 80, y: 180), withAttributes: attributes)

        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let image = representation.cgImage else {
            throw VisionFixtureAnalyzerError.noImage
        }
        return image
    }
}
