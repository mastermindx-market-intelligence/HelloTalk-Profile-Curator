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

    func testGuangzhouUsesTierTwo() {
        let result = LocationNormalizer().normalize("Guangzhou, Guangdong")

        XCTAssertEqual(result.city, "Guangzhou")
        XCTAssertEqual(result.tier, 2)
        XCTAssertEqual(result.score, 85)
    }

    func testRequestedTierThreeCitiesAndProvince() {
        for value in ["Zhuhai", "Foshan", "Dongguan", "Hainan", "Changchun"] {
            let result = LocationNormalizer().normalize(value)
            XCTAssertEqual(result.tier, 3, value)
            XCTAssertEqual(result.score, 70, value)
        }
    }

    func testRequestedLastTierCities() {
        for value in ["Shantou", "Wuxi", "Linyi"] {
            let result = LocationNormalizer().normalize(value)
            XCTAssertEqual(result.tier, 5, value)
            XCTAssertEqual(result.score, 30, value)
        }
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

    func testExpandedTierTwoCitiesAllowPreferredNoMBTIException() {
        for value in ["Beijing", "上海", "Chengdu", "重庆", "Hangzhou", "苏州"] {
            let result = LocationNormalizer().normalize(value)
            XCTAssertEqual(result.tier, 2, value)
            XCTAssertEqual(result.score, 85, value)
        }
    }

    func testNewTierThreeCitiesPassGeneralLocationGate() {
        let expected = [
            "Wuhan": "Wuhan",
            "Ninbo": "Ningbo",
            "南京": "Nanjing",
            "青岛": "Qingdao",
            "郑州": "Zhengzhou"
        ]
        for (input, city) in expected {
            let result = LocationNormalizer().normalize(input)
            XCTAssertEqual(result.city, city, input)
            XCTAssertEqual(result.tier, 3, input)
            XCTAssertEqual(result.score, 70, input)
        }
    }

    func testUnknownAndMissingRemainDistinct() {
        let knownButUnmapped = LocationNormalizer().normalize("Jinan")
        let missing = LocationNormalizer().normalize("   ")

        XCTAssertEqual(knownButUnmapped.tier, 5)
        XCTAssertEqual(knownButUnmapped.score, 30)
        XCTAssertEqual(missing.tier, 6)
        XCTAssertEqual(missing.score, 10)
    }
}
