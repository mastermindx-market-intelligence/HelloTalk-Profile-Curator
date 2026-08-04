import Foundation

public enum PostconditionStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case inconclusive
}

public struct PostconditionResult: Codable, Sendable {
    public let condition: VisiblePostcondition
    public let status: PostconditionStatus
    public let summary: String

    public init(condition: VisiblePostcondition, status: PostconditionStatus, summary: String) {
        self.condition = condition
        self.status = status
        self.summary = summary
    }
}

public struct NavigationPostconditionEvaluator: Sendable {
    public init() {}

    public func evaluate(
        _ condition: VisiblePostcondition,
        against snapshot: ObservationSnapshot
    ) -> PostconditionResult {
        switch condition {
        case .contentHashChanged(let previous):
            return result(
                condition,
                passed: snapshot.fingerprint != previous,
                success: "Captured content changed",
                failure: "Captured content fingerprint did not change"
            )
        case .ocrAnchorVisible(let anchor):
            return result(
                condition,
                passed: snapshot.combinedOCRText.localizedCaseInsensitiveContains(anchor),
                success: "OCR anchor visible: \(anchor)",
                failure: "OCR anchor missing: \(anchor)"
            )
        case .ocrAnchorAbsent(let anchor):
            return result(
                condition,
                passed: !snapshot.combinedOCRText.localizedCaseInsensitiveContains(anchor),
                success: "OCR anchor dismissed: \(anchor)",
                failure: "OCR anchor is still visible: \(anchor)"
            )
        case .viewerDetected:
            let kinds: Set<DetectedScreenKind> = [.pfpViewer, .momentViewer]
            return result(
                condition,
                passed: kinds.contains(snapshot.screen.kind),
                success: "Viewer detected",
                failure: "No recognized viewer detected"
            )
        case .profilePageDetected:
            let kinds: Set<DetectedScreenKind> = [
                .profileTop, .profilePersonalInfo, .suggestedProfilesGallery, .momentsFeed
            ]
            return result(
                condition,
                passed: kinds.contains(snapshot.screen.kind),
                success: "Profile surface detected",
                failure: "No recognized profile surface detected"
            )
        case .selectedTab(let tab):
            return result(
                condition,
                passed: snapshot.combinedOCRText.localizedCaseInsensitiveContains(tab),
                success: "Selected tab anchor visible: \(tab)",
                failure: "Selected tab anchor missing: \(tab)"
            )
        case .profileIdentityChanged(let previousUsername):
            guard let previousUsername, let current = snapshot.username else {
                return PostconditionResult(
                    condition: condition,
                    status: .inconclusive,
                    summary: "A previous and current username are required"
                )
            }
            return result(
                condition,
                passed: current != previousUsername.lowercased(),
                success: "Profile identity changed to \(current)",
                failure: "Profile identity is still \(current)"
            )
        }
    }

    private func result(
        _ condition: VisiblePostcondition,
        passed: Bool,
        success: String,
        failure: String
    ) -> PostconditionResult {
        PostconditionResult(
            condition: condition,
            status: passed ? .passed : .failed,
            summary: passed ? success : failure
        )
    }
}
