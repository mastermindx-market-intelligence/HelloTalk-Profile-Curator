import Foundation

public struct VLMConfiguration: Codable, Hashable, Sendable {
    public var baseURL: URL?
    public var model: String
    public var requestTimeoutSeconds: Double
    public var maximumRetries: Int

    public init(
        baseURL: URL? = nil,
        model: String = "qwen3.5:9b",
        requestTimeoutSeconds: Double = 45,
        maximumRetries: Int = 2
    ) {
        self.baseURL = baseURL
        self.model = model
        self.requestTimeoutSeconds = min(180, max(5, requestTimeoutSeconds))
        self.maximumRetries = min(5, max(0, maximumRetries))
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
}

public struct VisualAppealResult: Codable, Hashable, Sendable {
    public let visualAppealScore: Double
    public let confidence: Double
    public let photoQualityPenalty: Double
    public let notes: [String]

    private enum CodingKeys: String, CodingKey {
        case visualAppealScore = "visual_appeal_score"
        case confidence
        case photoQualityPenalty = "photo_quality_penalty"
        case notes
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
}

public enum VLMPromptLibrary {
    public static let faceVerificationVersion = "face-verification-v1"
    public static let visualAppealVersion = "visual-appeal-v1"
    public static let lifestyleVersion = "lifestyle-evidence-v1"

    public static let faceVerification = """
    Return JSON only. Determine whether the provided crop contains a photographic human face that is clear enough for presentation scoring. Distinguish illustration/anime and heavy filtering. Do not identify the person or infer protected traits. Use keys: is_photographic_human_face, is_illustration_or_anime, is_heavily_filtered, is_face_clear_enough_to_score, confidence.
    """

    public static let visualAppeal = """
    Return JSON only. Estimate generic visible facial presentation and photographic clarity, not identity, ethnicity, personality, income, or compatibility. Score 0 to 100. Use keys: visual_appeal_score, confidence, photo_quality_penalty, notes. Treat this as a model estimate, not an objective fact.
    """

    public static let lifestyle = """
    Return JSON only. Score repeated, observable lifestyle presentation from 0 to 100 using visible evidence. Never claim actual wealth, family background, social class, or protected traits. One ambiguous logo or one hotel visit must not dominate. Use keys: lifestyle_affluence_signal, confidence, evidence (category, strength, source_image_id, explanation), actual_wealth. actual_wealth must be unknown.
    """
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
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        let cleaned = Self.cleanJSON(envelope.message.content)
        guard let result = cleaned.data(using: .utf8) else { throw VLMClientError.invalidResponse }
        return result
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
    private struct ChatMessage: Codable { let role: String; let content: String; let images: [String] }
    private struct ChatResponse: Decodable { let message: ChatMessage }
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
