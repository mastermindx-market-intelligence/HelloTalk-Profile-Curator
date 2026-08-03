import XCTest
@testable import ProfileCuratorCore

final class MBTIParserTests: XCTestCase {
    private let bounds = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)

    func testFindsPrimaryAndSecondaryTargetsExactly() {
        let observations = [
            OCRObservation(text: "Personality: INFJ", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "Also shown: entp", confidence: 0.97, bounds: bounds)
        ]

        let matches = MBTIParser().matches(in: observations)

        XCTAssertEqual(matches.map(\.type), [.infj, .entp])
        XCTAssertEqual(matches.map(\.type.group), [.primary, .secondary])
    }

    func testDoesNotFuzzyConvertDifferentOrInvalidTypes() {
        let observations = [
            OCRObservation(text: "INFP", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "INFX", confidence: 0.99, bounds: bounds),
            OCRObservation(text: "INFJOURNAL", confidence: 0.99, bounds: bounds)
        ]

        let matches = MBTIParser().matches(in: observations)

        XCTAssertEqual(matches.map(\.type), [.infp])
        XCTAssertEqual(MBTIParser().firstTarget(in: observations)?.type, .infp)
    }

    func testRejectsLowConfidenceOCR() {
        let observations = [
            OCRObservation(text: "INTJ", confidence: 0.51, bounds: bounds)
        ]

        XCTAssertTrue(MBTIParser().matches(in: observations).isEmpty)
    }

    func testRecognizesNonTargetWithoutRoutingItToAGroup() {
        let observations = [
            OCRObservation(text: "ENTJ", confidence: 0.99, bounds: bounds)
        ]

        let match = MBTIParser().matches(in: observations).first
        XCTAssertEqual(match?.type, .entj)
        XCTAssertNil(match?.type.group)
    }
}
