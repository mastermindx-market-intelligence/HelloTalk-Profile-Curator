import XCTest
@testable import ProfileCuratorCore

final class ProfileMetadataParserTests: XCTestCase {
    func testParsesBioHobbiesEducationAndOccupationFromOrderedOCR() {
        let observations = [
            observation("Self Introduction", x: 0.08, y: 0.10),
            observation("Learning languages and meeting new people", x: 0.08, y: 0.15),
            observation("Hobbies", x: 0.08, y: 0.30),
            observation("Psychology", x: 0.35, y: 0.30),
            observation("Tennis", x: 0.55, y: 0.30),
            observation("Traveling, Yoga", x: 0.08, y: 0.36),
            observation("Education", x: 0.08, y: 0.55),
            observation("International Student", x: 0.35, y: 0.55),
            observation("Occupation", x: 0.08, y: 0.70),
            observation("Student", x: 0.35, y: 0.70)
        ]

        let result = ProfileMetadataParser().parse(observations)

        XCTAssertEqual(result.bio, "Learning languages and meeting new people")
        XCTAssertEqual(result.hobbies, ["Psychology", "Tennis", "Traveling", "Yoga"])
        XCTAssertEqual(result.education, "International Student")
        XCTAssertEqual(result.occupation, "Student")
    }

    func testProfileSignalScoringAppliesRequestedEducationExceptions() {
        let scorer = ProfileSignalScorer()

        XCTAssertEqual(scorer.score(hobbies: [], education: "International Student", occupation: nil).education, 100)
        XCTAssertEqual(scorer.score(hobbies: [], education: "Senior High School Student", occupation: nil).education, 75)
        XCTAssertEqual(scorer.score(hobbies: [], education: "Junior High School Student", occupation: nil).education, 40)
        XCTAssertEqual(scorer.score(hobbies: [], education: "University", occupation: nil).education, 80)
        XCTAssertEqual(scorer.score(hobbies: [], education: "某职业技术学院 大专", occupation: nil).education, 20)
        XCTAssertNil(scorer.score(hobbies: [], education: "Tsinghua University", occupation: nil).education)
    }

    func testParsesActualHelloTalkHobbyLabelAndUnlabeledBio() {
        let observations = [
            observation("5 Following 29 Followers 59d Streak 571d Joined", x: 0.08, y: 0.20),
            observation("Hi! I'm Emma. I'm an international student in", x: 0.08, y: 0.26),
            observation("Sydney. I'd love to make friends here!", x: 0.08, y: 0.30),
            observation("About Me", x: 0.08, y: 0.38),
            observation("Interest & Hobbies", x: 0.08, y: 0.58),
            observation("Dancing", x: 0.08, y: 0.64),
            observation("Personal Info", x: 0.08, y: 0.73)
        ]

        let result = ProfileMetadataParser().parse(observations)

        XCTAssertEqual(result.bio, "Hi! I'm Emma. I'm an international student in Sydney. I'd love to make friends here!")
        XCTAssertEqual(result.hobbies, ["Dancing"])
    }

    func testParsesPersonalInfoTileValueAboveItsLabel() {
        let observations = [
            observation("University", x: 0.08, y: 0.50),
            observation("Education", x: 0.08, y: 0.56),
            observation("Operations", x: 0.45, y: 0.50),
            observation("Occupation", x: 0.45, y: 0.56)
        ]

        let result = ProfileMetadataParser().parse(observations)

        XCTAssertEqual(result.education, "University")
        XCTAssertEqual(result.occupation, "Operations")
    }

    func testStrongHobbiesRaiseSignalAndLowOccupationStaysLow() throws {
        let result = ProfileSignalScorer().score(
            hobbies: ["Psychology", "Horseback Riding", "Tennis"],
            education: nil,
            occupation: "Operations"
        )

        XCTAssertGreaterThan(try XCTUnwrap(result.hobbies), 85)
        XCTAssertEqual(result.occupation, 20)
        XCTAssertGreaterThan(try XCTUnwrap(result.combined), 70)
    }

    private func observation(_ text: String, x: Double, y: Double) -> OCRObservation {
        OCRObservation(
            text: text,
            confidence: 0.95,
            bounds: NormalizedRect(x: x, y: y, width: 0.20, height: 0.035)
        )
    }
}
