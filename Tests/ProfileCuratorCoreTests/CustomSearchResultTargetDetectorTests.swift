import XCTest
@testable import ProfileCuratorCore

final class CustomSearchResultTargetDetectorTests: XCTestCase {
    func testBuildsSafeTargetsOnlyForRecognizedTargetLocations() throws {
        let observations = [
            item("Emily", x: 0.23, y: 0.20, width: 0.20),
            item("CN → EN", x: 0.23, y: 0.24, width: 0.18),
            item("Guangzhou,China", x: 0.23, y: 0.28, width: 0.34),
            item("Fox", x: 0.23, y: 0.45, width: 0.15),
            item("CN → EN", x: 0.23, y: 0.49, width: 0.18),
            item("Wuxi,China", x: 0.23, y: 0.53, width: 0.28),
            item("Flora", x: 0.23, y: 0.70, width: 0.18),
            item("Xuancheng,China", x: 0.23, y: 0.78, width: 0.36)
        ]

        let targets = CustomSearchResultTargetDetector().targets(in: observations)

        XCTAssertEqual(targets.map(\.displayName), ["Emily", "Fox"])
        XCTAssertEqual(targets.map(\.location.city), ["Guangzhou", "Wuxi"])
        XCTAssertTrue(targets.allSatisfy { $0.safePhotoRegion.contains($0.photoPoint) })
        XCTAssertTrue(targets.allSatisfy { $0.photoPoint.x < 0.18 })
    }

    func testSearchPlannerRequiresExactButtonAnchor() throws {
        let planner = CustomSearchInteractionPlanner()
        let action = try XCTUnwrap(planner.searchAction(in: [
            item("Custom Search", x: 0.30, y: 0.08, width: 0.40),
            item("Search", x: 0.35, y: 0.72, width: 0.30)
        ]))

        XCTAssertEqual(action.kind, .refreshCustomSearch)
        XCTAssertEqual(action.point, NormalizedPoint(x: 0.50, y: 0.735))
    }

    private func item(
        _ text: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double = 0.03
    ) -> OCRObservation {
        OCRObservation(
            text: text,
            confidence: 0.95,
            bounds: NormalizedRect(x: x, y: y, width: width, height: height)
        )
    }
}
