import XCTest
@testable import ProfileCuratorCore

final class RecommendationAgeParserTests: XCTestCase {
    private let bounds = NormalizedRect(x: 0.1, y: 0.6, width: 0.12, height: 0.04)

    func testAcceptsOnlyAdultTargetRange() {
        let observations = [17, 18, 19, 20, 21, 22].map {
            OCRObservation(text: "Age \($0)", confidence: 0.98, bounds: bounds)
        }

        let candidates = RecommendationAgeParser().candidates(in: observations)

        XCTAssertEqual(candidates.map(\.age), [18, 19, 20, 21])
    }

    func testRejectsLowConfidenceAge() {
        let observations = [OCRObservation(text: "21", confidence: 0.4, bounds: bounds)]
        XCTAssertTrue(RecommendationAgeParser().candidates(in: observations).isEmpty)
    }

    func testDoesNotExtractAgeFromUsernameOrUnrelatedNumber() {
        let observations = [
            OCRObservation(text: "@a_eira19", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "571d Joined", confidence: 0.99, bounds: bounds)
        ]

        XCTAssertTrue(RecommendationAgeParser().candidates(in: observations).isEmpty)
    }

    func testObservedFemaleBadgeArtifactCanBeRejectedAsOutOfRange() {
        let observations = [OCRObservation(text: "922", confidence: 0.95, bounds: bounds)]
        let parser = RecommendationAgeParser()

        XCTAssertEqual(parser.allAges(in: observations).map(\.age), [22])
        XCTAssertTrue(parser.allAges(in: observations).first?.usedBadgeArtifactCorrection == true)
        XCTAssertTrue(parser.candidates(in: observations).isEmpty)
    }
}
