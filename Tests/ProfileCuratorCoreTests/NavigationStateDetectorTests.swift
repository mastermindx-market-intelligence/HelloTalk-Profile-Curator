import XCTest
@testable import ProfileCuratorCore

final class NavigationStateDetectorTests: XCTestCase {
    private let bounds = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.04)

    func testSuggestedGalleryWinsAsPrimaryDetectedSurface() {
        let analysis = fixture(["Suggested for You", "922", "About Me", "Moments"])
        let result = NavigationStateDetector().classify(analysis)

        XCTAssertEqual(result.kind, .suggestedProfilesGallery)
        XCTAssertEqual(result.navigationState, .scanRecommendationCards)
        XCTAssertGreaterThan(result.confidence, 0.9)
    }

    func testPFPActionRowsIdentifyViewer() {
        let result = NavigationStateDetector().classify(fixture(["Al Photo Gift", "Avatar Effect"]))

        XCTAssertEqual(result.kind, .pfpViewer)
        XCTAssertEqual(result.navigationState, .inspectPFPViewer)
    }

    func testUnknownScreenFailsClosed() {
        let result = NavigationStateDetector().classify(fixture(["unrelated text"]))

        XCTAssertEqual(result.kind, .unknown)
        XCTAssertEqual(result.navigationState, .pausedUnknownState)
        XCTAssertEqual(result.confidence, 0)
    }

    func testSnapshotFingerprintIsStableAcrossObservationOrderAndIDs() {
        let first = fixture(["Personal Info", "INFJ"])
        let second = FixtureAnalysis(
            imageWidth: first.imageWidth,
            imageHeight: first.imageHeight,
            text: first.text.reversed().map {
                OCRObservation(text: $0.text, confidence: $0.confidence, bounds: $0.bounds)
            },
            faces: []
        )

        let builder = ObservationSnapshotBuilder()
        XCTAssertEqual(builder.build(from: first).fingerprint, builder.build(from: second).fingerprint)
    }

    func testRotatingLocationBadgeDoesNotCreateFalseContentChange() {
        let peopleFrame = fixture(["Profile content", "576 People Nearby"])
        let cityFrame = fixture(["Profile content", "Shenyang, China 6:58pm"])
        let builder = ObservationSnapshotBuilder()

        XCTAssertEqual(
            builder.build(from: peopleFrame).fingerprint,
            builder.build(from: cityFrame).fingerprint
        )
    }

    private func fixture(_ strings: [String]) -> FixtureAnalysis {
        FixtureAnalysis(
            imageWidth: 420,
            imageHeight: 932,
            text: strings.enumerated().map { index, text in
                OCRObservation(
                    text: text,
                    confidence: 0.95,
                    bounds: NormalizedRect(
                        x: bounds.x,
                        y: bounds.y + Double(index) * 0.06,
                        width: bounds.width,
                        height: bounds.height
                    )
                )
            },
            faces: []
        )
    }
}
