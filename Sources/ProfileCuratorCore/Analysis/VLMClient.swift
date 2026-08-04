import Foundation

public struct VLMConfiguration: Codable, Hashable, Sendable {
    public var baseURL: URL?
    public var model: String
    public var requestTimeoutSeconds: Double
    public var maximumRetries: Int
    public var enforceNoFaceForPrimary: Bool

    public init(
        baseURL: URL? = nil,
        model: String = "qwen3.5:9b",
        requestTimeoutSeconds: Double = 45,
        maximumRetries: Int = 2,
        enforceNoFaceForPrimary: Bool = true
    ) {
        self.baseURL = baseURL
        self.model = model
        self.requestTimeoutSeconds = min(180, max(5, requestTimeoutSeconds))
        self.maximumRetries = min(5, max(0, maximumRetries))
        self.enforceNoFaceForPrimary = enforceNoFaceForPrimary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseURL: try container.decodeIfPresent(URL.self, forKey: .baseURL),
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? "qwen3.5:9b",
            requestTimeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 45,
            maximumRetries: try container.decodeIfPresent(Int.self, forKey: .maximumRetries) ?? 2,
            enforceNoFaceForPrimary: try container.decodeIfPresent(Bool.self, forKey: .enforceNoFaceForPrimary) ?? true
        )
    }

    public func validatedBaseURL() throws -> URL {
        guard let baseURL else { throw VLMClientError.endpointNotConfigured }
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw VLMClientError.invalidEndpoint
        }
        return baseURL
    }
}

