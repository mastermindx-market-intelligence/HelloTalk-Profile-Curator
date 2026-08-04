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

    func testLivePhotoBadgeInViewerHeaderIdentifiesMomentViewerWithHiddenChrome() {
        let analysis = FixtureAnalysis(
            imageWidth: 418,
            imageHeight: 920,
            text: [
                OCRObservation(
                    text: "LIVE",
                    confidence: 0.95,
                    bounds: NormalizedRect(x: 0.115, y: 0.174, width: 0.077, height: 0.013)
                )
            ],
            faces: []
        )

        let result = NavigationStateDetector().classify(analysis)

        XCTAssertEqual(result.kind, .momentViewer)
        XCTAssertEqual(result.navigationState, .inspectMomentViewer)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.85)
    }

    func testLiveBadgeOutsideViewerHeaderDoesNotCreateFalsePositive() {
        let analysis = FixtureAnalysis(
            imageWidth: 418,
            imageHeight: 920,
            text: [
                OCRObservation(
                    text: "LIVE",
                    confidence: 0.95,
                    bounds: NormalizedRect(x: 0.08, y: 0.72, width: 0.08, height: 0.02)
                )
            ],
            faces: []
        )

        XCTAssertEqual(NavigationStateDetector().classify(analysis).kind, .unknown)
    }

    func testMomentDetailsGridDoesNotMimicMomentViewerThroughPostDate() {
        let analysis = FixtureAnalysis(
            imageWidth: 418,
            imageHeight: 920,
            text: [
                OCRObservation(text: "Details", confidence: 0.95, bounds: NormalizedRect(x: 0.42, y: 0.11, width: 0.15, height: 0.03)),
                OCRObservation(text: "19/07", confidence: 0.95, bounds: NormalizedRect(x: 0.86, y: 0.20, width: 0.08, height: 0.02)),
                OCRObservation(text: "24 Likes", confidence: 0.95, bounds: NormalizedRect(x: 0.77, y: 0.68, width: 0.17, height: 0.02)),
                OCRObservation(text: "Comments (3)", confidence: 0.95, bounds: NormalizedRect(x: 0.07, y: 0.84, width: 0.26, height: 0.02)),
                OCRObservation(text: "Type a message.", confidence: 0.95, bounds: NormalizedRect(x: 0.07, y: 0.91, width: 0.35, height: 0.02))
            ],
            faces: []
        )

        let result = NavigationStateDetector().classify(analysis)

        XCTAssertEqual(result.kind, .momentDetails)
        XCTAssertEqual(result.navigationState, .collectMoments)
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
