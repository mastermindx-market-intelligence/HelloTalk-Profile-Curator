import Foundation

public struct NormalizedLocation: Codable, Hashable, Sendable {
    public let rawText: String
    public let city: String?
    public let province: String?
    public let country: String?
    public let tier: Int
    public let score: Int
    public let confidence: Double

    public init(
        rawText: String,
        city: String?,
        province: String?,
        country: String?,
        tier: Int,
        score: Int,
        confidence: Double
    ) {
        self.rawText = rawText
        self.city = city
        self.province = province
        self.country = country
        self.tier = tier
        self.score = score
        self.confidence = confidence
    }
}

public struct LocationNormalizer: Sendable {
    private struct Entry: Sendable {
        let aliases: [String]
        let city: String
        let province: String?
        let tier: Int
        let score: Int
    }

    private static let entries: [Entry] = [
        Entry(aliases: ["shenzhen", "深圳"], city: "Shenzhen", province: "Guangdong", tier: 1, score: 100),
        Entry(aliases: ["hong kong", "hongkong", "香港"], city: "Hong Kong", province: nil, tier: 2, score: 85),
        Entry(aliases: ["guangzhou", "广州", "廣州"], city: "Guangzhou", province: "Guangdong", tier: 2, score: 85),
        Entry(aliases: ["dongguan", "东莞", "東莞"], city: "Dongguan", province: "Guangdong", tier: 2, score: 85),
        Entry(aliases: ["foshan", "佛山"], city: "Foshan", province: "Guangdong", tier: 2, score: 85),
        Entry(aliases: ["zhuhai", "珠海"], city: "Zhuhai", province: "Guangdong", tier: 2, score: 85),
        Entry(aliases: ["beijing", "北京"], city: "Beijing", province: nil, tier: 3, score: 70),
        Entry(aliases: ["shanghai", "上海"], city: "Shanghai", province: nil, tier: 3, score: 70),
        Entry(aliases: ["chengdu", "成都"], city: "Chengdu", province: "Sichuan", tier: 4, score: 55),
        Entry(aliases: ["chongqing", "重庆", "重慶"], city: "Chongqing", province: nil, tier: 4, score: 55),
        Entry(aliases: ["hangzhou", "杭州"], city: "Hangzhou", province: "Zhejiang", tier: 4, score: 55),
        Entry(aliases: ["suzhou", "苏州", "蘇州"], city: "Suzhou", province: "Jiangsu", tier: 4, score: 55),
        Entry(aliases: ["wuhan", "武汉", "武漢"], city: "Wuhan", province: "Hubei", tier: 4, score: 55),
        Entry(aliases: ["xi'an", "xian", "西安"], city: "Xi'an", province: "Shaanxi", tier: 4, score: 55),
        Entry(aliases: ["nanjing", "南京"], city: "Nanjing", province: "Jiangsu", tier: 4, score: 55),
        Entry(aliases: ["xiamen", "厦门", "廈門"], city: "Xiamen", province: "Fujian", tier: 4, score: 55),
        Entry(aliases: ["shenyang", "沈阳", "瀋陽"], city: "Shenyang", province: "Liaoning", tier: 5, score: 30)
    ]

    private static let preferredCountries: [(name: String, pattern: String, ideographs: [String])] = [
        ("United States", #"\b(united states|usa|u\.s\.a\.?|america)\b"#, ["美国", "美國"]),
        ("Australia", #"\b(australia|australian)\b"#, ["澳大利亚", "澳大利亞", "澳洲"]),
        ("United Kingdom", #"\b(united kingdom|uk|u\.k\.?|britain|great britain|england)\b"#, ["英国", "英國"]),
        ("Canada", #"\b(canada|canadian)\b"#, ["加拿大"])
    ]

    public init() {}

    public func normalize(_ rawText: String) -> NormalizedLocation {
        let folded = rawText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()

        if let entry = Self.entries.first(where: { entry in
            entry.aliases.contains { folded.contains($0.lowercased()) }
        }) {
            return NormalizedLocation(
                rawText: rawText,
                city: entry.city,
                province: entry.province,
                country: "China",
                tier: entry.tier,
                score: entry.score,
                confidence: 0.95
            )
        }

        if let country = Self.preferredCountries.first(where: { entry in
            folded.range(of: entry.pattern, options: .regularExpression) != nil
                || entry.ideographs.contains(where: rawText.contains)
        }) {
            return NormalizedLocation(
                rawText: rawText,
                city: nil,
                province: nil,
                country: country.name,
                tier: 1,
                score: 100,
                confidence: 0.95
            )
        }

        if folded.contains("guangdong") || rawText.contains("广东") || rawText.contains("廣東") {
            return NormalizedLocation(
                rawText: rawText,
                city: nil,
                province: "Guangdong",
                country: "China",
                tier: 2,
                score: 85,
                confidence: 0.9
            )
        }

        if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NormalizedLocation(
                rawText: rawText,
                city: nil,
                province: nil,
                country: nil,
                tier: 6,
                score: 10,
                confidence: 0
            )
        }

        return NormalizedLocation(
            rawText: rawText,
            city: nil,
            province: nil,
            country: nil,
            tier: 5,
            score: 30,
            confidence: 0.25
        )
    }
}
