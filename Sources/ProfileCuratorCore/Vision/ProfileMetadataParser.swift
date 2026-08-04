import Foundation

public struct ParsedProfileMetadata: Hashable, Sendable {
    public var bio: String?
    public var hobbies: [String]
    public var education: String?
    public var occupation: String?

    public init(
        bio: String? = nil,
        hobbies: [String] = [],
        education: String? = nil,
        occupation: String? = nil
    ) {
        self.bio = bio
        self.hobbies = hobbies
        self.education = education
        self.occupation = occupation
    }
}

public struct ProfileMetadataParser: Sendable {
    private enum Field: CaseIterable {
        case bio, hobbies, education, occupation

        var aliases: [String] {
            switch self {
            case .bio: ["bio", "self introduction", "self-introduction", "introduction", "自我介绍", "個人簡介"]
            case .hobbies: [
                "interest & hobbies", "interests & hobbies", "interest and hobbies",
                "hobbies", "hobby", "interests", "interest", "爱好", "愛好", "兴趣", "興趣"
            ]
            case .education: ["education", "school", "education background", "教育", "学校", "學校"]
            case .occupation: ["occupation", "profession", "job", "work", "职业", "職業", "工作"]
            }
        }
    }

    private struct Item {
        let text: String
        let normalized: String
        let bounds: NormalizedRect
    }

    public init() {}

    public func parse(_ observations: [OCRObservation]) -> ParsedProfileMetadata {
        let items = observations
            .filter { $0.confidence >= 0.35 }
            .compactMap { observation -> Item? in
                let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return Item(text: text, normalized: normalize(text), bounds: observation.bounds)
            }
            .sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }

