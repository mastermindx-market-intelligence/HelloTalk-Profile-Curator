import CoreGraphics
import Foundation
import ImageIO

public struct FixtureManifest: Codable, Sendable {
    public let image: String
    public let expectedAnchors: [String]
    public let expectedMBTI: MBTIType?
    public let expectedAge: Int?
    public let expectedRecommendationAges: [Int]?
    public let expectedGenderHint: GenderBadgeHint?
    public let expectedLocationCity: String?
    public let expectedNearbyCount: Int?
    public let expectedScreenKind: DetectedScreenKind?
    public let expectedVisibleTargetAges: [Int]?
    public let expectedVisibleTargetKeys: [String]?
    public let minimumFaces: Int?
    public let notes: String?

    public init(
        image: String,
        expectedAnchors: [String] = [],
        expectedMBTI: MBTIType? = nil,
        expectedAge: Int? = nil,
        expectedRecommendationAges: [Int]? = nil,
        expectedGenderHint: GenderBadgeHint? = nil,
        expectedLocationCity: String? = nil,
        expectedNearbyCount: Int? = nil,
        expectedScreenKind: DetectedScreenKind? = nil,
        expectedVisibleTargetAges: [Int]? = nil,
        expectedVisibleTargetKeys: [String]? = nil,
        minimumFaces: Int? = nil,
        notes: String? = nil
    ) {
        self.image = image
        self.expectedAnchors = expectedAnchors
        self.expectedMBTI = expectedMBTI
        self.expectedAge = expectedAge
        self.expectedRecommendationAges = expectedRecommendationAges
        self.expectedGenderHint = expectedGenderHint
        self.expectedLocationCity = expectedLocationCity
        self.expectedNearbyCount = expectedNearbyCount
        self.expectedScreenKind = expectedScreenKind
        self.expectedVisibleTargetAges = expectedVisibleTargetAges
        self.expectedVisibleTargetKeys = expectedVisibleTargetKeys
        self.minimumFaces = minimumFaces
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case image
        case expectedAnchors
        case expectedMBTI
        case expectedAge
        case expectedRecommendationAges
        case expectedGenderHint
        case expectedLocationCity
        case expectedNearbyCount
        case expectedScreenKind
        case expectedVisibleTargetAges
        case expectedVisibleTargetKeys
        case minimumFaces
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try container.decode(String.self, forKey: .image)
        expectedAnchors = try container.decodeIfPresent([String].self, forKey: .expectedAnchors) ?? []
        expectedMBTI = try container.decodeIfPresent(MBTIType.self, forKey: .expectedMBTI)
        expectedAge = try container.decodeIfPresent(Int.self, forKey: .expectedAge)
        expectedRecommendationAges = try container.decodeIfPresent([Int].self, forKey: .expectedRecommendationAges)
        expectedGenderHint = try container.decodeIfPresent(GenderBadgeHint.self, forKey: .expectedGenderHint)
        expectedLocationCity = try container.decodeIfPresent(String.self, forKey: .expectedLocationCity)
        expectedNearbyCount = try container.decodeIfPresent(Int.self, forKey: .expectedNearbyCount)
        expectedScreenKind = try container.decodeIfPresent(DetectedScreenKind.self, forKey: .expectedScreenKind)
        expectedVisibleTargetAges = try container.decodeIfPresent([Int].self, forKey: .expectedVisibleTargetAges)
        expectedVisibleTargetKeys = try container.decodeIfPresent([String].self, forKey: .expectedVisibleTargetKeys)
        minimumFaces = try container.decodeIfPresent(Int.self, forKey: .minimumFaces)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct FixtureReplayResult: Sendable {
    public let manifestURL: URL
    public let manifest: FixtureManifest
    public let analysis: FixtureAnalysis
    public let combinedOCRText: String
    public let mbtiMatches: [MBTIMatch]
    public let profileAgeMatches: [ProfileAgeMatch]
    public let genderBadgeEvidence: GenderBadgeEvidence?
    public let ageCandidates: [RecommendationAgeCandidate]
    public let allRecommendationAges: [RecommendationAgeCandidate]
    public let temporalLocation: TemporalLocationResolution
    public let screenClassification: ScreenClassification
    public let visibleRecommendationTargets: [VisibleRecommendationTarget]
    public let validationFailures: [String]

    public init(
        manifestURL: URL,
        manifest: FixtureManifest,
        analysis: FixtureAnalysis,
        combinedOCRText: String,
        mbtiMatches: [MBTIMatch],
        profileAgeMatches: [ProfileAgeMatch],
        genderBadgeEvidence: GenderBadgeEvidence?,
        ageCandidates: [RecommendationAgeCandidate],
        allRecommendationAges: [RecommendationAgeCandidate],
        temporalLocation: TemporalLocationResolution,
        screenClassification: ScreenClassification,
        visibleRecommendationTargets: [VisibleRecommendationTarget],
        validationFailures: [String]
    ) {
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.analysis = analysis
        self.combinedOCRText = combinedOCRText
        self.mbtiMatches = mbtiMatches
        self.profileAgeMatches = profileAgeMatches
        self.genderBadgeEvidence = genderBadgeEvidence
        self.ageCandidates = ageCandidates
        self.allRecommendationAges = allRecommendationAges
        self.temporalLocation = temporalLocation
        self.screenClassification = screenClassification
        self.visibleRecommendationTargets = visibleRecommendationTargets
        self.validationFailures = validationFailures
    }
}

public enum FixtureReplayError: Error, LocalizedError {
    case unreadableImage(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "Could not decode private fixture image at \(url.path)."
        }
    }
}

public struct FixtureReplayHarness: Sendable {
    private let analyzer = VisionFixtureAnalyzer()
    private let mbtiParser = MBTIParser()
    private let ageParser = RecommendationAgeParser()
    private let profileHeaderParser = ProfileHeaderParser()
    private let anchorMatcher = OCRAnchorMatcher()
    private let genderBadgeClassifier = GenderBadgeClassifier()
    private let rotatingLocationBadgeParser = RotatingLocationBadgeParser()

