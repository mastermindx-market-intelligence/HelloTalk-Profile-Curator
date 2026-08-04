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

    func testDisplayNameComesFromHeaderImmediatelyAboveUsernameNotStatusTime() {
        let observations = [
            OCRObservation(text: "1:08", confidence: 0.99, bounds: NormalizedRect(x: 0.08, y: 0.05, width: 0.08, height: 0.03)),
            OCRObservation(text: "lulu", confidence: 0.94, bounds: NormalizedRect(x: 0.06, y: 0.29, width: 0.10, height: 0.035)),
            OCRObservation(text: "@com_tiana143", confidence: 0.96, bounds: NormalizedRect(x: 0.06, y: 0.335, width: 0.24, height: 0.03))
        ]

        XCTAssertEqual(ProfileDisplayNameParser().displayName(in: observations), "lulu")
    }
}
