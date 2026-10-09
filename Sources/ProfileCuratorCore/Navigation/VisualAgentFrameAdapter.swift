import Foundation

public enum VisualAgentFrameAdapterError: Error, Sendable {
    case missingScreenshotDigest
}

/// Read-only bridge from the current Apple Vision/OCR pipeline to grounded AI element IDs.
/// This intentionally exposes *only* verified OCR navigation tabs. It cannot open profiles,
/// pick people, capture media, or emit any input. The caller supplies an image-byte digest.
public struct VisualAgentFrameAdapter: Sendable {
    public init() {}

    public func build(screenshotDigest: String,
                      observation: ObservationSnapshot,
                      analysis: FixtureAnalysis,
                      calibratedExclusions: [ExclusionZone] = []) throws -> VisualAgentFrame {
        guard !screenshotDigest.isEmpty else { throw VisualAgentFrameAdapterError.missingScreenshotDigest }
        let interaction = ProfileInteractionSafety()
        var controls: [VisualAgentElement] = []
        let tabScreens: Set<String> = ["profileTop", "profilePersonalInfo", "suggestedProfilesGallery", "momentsFeed"]
        if tabScreens.contains(observation.screen.kind.rawValue) {
            for (tab, id) in [("About Me", "tab-about-me"), ("Moments", "tab-moments")] {
                guard let action = interaction.tabAction(named: tab, in: analysis.text),
                      let bounds = action.requiredSafeRegion, bounds.isValidNormalizedRect else { continue }
                controls.append(VisualAgentElement(
                    id: id,
                    label: tab,
                    role: .navigation,
                    actionKind: action.kind,
                    bounds: bounds
                ))
            }
        }
        let exclusions = calibratedExclusions
            + SocialControlExclusionDetector().exclusions(in: analysis.text)
            + interaction.learningStatsExclusions(in: analysis.text)
        return VisualAgentFrame(
            id: screenshotDigest,
            screenKind: observation.screen.kind.rawValue,
            visibleText: analysis.text.map(\.text),
            elements: controls,
            exclusions: exclusions
        )
    }
}
