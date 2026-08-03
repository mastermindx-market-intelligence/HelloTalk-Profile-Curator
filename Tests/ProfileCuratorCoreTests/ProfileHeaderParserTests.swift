import XCTest
@testable import ProfileCuratorCore

final class ProfileHeaderParserTests: XCTestCase {
    private let bounds = NormalizedRect(x: 0.2, y: 0.3, width: 0.1, height: 0.04)

    func testExtractsAgeFromObservedFemaleBadgeOCRArtifact() {
        let observations = [OCRObservation(text: "918", confidence: 0.87, bounds: bounds)]
        let match = ProfileHeaderParser().bestAge(in: observations)

        XCTAssertEqual(match?.age, 18)
        XCTAssertEqual(match?.usedBadgeArtifactCorrection, true)
    }

    func testExtractsNonEligibleObservedBadgeAge() {
        let observations = [OCRObservation(text: "925", confidence: 0.91, bounds: bounds)]
        XCTAssertEqual(ProfileHeaderParser().bestAge(in: observations)?.age, 25)
    }

    func testRejectsUsernameSuffixAndStatusBarNumbers() {
        let observations = [
            OCRObservation(text: "@a_eira19", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "3:52", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "304", confidence: 0.99, bounds: bounds)
        ]

        XCTAssertNil(ProfileHeaderParser().bestAge(in: observations))
    }

    func testKnownAIAnchorCorrectionIsNarrow() {
        let matcher = OCRAnchorMatcher()
        XCTAssertTrue(matcher.contains(anchor: "AI Photo Gift", in: "Al Photo Gift · Avatar Effect"))
        XCTAssertFalse(matcher.contains(anchor: "AI Photo Gift", in: "Photo Gift"))
    }
}
