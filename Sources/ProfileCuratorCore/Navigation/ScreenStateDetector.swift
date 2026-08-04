import CoreGraphics
import Foundation

public enum DetectedScreenKind: String, Codable, CaseIterable, Hashable, Sendable {
    case connectFeed
    case customSearch
    case profileTop
    case profilePersonalInfo
    case suggestedProfilesGallery
    case pfpViewer
    case momentsFeed
    case momentViewer
    case unknown
}

public struct ScreenClassification: Codable, Sendable {
    public let kind: DetectedScreenKind
    public let navigationState: NavigationState
    public let confidence: Double
    public let evidence: [String]

    public init(
        kind: DetectedScreenKind,
        navigationState: NavigationState,
        confidence: Double,
        evidence: [String]
    ) {
        self.kind = kind
        self.navigationState = navigationState
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct NavigationStateDetector: Sendable {
    private let headerParser = ProfileHeaderParser()

    public init() {}

    public func classify(_ analysis: FixtureAnalysis, image: CGImage? = nil) -> ScreenClassification {
        let text = analysis.text.map(\.text).joined(separator: " · ")

        if contains("AI Photo Gift", in: text) || contains("Avatar Effect", in: text) {
            return classification(.pfpViewer, .inspectPFPViewer, 0.98, ["PFP action rows"])
        }
        if containsMomentsFeedAnchors(in: analysis) {
            return classification(.momentsFeed, .collectMoments, 0.9, ["Moments feed tab and activity anchors"])
        }
        if (containsGalleryCounter(in: text) || contains("LIVE", in: text))
            && (contains("Like", in: text) || contains("Comment", in: text) || contains("Moments", in: text) || contains("AI", in: text)) {
            return classification(.momentViewer, .inspectMomentViewer, 0.9, ["Moment media chrome"])
        }
        if contains("Moments", in: text)
            && (contains("Posts", in: text) || contains("Album", in: text) || contains("No moments", in: text)
                || (contains("Like", in: text) && contains("Comment", in: text))) {
            return classification(.momentsFeed, .collectMoments, 0.84, ["Moments feed anchors"])
        }
        if let image, MomentViewerVisualDetector().matches(image) {
            return classification(.momentViewer, .inspectMomentViewer, 0.8, ["Dark media frame and pagination strip"])
        }
        if contains("Suggested for You", in: text) {
            return classification(
                .suggestedProfilesGallery,
                .scanRecommendationCards,
                0.98,
                ["Suggested for You"]
            )
        }
        if contains("Personal Info", in: text) {
            return classification(
                .profilePersonalInfo,
                .evaluateMBTI,
                0.96,
                ["Personal Info"]
            )
        }
        if contains("Custom Search", in: text) ||
            (contains("Active", in: text) && contains("Age", in: text) && contains("Search", in: text)) {
            return classification(.customSearch, .acquireSeedProfile, 0.9, ["Custom Search controls"])
        }
        if contains("Connect", in: text) && (contains("Say Hi", in: text) || contains("Nearby", in: text)) {
            return classification(.connectFeed, .acquireSeedProfile, 0.86, ["Connect feed anchors"])
        }
        if headerParser.bestAge(in: analysis.text) != nil &&
            (contains("Follow", in: text) || contains("Say Hi", in: text)) {
            return classification(.profileTop, .profileTop, 0.82, ["Age badge", "Profile social bar"])
        }

        return classification(.unknown, .pausedUnknownState, 0, [])
    }

    private func contains(_ anchor: String, in text: String) -> Bool {
        OCRAnchorMatcher().contains(anchor: anchor, in: text)
    }

    private func containsGalleryCounter(in text: String) -> Bool {
        text.range(of: #"\b\d{1,2}\s*/\s*\d{1,2}\b"#, options: .regularExpression) != nil
    }

    private func containsMomentsFeedAnchors(in analysis: FixtureAnalysis) -> Bool {
        let hasTab = analysis.text.contains {
            contains("Moments", in: $0.text) && $0.bounds.minY >= 0.28 && $0.bounds.minY <= 0.66
        }
        let text = analysis.text.map(\.text).joined(separator: " · ")
        return hasTab && contains("Like", in: text) && contains("Comment", in: text)
    }

    private func classification(
        _ kind: DetectedScreenKind,
        _ state: NavigationState,
        _ confidence: Double,
        _ evidence: [String]
    ) -> ScreenClassification {
        ScreenClassification(kind: kind, navigationState: state, confidence: confidence, evidence: evidence)
    }
}

struct MomentViewerVisualDetector: Sendable {
    func matches(_ image: CGImage) -> Bool {
        guard let pixels = ScreenPixelBuffer(image: image) else { return false }
        let topDark = pixels.darkFraction(in: NormalizedRect(x: 0.06, y: 0.14, width: 0.88, height: 0.17))
        let bottomDark = pixels.darkFraction(in: NormalizedRect(x: 0.06, y: 0.70, width: 0.88, height: 0.14))
        let centerContent = pixels.nonDarkFraction(in: NormalizedRect(x: 0.06, y: 0.35, width: 0.88, height: 0.30))
        let paginationLight = pixels.neutralLightFraction(
            in: NormalizedRect(x: 0.28, y: 0.86, width: 0.44, height: 0.055)
        )
        return topDark >= 0.72
            && bottomDark >= 0.72
            && centerContent >= 0.18
            && paginationLight >= 0.0008
            && paginationLight <= 0.06
    }
}

private struct ScreenPixelBuffer {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        let imageBytesPerRow = imageWidth * 4
        var storage = [UInt8](repeating: 0, count: imageBytesPerRow * imageHeight)
        let drew = storage.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard drew else { return nil }
        width = imageWidth
        height = imageHeight
        bytesPerRow = imageBytesPerRow
        bytes = storage
    }

    func darkFraction(in rect: NormalizedRect) -> Double {
        fraction(in: rect, stride: 3) { red, green, blue in max(red, green, blue) < 38 }
    }

    func nonDarkFraction(in rect: NormalizedRect) -> Double {
        fraction(in: rect, stride: 3) { red, green, blue in max(red, green, blue) >= 48 }
    }

    func neutralLightFraction(in rect: NormalizedRect) -> Double {
        fraction(in: rect, stride: 1) { red, green, blue in
            min(red, green, blue) >= 52 && max(red, green, blue) - min(red, green, blue) <= 42
        }
    }

    private func fraction(
        in rect: NormalizedRect,
        stride: Int,
        predicate: (Int, Int, Int) -> Bool
    ) -> Double {
        let minX = max(0, Int((rect.minX * Double(width)).rounded()))
        let minY = max(0, Int((rect.minY * Double(height)).rounded()))
        let maxX = min(width, Int((rect.maxX * Double(width)).rounded()))
        let maxY = min(height, Int((rect.maxY * Double(height)).rounded()))
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        var samples = 0
        for row in Swift.stride(from: minY, to: maxY, by: max(1, stride)) {
            for column in Swift.stride(from: minX, to: maxX, by: max(1, stride)) {
                let offset = row * bytesPerRow + column * 4
                if predicate(Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])) {
                    matches += 1
                }
                samples += 1
            }
        }
        return samples == 0 ? 0 : Double(matches) / Double(samples)
    }
}