    public init() {}

    public func replay(manifestURL: URL) throws -> FixtureReplayResult {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(FixtureManifest.self, from: Data(contentsOf: manifestURL))
        let imageURL = manifestURL.deletingLastPathComponent().appendingPathComponent(manifest.image)

        guard
            let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FixtureReplayError.unreadableImage(imageURL)
        }

        let analysis = try analyzer.analyze(image)
        let combinedText = analysis.text.map(\.text).joined(separator: " · ")
        let mbtiMatches = mbtiParser.matches(in: analysis.text)
        let profileAgeMatches = profileHeaderParser.ageMatches(in: analysis.text)
        let genderEvidence = profileAgeMatches.first.map {
            genderBadgeClassifier.classify(image: image, ageMatch: $0)
        }
        let ageCandidates = ageParser.candidates(in: analysis.text)
        let allRecommendationAges = ageParser.allAges(in: analysis.text)
        let temporalLocation = rotatingLocationBadgeParser.resolve(frames: [analysis.text])
        let screenClassification = NavigationStateDetector().classify(analysis)
        let visibleRecommendationTargets = VisibleRecommendationTargetDetector().targets(in: analysis.text)
        var failures: [String] = []

        for anchor in manifest.expectedAnchors where !anchorMatcher.contains(anchor: anchor, in: combinedText) {
            failures.append("Missing OCR anchor: \(anchor)")
        }

        if let expectedMBTI = manifest.expectedMBTI,
           !mbtiMatches.contains(where: { $0.type == expectedMBTI }) {
            failures.append("Expected MBTI \(expectedMBTI.rawValue), got \(mbtiMatches.map(\.type.rawValue))")
        }

