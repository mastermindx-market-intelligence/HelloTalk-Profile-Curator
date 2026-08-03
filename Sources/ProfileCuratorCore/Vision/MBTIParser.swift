import Foundation

public struct MBTIParser: Sendable {
    private static let expression = try! NSRegularExpression(
        pattern: #"(?<![A-Z])([IE][NS][FT][JP])(?![A-Z])"#,
        options: [.caseInsensitive]
    )

    public init() {}

    public func matches(in observations: [OCRObservation], minimumConfidence: Float = 0.72) -> [MBTIMatch] {
        observations.flatMap { observation -> [MBTIMatch] in
            guard observation.confidence >= minimumConfidence else { return [] }
            let uppercased = observation.text.uppercased()
            let range = NSRange(uppercased.startIndex..<uppercased.endIndex, in: uppercased)

            return Self.expression.matches(in: uppercased, range: range).compactMap { result in
                guard
                    let matchRange = Range(result.range(at: 1), in: uppercased),
                    let type = MBTIType(rawValue: String(uppercased[matchRange]))
                else {
                    return nil
                }
                return MBTIMatch(type: type, source: observation)
            }
        }
    }

    public func firstTarget(in observations: [OCRObservation], minimumConfidence: Float = 0.72) -> MBTIMatch? {
        matches(in: observations, minimumConfidence: minimumConfidence).first { $0.type.group != nil }
    }
}