public struct ObservationSnapshot: Codable, Sendable {
    public let fingerprint: String
    public let screen: ScreenClassification
    public let combinedOCRText: String
    public let username: String?
    public let capturedAt: Date

    public init(
        fingerprint: String,
        screen: ScreenClassification,
        combinedOCRText: String,
        username: String?,
        capturedAt: Date = Date()
    ) {
        self.fingerprint = fingerprint
        self.screen = screen
        self.combinedOCRText = combinedOCRText
        self.username = username
        self.capturedAt = capturedAt
    }
}

public struct ObservationSnapshotBuilder: Sendable {
    private static let usernameExpression = try! NSRegularExpression(
        pattern: #"@[A-Z0-9_.-]{2,40}"#,
        options: [.caseInsensitive]
    )

    public init() {}

    public func build(
        from analysis: FixtureAnalysis,
        image: CGImage? = nil,
        capturedAt: Date = Date()
    ) -> ObservationSnapshot {
        let orderedText = analysis.text.sorted {
            if abs($0.bounds.minY - $1.bounds.minY) > 0.005 {
                return $0.bounds.minY < $1.bounds.minY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        let combinedText = orderedText.map(\.text).joined(separator: " · ")
        let stableText = orderedText.filter { !isRotatingLocationBadge($0) }
        let canonical = stableText.map {
            "\($0.text.lowercased())@\(quantize($0.bounds.x)),\(quantize($0.bounds.y))"
        }.joined(separator: "|") + "|faces:\(analysis.faces.count)|size:\(analysis.imageWidth)x\(analysis.imageHeight)"

        return ObservationSnapshot(
            fingerprint: stableFingerprint(canonical),
            screen: NavigationStateDetector().classify(analysis, image: image),
            combinedOCRText: combinedText,
            username: username(in: combinedText),
            capturedAt: capturedAt
        )
    }

    private func username(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.usernameExpression.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange]).lowercased()
    }

    private func isRotatingLocationBadge(_ observation: OCRObservation) -> Bool {
        let parser = RotatingLocationBadgeParser()
        return !parser.locationSamples(in: [observation], minimumConfidence: 0).isEmpty ||
            !parser.nearbySamples(in: [observation], minimumConfidence: 0).isEmpty
    }

    private func quantize(_ value: Double) -> Int {
        Int((value * 1_000).rounded())
    }

    private func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
