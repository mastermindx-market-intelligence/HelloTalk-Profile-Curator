import Foundation

public struct ProfileInteractionSafety: Sendable {
    public init() {}

    public func tabAction(named tab: String, in observations: [OCRObservation]) -> PlannedAction? {
        let normalizedTab = normalize(tab)
        guard let anchor = observations
            .filter({ $0.confidence >= 0.65 && matchesTab($0.text, requestedTab: normalizedTab) })
            .max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }
        let kind: PlannedActionKind = normalizedTab == "moments" ? .selectMoments : .selectAboutMe
        return PlannedAction(
            kind: kind,
            point: anchor.bounds.center,
            requiredSafeRegion: expanded(anchor.bounds, horizontal: 0.025, vertical: 0.016),
            rationale: "Select the live OCR \(tab) tab anchor"
        )
    }

    public func learningStatsExclusions(in observations: [OCRObservation]) -> [ExclusionZone] {
        let joined = observations.filter {
            normalize($0.text).contains("joined") && $0.confidence >= 0.55
        }
        let points = observations.filter {
            normalize($0.text).contains("points") && $0.confidence >= 0.55
        }
        guard let pair = joined.flatMap({ joinedItem in
            points.compactMap { pointsItem -> (OCRObservation, OCRObservation, Double)? in
                let distance = abs(joinedItem.bounds.center.y - pointsItem.bounds.center.y)
                return distance <= 0.09 ? (joinedItem, pointsItem, distance) : nil
            }
        }).min(by: { $0.2 < $1.2 }) else {
            return []
        }

        let minY = max(0, min(pair.0.bounds.minY, pair.1.bounds.minY) - 0.022)
        let maxY = min(1, max(pair.0.bounds.maxY, pair.1.bounds.maxY) + 0.145)
        return [ExclusionZone(
            label: "Learning statistics card",
            bounds: NormalizedRect(x: 0.025, y: minY, width: 0.95, height: maxY - minY)
        )]
    }

    public func isLearningStatsPopup(_ observations: [OCRObservation]) -> Bool {
        let text = observations.map { normalize($0.text) }
        let detailAnchors = [
            "translations used", "tapped word",
            "transcription", "pronunciation", "unique learning features"
        ]
        let hasTitle = text.contains(where: { $0.contains("total learning points") })
        let hasDetail = detailAnchors.contains { anchor in text.contains(where: { $0.contains(anchor) }) }
        return hasTitle && hasDetail
    }

    public func dismissLearningStatsPopupAction() -> PlannedAction {
        let region = NormalizedRect(x: 0.80, y: 0.13, width: 0.16, height: 0.09)
        return PlannedAction(
            kind: .closeViewer,
            point: region.center,
            requiredSafeRegion: region,
            rationale: "Dismiss the learning-statistics popup by tapping the unobstructed map margin"
        )
    }

    public func scrollAction(lines: Int, avoiding exclusions: [ExclusionZone]) -> PlannedAction? {
        let candidates = [
            NormalizedPoint(x: 0.88, y: 0.66),
            NormalizedPoint(x: 0.88, y: 0.52),
            NormalizedPoint(x: 0.12, y: 0.66),
            NormalizedPoint(x: 0.88, y: 0.38),
            NormalizedPoint(x: 0.12, y: 0.52)
        ]
        guard let point = candidates.first(where: { candidate in
            !exclusions.contains(where: { $0.bounds.contains(candidate) })
        }) else {
            return nil
        }
        let region = NormalizedRect(x: point.x - 0.045, y: point.y - 0.045, width: 0.09, height: 0.09)
        return PlannedAction(
            kind: .verticalScroll,
            point: point,
            requiredSafeRegion: region,
            rationale: lines < 0 ? "Discrete vertical scroll down outside interactive cards" : "Discrete vertical scroll up outside interactive cards"
        )
    }

    private func expanded(_ bounds: NormalizedRect, horizontal: Double, vertical: Double) -> NormalizedRect {
        let minX = max(0, bounds.minX - horizontal)
        let minY = max(0, bounds.minY - vertical)
        let maxX = min(1, bounds.maxX + horizontal)
        let maxY = min(1, bounds.maxY + vertical)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesTab(_ observedText: String, requestedTab: String) -> Bool {
        let candidate = normalize(observedText)
        guard requestedTab == "moments" else { return candidate == requestedTab }
        return candidate.range(
            of: #"^moments\s*\d*$"#,
            options: .regularExpression
        ) != nil
    }
}
