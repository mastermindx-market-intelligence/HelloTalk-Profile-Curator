import Foundation

public enum MBTIGroup: String, Codable, Sendable {
    case primary
    case secondary
}

public enum MBTIType: String, CaseIterable, Codable, Sendable {
    case infj = "INFJ"
    case intj = "INTJ"
    case infp = "INFP"
    case intp = "INTP"
    case enfp = "ENFP"
    case entp = "ENTP"
    case enfj = "ENFJ"
    case entj = "ENTJ"
    case isfj = "ISFJ"
    case istj = "ISTJ"
    case isfp = "ISFP"
    case istp = "ISTP"
    case esfp = "ESFP"
    case estp = "ESTP"
    case esfj = "ESFJ"
    case estj = "ESTJ"

    public var group: MBTIGroup? {
        switch self {
        case .infj, .intj:
            .primary
        case .infp, .intp, .enfp, .entp, .enfj:
            .secondary
        default:
            nil
        }
    }
}

public struct MBTIMatch: Hashable, Sendable {
    public let type: MBTIType
    public let source: OCRObservation

    public init(type: MBTIType, source: OCRObservation) {
        self.type = type
        self.source = source
    }
}
