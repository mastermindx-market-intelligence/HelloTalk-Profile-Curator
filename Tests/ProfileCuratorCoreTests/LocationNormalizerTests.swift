import XCTest
@testable import ProfileCuratorCore

final class LocationNormalizerTests: XCTestCase {
    func testShenzhenHasTopPriority() {
        let result = LocationNormalizer().normalize("Current city: 深圳 Shenzhen")

        XCTAssertEqual(result.city, "Shenzhen")
        XCTAssertEqual(result.province, "Guangdong")
        XCTAssertEqual(result.tier, 1)
        XCTAssertEqual(result.score, 100)
    }

    func testOtherGuangdongCityUsesTierTwo() {
        let result = LocationNormalizer().normalize("Guangzhou, Guangdong")

        XCTAssertEqual(result.city, "Guangzhou")
        XCTAssertEqual(result.tier, 2)
        XCTAssertEqual(result.score, 85)
    }

    func testPreferredForeignCountriesShareTopLocationScore() {
        for value in ["United States", "Australia", "UK", "Canada", "美国"] {
            let result = LocationNormalizer().normalize("Country: \(value)")
            XCTAssertEqual(result.tier, 1, value)
            XCTAssertEqual(result.score, 100, value)
            XCTAssertNotNil(result.country, value)
        }
    }

    func testProvinceOnlyUsesTierTwo() {
        let result = LocationNormalizer().normalize("广东省")

        XCTAssertNil(result.city)
        XCTAssertEqual(result.province, "Guangdong")
        XCTAssertEqual(result.tier, 2)
    }

    func testUnknownAndMissingRemainDistinct() {
        let knownButUnmapped = LocationNormalizer().normalize("Qingdao")
        let missing = LocationNormalizer().normalize("   ")

        XCTAssertEqual(knownButUnmapped.tier, 5)
        XCTAssertEqual(knownButUnmapped.score, 30)
        XCTAssertEqual(missing.tier, 6)
        XCTAssertEqual(missing.score, 10)
    }
}