        let explicitBio = values(for: .bio, in: items, maximumVerticalSpan: 0.20).joined(separator: " ").nilIfBlank
        let bio = explicitBio ?? unlabeledBio(in: items)
        let education = values(for: .education, in: items, maximumVerticalSpan: 0.12).joined(separator: " ").nilIfBlank
        let occupation = values(for: .occupation, in: items, maximumVerticalSpan: 0.12).joined(separator: " ").nilIfBlank
        let hobbies = deduplicatedHobbies(values(for: .hobbies, in: items, maximumVerticalSpan: 0.26))
        return ParsedProfileMetadata(bio: bio, hobbies: hobbies, education: education, occupation: occupation)
    }

    private func values(for field: Field, in items: [Item], maximumVerticalSpan: Double) -> [String] {
        guard let labelIndex = items.firstIndex(where: { matchesLabel($0.normalized, field: field) }) else { return [] }
        let label = items[labelIndex]
        if let inline = inlineValue(in: label.text, field: field) { return [inline] }
        if [.education, .occupation].contains(field), let tileValue = tileValueAbove(labelIndex: labelIndex, in: items) {
            return [tileValue]
        }

        let nextFieldY = items.dropFirst(labelIndex + 1)
            .first(where: { item in Field.allCases.contains { matchesLabel(item.normalized, field: $0) } })?
            .bounds.minY ?? 1
        let lowerBound = label.bounds.minY - 0.012
        let upperBound = min(label.bounds.maxY + maximumVerticalSpan, nextFieldY - 0.004)
        let candidates = items.dropFirst(labelIndex + 1).filter { item in
            item.bounds.minY >= lowerBound
                && item.bounds.minY <= upperBound
                && !isInterfaceText(item.normalized)
                && !Field.allCases.contains(where: { matchesLabel(item.normalized, field: $0) })
        }
        return candidates.map(\.text)
    }

    private func tileValueAbove(labelIndex: Int, in items: [Item]) -> String? {
        let label = items[labelIndex]
        return items.prefix(labelIndex)
            .filter { item in
                let verticalGap = label.bounds.minY - item.bounds.maxY
                return item.bounds.minY < label.bounds.minY
                    && verticalGap >= -0.01
                    && verticalGap <= 0.07
                    && abs(item.bounds.center.x - label.bounds.center.x) <= 0.14
                    && !isInterfaceText(item.normalized)
                    && !Field.allCases.contains(where: { matchesLabel(item.normalized, field: $0) })
            }
            .max(by: { $0.bounds.minY < $1.bounds.minY })?
            .text
    }

    private func unlabeledBio(in items: [Item]) -> String? {
        guard let aboutMe = items.first(where: { $0.normalized == "about me" }) else { return nil }
        let candidates = items.filter { item in
            item.bounds.minY >= max(0, aboutMe.bounds.minY - 0.19)
                && item.bounds.maxY <= aboutMe.bounds.minY + 0.012
                && !isBioNoise(item)
        }
        return candidates.map(\.text).joined(separator: " ").nilIfBlank
    }

    private func isBioNoise(_ item: Item) -> Bool {
        let value = item.normalized
        if isInterfaceText(value) || value.hasPrefix("@") { return true }
        if ["cn", "en", "english", "chinese", "about me", "moments", "achievements"].contains(value) { return true }
        if ["following", "followers", "streak", "joined", "active now"].contains(where: value.contains) { return true }
        let letters = item.text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return letters.count < 2
    }

    private func inlineValue(in text: String, field: Field) -> String? {
        let folded = normalize(text)
        guard let alias = field.aliases.first(where: { folded.hasPrefix(normalize($0)) }) else { return nil }
        let rawAliasLength = alias.count
        guard text.count > rawAliasLength else { return nil }
        let start = text.index(text.startIndex, offsetBy: min(rawAliasLength, text.count))
        let suffix = text[start...].trimmingCharacters(in: CharacterSet(charactersIn: " :：-–—\t"))
        return suffix.nilIfBlank
    }

    private func deduplicatedHobbies(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，;；|•·\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                !value.isEmpty && seen.insert(normalize(value)).inserted
            }
    }

    private func matchesLabel(_ normalized: String, field: Field) -> Bool {
        field.aliases.contains { alias in
            let value = normalize(alias)
            return normalized == value
                || normalized.hasPrefix(value + ":")
                || normalized.hasPrefix(value + "：")
        }
    }

    private func isInterfaceText(_ value: String) -> Bool {
        ["personal info", "moments", "achievements", "about me", "suggested for you", "say hi", "follow", "message"]
            .contains(value)
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ProfileSignalScores: Hashable, Sendable {
    public let hobbies: Double?
    public let education: Double?
    public let occupation: Double?
    public let combined: Double?
}

public struct ProfileSignalScorer: Sendable {
    public init() {}

    public func score(hobbies: [String], education: String?, occupation: String?) -> ProfileSignalScores {
        let hobbyScore = scoreHobbies(hobbies)
        let educationScore = scoreEducation(education)
        let occupationScore = scoreOccupation(occupation)
        let weighted = [
            (hobbyScore, 0.50),
            (educationScore, 0.35),
            (occupationScore, 0.15)
        ].compactMap { score, weight in score.map { ($0, weight) } }
        let totalWeight = weighted.reduce(0) { $0 + $1.1 }
        let combined = totalWeight > 0
            ? weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
            : nil
        return ProfileSignalScores(
            hobbies: hobbyScore,
            education: educationScore,
            occupation: occupationScore,
            combined: combined
        )
    }

    public func enrichLifestyle(visualScore: Double, profileSignalScore: Double?) -> Double {
        guard let profileSignalScore else { return clamp(visualScore) }
        return clamp(visualScore * 0.70 + profileSignalScore * 0.30)
    }

    private func scoreHobbies(_ hobbies: [String]) -> Double? {
        guard !hobbies.isEmpty else { return nil }
        let scores = hobbies.map { hobby -> Double in
            let value = normalize(hobby)
            if containsAny(value, ["psychology", "philosophy", "business", "economics", "心理学", "哲学", "经济学", "商科"]) { return 95 }
            if containsAny(value, ["horseback riding", "scuba diving", "skiing", "snowboarding", "traveling", "travelling", "travel", "骑马", "潜水", "滑雪", "旅行"]) { return 90 }
            if containsAny(value, ["sports", "sport", "tennis", "yoga", "pilates", "riding", "运动", "网球", "瑜伽", "普拉提", "骑行"]) { return 82 }
            if containsAny(value, ["fashion", "cat", "cats", "dog", "dogs", "时尚", "猫", "狗"]) { return 75 }
            return 55
        }
        let strongest = scores.sorted(by: >).prefix(3)
        return strongest.reduce(0, +) / Double(strongest.count)
    }

    private func scoreEducation(_ education: String?) -> Double? {
        guard let education = education?.trimmingCharacters(in: .whitespacesAndNewlines), !education.isEmpty else { return nil }
        let value = normalize(education)
        if containsAny(value, ["tsinghua", "peking university", "beida", "清华", "清華", "北大"]) { return nil }
        if containsAny(value, ["international student", "overseas student", "留学生", "留學生"]) { return 100 }
        if containsAny(value, ["vocational", "technical college", "职业", "職業", "大专", "大專"]) { return 20 }
        if containsAny(value, ["junior school", "junior high", "middle school", "初中"]) { return 40 }
        if containsAny(value, ["senior high school student", "senior high", "high school student", "高中"]) { return 75 }
        if containsAny(value, ["university", "college", "本科", "大学", "大學"]) { return 80 }
        return 65
    }

    private func scoreOccupation(_ occupation: String?) -> Double? {
        guard let occupation = occupation?.trimmingCharacters(in: .whitespacesAndNewlines), !occupation.isEmpty else { return nil }
        let value = normalize(occupation)
        if value == "worker" || value == "工人" || value.contains("operations") || value.contains("运营") || value.contains("運營") {
            return 20
        }
        return 60
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    private func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
