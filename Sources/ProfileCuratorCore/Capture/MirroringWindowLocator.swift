import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public struct MirroringWindowDescriptor: Identifiable, Hashable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let applicationName: String
    public let bundleIdentifier: String?
    public let frame: CGRect
    public let confidence: Double

    public init(
        id: CGWindowID,
        title: String,
        applicationName: String,
        bundleIdentifier: String?,
        frame: CGRect,
        confidence: Double
    ) {
        self.id = id
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.confidence = confidence
    }
}

public struct MirroringWindowLocator: Sendable {
    private static let likelyBundleIdentifiers = [
        "com.apple.ScreenContinuity"
    ]

    public init() {}

    public func locateCandidates() async throws -> [MirroringWindowDescriptor] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        return content.windows.compactMap { window in
            guard let application = window.owningApplication else { return nil }
            let appName = application.applicationName
            let bundleID = application.bundleIdentifier
            let title = window.title ?? "Untitled"
            let haystack = "\(appName) \(title)".lowercased()

            let bundleMatch = Self.likelyBundleIdentifiers.contains(bundleID)
            let nameMatch = haystack.contains("iphone mirroring")
                || haystack.contains("iphone 镜像")
                || haystack.contains("iphone 鏡像")

            guard bundleMatch || nameMatch else { return nil }

            return MirroringWindowDescriptor(
                id: window.windowID,
                title: title,
                applicationName: appName,
                bundleIdentifier: bundleID,
                frame: window.frame,
                confidence: bundleMatch && nameMatch ? 1 : 0.75
            )
        }
        .sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
            }
            return lhs.confidence > rhs.confidence
        }
    }
}