        if let expectedAge = manifest.expectedAge,
           !profileAgeMatches.contains(where: { $0.age == expectedAge }) {
            failures.append("Expected profile age \(expectedAge), got \(profileAgeMatches.map(\.age))")
        }

        if let minimumFaces = manifest.minimumFaces, analysis.faces.count < minimumFaces {
            failures.append("Expected at least \(minimumFaces) faces, got \(analysis.faces.count)")
        }


        for expectedAge in manifest.expectedRecommendationAges ?? []
        where !allRecommendationAges.contains(where: { $0.age == expectedAge }) {
            failures.append(
                "Expected recommendation age \(expectedAge), got \(allRecommendationAges.map(\.age))"
            )
        }


        if let expectedGenderHint = manifest.expectedGenderHint,
           genderEvidence?.hint != expectedGenderHint {
            failures.append(
                "Expected gender hint \(expectedGenderHint.rawValue), got \(genderEvidence?.hint.rawValue ?? "none") "
                    + "(magenta=\(genderEvidence?.magentaPixelRatio ?? 0), "
                    + "blue=\(genderEvidence?.bluePixelRatio ?? 0), "
                    + "samples=\(genderEvidence?.sampledPixelCount ?? 0), "
                    + "ageBounds=\(profileAgeMatches.first?.source.bounds ?? NormalizedRect(x: 0, y: 0, width: 0, height: 0)))"
            )
        }


        if let expectedLocationCity = manifest.expectedLocationCity,
           temporalLocation.location?.city != expectedLocationCity {
            failures.append(
                "Expected location city \(expectedLocationCity), got \(temporalLocation.location?.city ?? "none")"
            )
        }

        if let expectedNearbyCount = manifest.expectedNearbyCount,
           !temporalLocation.nearbyCountsIgnored.contains(expectedNearbyCount) {
            failures.append(
                "Expected ignored nearby count \(expectedNearbyCount), got \(temporalLocation.nearbyCountsIgnored)"
            )
        }

        if let expectedScreenKind = manifest.expectedScreenKind,
           screenClassification.kind != expectedScreenKind {
            failures.append(
                "Expected screen kind \(expectedScreenKind.rawValue), got \(screenClassification.kind.rawValue)"
            )
        }

        for expectedAge in manifest.expectedVisibleTargetAges ?? []
        where !visibleRecommendationTargets.contains(where: { $0.displayedAge == expectedAge }) {
            let galleryBounds = analysis.text
                .first(where: { $0.text.localizedCaseInsensitiveContains("Suggested for You") })?
                .bounds
            let ageDebug = allRecommendationAges.map { "\($0.age)@\($0.bounds)" }
            failures.append(
                "Expected visible photo target age \(expectedAge), got \(visibleRecommendationTargets.map(\.displayedAge)); "
                    + "gallery=\(galleryBounds.map(String.init(describing:)) ?? "none"), ages=\(ageDebug)"
            )
        }

        for expectedKey in manifest.expectedVisibleTargetKeys ?? []
        where !visibleRecommendationTargets.contains(where: { $0.profileKey == expectedKey.lowercased() }) {
            failures.append(
                "Expected visible photo target key \(expectedKey), got \(visibleRecommendationTargets.map(\.profileKey))"
            )
        }

        return FixtureReplayResult(
            manifestURL: manifestURL,
            manifest: manifest,
            analysis: analysis,
            combinedOCRText: combinedText,
            mbtiMatches: mbtiMatches,
            profileAgeMatches: profileAgeMatches,
            genderBadgeEvidence: genderEvidence,
            ageCandidates: ageCandidates,
            allRecommendationAges: allRecommendationAges,
            temporalLocation: temporalLocation,
            screenClassification: screenClassification,
            visibleRecommendationTargets: visibleRecommendationTargets,
            validationFailures: failures
        )
    }

    public func manifestURLs(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.path < $1.path }
    }
}