public final class VLMConfigurationStore: @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func defaultStore(fileManager: FileManager = .default) throws -> VLMConfigurationStore {
        let root = try ProfileRepository.defaultDataDirectory(fileManager: fileManager)
        return VLMConfigurationStore(fileURL: root.appendingPathComponent("config.json"))
    }

    public func load() throws -> VLMConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return VLMConfiguration() }
        return try JSONDecoder().decode(VLMConfiguration.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ configuration: VLMConfiguration) throws {
        _ = try configuration.baseURL.map { _ in try configuration.validatedBaseURL() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

public struct VLMHealth: Hashable, Sendable {
    public let reachable: Bool
    public let configuredModelAvailable: Bool
    public let availableModels: [String]
}

public struct FaceVerificationResult: Codable, Hashable, Sendable {
    public let isPhotographicHumanFace: Bool
    public let isIllustrationOrAnime: Bool
    public let isHeavilyFiltered: Bool
    public let isFaceClearEnoughToScore: Bool
    public let confidence: Double

    private enum CodingKeys: String, CodingKey {
        case isPhotographicHumanFace = "is_photographic_human_face"
        case isIllustrationOrAnime = "is_illustration_or_anime"
        case isHeavilyFiltered = "is_heavily_filtered"
        case isFaceClearEnoughToScore = "is_face_clear_enough_to_score"
        case confidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPhotographicHumanFace = try container.decode(Bool.self, forKey: .isPhotographicHumanFace)
        isIllustrationOrAnime = try container.decode(Bool.self, forKey: .isIllustrationOrAnime)
        isHeavilyFiltered = try container.decode(Bool.self, forKey: .isHeavilyFiltered)
        isFaceClearEnoughToScore = try container.decode(Bool.self, forKey: .isFaceClearEnoughToScore)
        confidence = normalizedConfidence(try container.decode(Double.self, forKey: .confidence))
    }
}

public struct VisualAppealResult: Codable, Hashable, Sendable {
    public let visualAppealScore: Double
    public let confidence: Double
    public let photoQualityPenalty: Double
    public let notes: [String]
    public let bestSourceImageID: String?

    private enum CodingKeys: String, CodingKey {
        case visualAppealScore = "visual_appeal_score"
        case confidence
        case photoQualityPenalty = "photo_quality_penalty"
        case notes
        case bestSourceImageID = "best_source_image_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visualAppealScore = min(100, max(0, try container.decode(Double.self, forKey: .visualAppealScore)))
        confidence = normalizedConfidence(try container.decode(Double.self, forKey: .confidence))
        photoQualityPenalty = min(100, max(0, try container.decode(Double.self, forKey: .photoQualityPenalty)))
        if let values = try? container.decode([String].self, forKey: .notes) {
            notes = values
        } else {
            notes = [try container.decode(String.self, forKey: .notes)]
        }
        bestSourceImageID = try container.decodeIfPresent(String.self, forKey: .bestSourceImageID)
    }
}

public struct TattooDetectionResult: Codable, Hashable, Sendable {
    public let hasVisibleTattoo: Bool
    public let confidence: Double
    public let sourceImageIDs: [String]
    public let notes: [String]

    public var isConfirmed: Bool {
        hasVisibleTattoo && confidence >= 0.75 && !sourceImageIDs.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case hasVisibleTattoo = "visible_tattoo"
        case confidence = "tattoo_confidence"
        case sourceImageIDs = "source_image_ids"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasVisibleTattoo = try container.decode(Bool.self, forKey: .hasVisibleTattoo)
        confidence = normalizedConfidence(try container.decode(Double.self, forKey: .confidence))
        sourceImageIDs = try container.decodeIfPresent([String].self, forKey: .sourceImageIDs) ?? []
        if let values = try? container.decode([String].self, forKey: .notes) {
            notes = values
        } else if let value = try? container.decode(String.self, forKey: .notes) {
            notes = [value]
        } else {
            notes = []
        }
    }
}

public struct LifestyleEvidence: Codable, Hashable, Sendable {
    public let category: String
    public let strength: String
    public let sourceImageID: String
    public let explanation: String

    private enum CodingKeys: String, CodingKey {
        case category, strength, explanation
        case sourceImageID = "source_image_id"
    }

    public init(category: String, strength: String, sourceImageID: String, explanation: String) {
        self.category = category
        self.strength = strength
        self.sourceImageID = sourceImageID
        self.explanation = explanation
    }
}

public struct LifestyleSignalResult: Codable, Hashable, Sendable {
    public let lifestyleAffluenceSignal: Double
    public let confidence: Double
    public let evidence: [LifestyleEvidence]
    public let actualWealth: String

    private enum CodingKeys: String, CodingKey {
        case lifestyleAffluenceSignal = "lifestyle_affluence_signal"
        case confidence, evidence
        case actualWealth = "actual_wealth"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lifestyleAffluenceSignal = min(100, max(0, try container.decode(Double.self, forKey: .lifestyleAffluenceSignal)))
        confidence = normalizedConfidence(try container.decode(Double.self, forKey: .confidence))
        evidence = try container.decode([LifestyleEvidence].self, forKey: .evidence)
        actualWealth = try container.decode(String.self, forKey: .actualWealth)
    }

    public init(lifestyleAffluenceSignal: Double, confidence: Double, evidence: [LifestyleEvidence]) {
        self.lifestyleAffluenceSignal = min(100, max(0, lifestyleAffluenceSignal))
        self.confidence = normalizedConfidence(confidence)
        self.evidence = evidence
        actualWealth = "unknown"
    }
}

private func normalizedConfidence(_ value: Double) -> Double {
    let ratio = value > 1 ? value / 100 : value
    return min(1, max(0, ratio))
}

public struct AnalysisImageReference: Codable, Hashable, Sendable, Identifiable {
    public let sourceImageID: String
    public let filePath: String

    public var id: String { sourceImageID }

    public init(sourceImageID: String, filePath: String) {
        self.sourceImageID = sourceImageID
        self.filePath = filePath
    }

    private enum CodingKeys: String, CodingKey {
        case sourceImageID = "source_image_id"
        case filePath = "file_path"
    }
}

public struct AnalysisRequestTrace: Codable, Hashable, Sendable {
    public let imageCount: Int
    public let images: [AnalysisImageReference]

    public init(images: [AnalysisImageReference]) {
        self.imageCount = images.count
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case imageCount = "image_count"
        case images
    }
}

public extension AnalysisRunRecord {
    var requestTrace: AnalysisRequestTrace? {
        guard let data = requestJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AnalysisRequestTrace.self, from: data)
    }

    var lifestyleEvidence: [LifestyleEvidence] {
        guard analysisType == AnalysisType.lifestyle.rawValue,
              let responseJSON,
              let data = responseJSON.data(using: .utf8),
              let result = try? JSONDecoder().decode(LifestyleSignalResult.self, from: data) else {
            return []
        }
        return result.evidence
    }

    var faceVerificationResult: FaceVerificationResult? {
        decodeResponse(FaceVerificationResult.self, expectedType: .faceVerification)
    }

    var visualAppealResult: VisualAppealResult? {
        decodeResponse(VisualAppealResult.self, expectedType: .visualAppeal)
    }

    var tattooDetectionResult: TattooDetectionResult? {
        decodeResponse(TattooDetectionResult.self, expectedType: .tattooDetection)
    }

    var lifestyleSignalResult: LifestyleSignalResult? {
        decodeResponse(LifestyleSignalResult.self, expectedType: .lifestyle)
    }

    func lifestyleEvidence(sourceImageID: String) -> [LifestyleEvidence] {
        lifestyleEvidence.filter { $0.sourceImageID == sourceImageID }
    }

    private func decodeResponse<T: Decodable>(_ type: T.Type, expectedType: AnalysisType) -> T? {
        guard analysisType == expectedType.rawValue,
              let responseJSON,
              let data = responseJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

public enum VLMPromptLibrary {
    public static let faceVerificationVersion = "face-verification-v2"
    public static let visualAppealVersion = "visual-appeal-v3"
    public static let tattooDetectionVersion = "tattoo-detection-v1"
    public static let lifestyleVersion = "lifestyle-evidence-v3"

    public static let faceVerification = """
    Return JSON only. Determine whether the provided crop contains a photographic human face that is clear enough for presentation scoring. Distinguish illustration/anime and heavy filtering. Do not identify the person or infer protected traits. Use keys: is_photographic_human_face, is_illustration_or_anime, is_heavily_filtered, is_face_clear_enough_to_score, confidence, source_image_ids. confidence must be from 0.0 to 1.0.
    """

    public static let visualAppeal = """
    Return JSON only. Estimate generic visible facial presentation, not identity, ethnicity, personality, income, or compatibility. Compare every attached image and base visual_appeal_score on the single best sufficiently credible view of the natural face. A novelty overlay such as dog ears, an animal nose, stickers, beauty smoothing, blur, crop, lighting, or compression lowers evidence confidence and photo_quality_penalty quality; it must NOT be mathematically subtracted from visual_appeal_score. Ignore the overlay itself and prefer another clearer image when available. If every view is filtered, give a conservative best estimate and lower confidence instead of defaulting the face score to 50. Score 0 to 100. Use keys: visual_appeal_score, confidence, photo_quality_penalty, best_source_image_id, notes, source_image_ids. best_source_image_id must be one supplied image ID. confidence must be from 0.0 to 1.0, photo_quality_penalty must be from 0 to 100, and notes must be an array of strings. Treat this as a model estimate, not an objective fact.
    """

    public static let tattooDetection = """
    Return JSON only. Inspect every attached image for a clearly visible permanent tattoo on the profile subject's skin. Do not infer hidden tattoos. Do not count clothing prints, jewelry, makeup, stickers, shadows, hair, image overlays, or background art. Set visible_tattoo true only when ink-like body art is visibly supported by at least one exact supplied source image ID; otherwise set it false. Use keys: visible_tattoo, tattoo_confidence, source_image_ids, notes. tattoo_confidence must be from 0.0 to 1.0. source_image_ids must contain only the exact supplied IDs that visibly support the finding and must be empty when visible_tattoo is false. notes must be a short array of factual visual observations without identity or personality claims.
    """

    public static let lifestyle = """
    Return JSON only. Score repeated, observable lifestyle presentation from 0 to 100 using visible evidence. Never claim actual wealth, family background, social class, or protected traits. One ambiguous logo or one hotel visit must not dominate. Use keys: lifestyle_affluence_signal, confidence, evidence (category, strength, source_image_id, explanation), actual_wealth. confidence must be from 0.0 to 1.0. Category must be one of: travel, dining, fashion, fitness, social_activity, animal_interaction, outdoor_activity, digital_engagement, home_environment, education, other. Every evidence item must use one of the supplied source image IDs. Before returning JSON, cross-check each evidence description against that exact image ordinal so citations cannot shift to an adjacent image. actual_wealth must be unknown.
    """

    public static func prompt(_ base: String, imageReferences: [AnalysisImageReference]) -> String {
        guard !imageReferences.isEmpty else { return base }
        let orderedIDs = imageReferences.map(\.sourceImageID).joined(separator: ", ")
        return """
        \(base)

        Attached images are ordered and identified as: \(orderedIDs). Use only these exact IDs when citing source_image_id or source_image_ids.
        """
    }
}

public protocol VLMClientProtocol: Sendable {
    func health() async throws -> VLMHealth
    func generateJSON(prompt: String, images: [Data]) async throws -> Data
}

public actor OllamaVLMClient: VLMClientProtocol {
    private let configuration: VLMConfiguration
    private let session: URLSession

    public init(configuration: VLMConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = configuration.requestTimeoutSeconds
            config.timeoutIntervalForResource = configuration.requestTimeoutSeconds + 15
            self.session = URLSession(configuration: config)
        }
    }

    public func health() async throws -> VLMHealth {
        let request = try makeRequest(path: "api/tags", method: "GET")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        let names = tags.models.map(\.name)
        return VLMHealth(reachable: true, configuredModelAvailable: names.contains(configuration.model), availableModels: names)
    }

    public func generateJSON(prompt: String, images: [Data]) async throws -> Data {
        var lastError: Error?
        for attempt in 0...configuration.maximumRetries {
            do {
                return try await send(prompt: prompt, images: images)
            } catch {
                lastError = error
                guard attempt < configuration.maximumRetries else { break }
                try await Task.sleep(for: .milliseconds(300 * (1 << attempt)))
            }
        }
        throw lastError ?? VLMClientError.invalidResponse
    }

    private func send(prompt: String, images: [Data]) async throws -> Data {
        var request = try makeRequest(path: "api/chat", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: configuration.model,
            messages: [ChatMessage(role: "user", content: prompt, images: images.map { $0.base64EncodedString() })],
            stream: false,
            think: false,
            format: "json",
            options: ["temperature": 0]
        ))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try Self.decodeJSONPayload(data)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let base = try configuration.validatedBaseURL()
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeoutSeconds)
        request.httpMethod = method
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw VLMClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw VLMClientError.httpStatus(http.statusCode) }
    }

    private static func cleanJSON(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeJSONPayload(_ data: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        let cleaned = Self.cleanJSON(envelope.message.content)
        guard let result = cleaned.data(using: .utf8) else { throw VLMClientError.invalidResponse }
        return result
    }

    private struct TagsResponse: Decodable { let models: [TagModel] }
    private struct TagModel: Decodable { let name: String }
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let think: Bool
        let format: String
        let options: [String: Double]
    }
    private struct ChatMessage: Encodable { let role: String; let content: String; let images: [String] }
    private struct ChatResponse: Decodable { let message: ResponseMessage }
    private struct ResponseMessage: Decodable { let content: String }
}

public enum VLMClientError: Error, LocalizedError, Sendable {
    case endpointNotConfigured
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .endpointNotConfigured: "The Qwen/Ollama endpoint is not configured yet."
        case .invalidEndpoint: "Use a valid HTTP or HTTPS Tailscale/MagicDNS Ollama URL without credentials or query parameters."
        case .invalidResponse: "The Qwen/Ollama service returned an invalid response."
        case .httpStatus(let status): "The Qwen/Ollama service returned HTTP \(status)."
        }
    }
}
