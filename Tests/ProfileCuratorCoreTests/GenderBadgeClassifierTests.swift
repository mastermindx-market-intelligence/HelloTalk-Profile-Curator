import CoreGraphics
import XCTest
@testable import ProfileCuratorCore

final class GenderBadgeClassifierTests: XCTestCase {
    private let badgeBounds = NormalizedRect(x: 0.4, y: 0.4, width: 0.12, height: 0.06)

    func testClassifiesSyntheticPinkBadgeAsFemale() throws {
        let image = try makeImage(badgeColor: CGColor(red: 0.92, green: 0.05, blue: 0.56, alpha: 1))
        let ageMatch = ProfileAgeMatch(
            age: 18,
            source: OCRObservation(text: "918", confidence: 0.95, bounds: badgeBounds),
            usedBadgeArtifactCorrection: true
        )

        XCTAssertEqual(GenderBadgeClassifier().classify(image: image, ageMatch: ageMatch).hint, .female)
    }

    func testClassifiesSyntheticBlueBadgeAsMale() throws {
        let image = try makeImage(badgeColor: CGColor(red: 0.05, green: 0.32, blue: 0.95, alpha: 1))
        let ageMatch = ProfileAgeMatch(
            age: 18,
            source: OCRObservation(text: "918", confidence: 0.95, bounds: badgeBounds),
            usedBadgeArtifactCorrection: true
        )

        XCTAssertEqual(GenderBadgeClassifier().classify(image: image, ageMatch: ageMatch).hint, .male)
    }

    private func makeImage(badgeColor: CGColor) throws -> CGImage {
        let width = 400
        let height = 800
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw VisionFixtureAnalyzerError.noImage
        }

        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(badgeColor)
        context.fill(
            CGRect(
                x: badgeBounds.x * Double(width),
                y: (1 - badgeBounds.y - badgeBounds.height) * Double(height),
                width: badgeBounds.width * Double(width),
                height: badgeBounds.height * Double(height)
            )
        )

        guard let image = context.makeImage() else {
            throw VisionFixtureAnalyzerError.noImage
        }
        return image
    }
}
