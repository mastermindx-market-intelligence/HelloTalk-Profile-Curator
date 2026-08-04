import Foundation
@preconcurrency import GRDB

public enum AnalysisJobState: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case retryWaiting = "retry_waiting"
    case failed
}

public struct AnalysisJobRecord: Codable, FetchableRecord, PersistableRecord, Hashable, Sendable, Identifiable {
    public static let databaseTableName = "analysis_jobs"
    public let id: String
    public let profileID: String
    public let analysisType: AnalysisType
    public let modelName: String
    public let promptVersion: String
    public let mediaPaths: [String]
    public let state: AnalysisJobState
    public let attemptCount: Int
    public let nextAttemptAt: Date?
    public let lastError: String?
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case analysisType = "analysis_type"
        case modelName = "model_name"
        case promptVersion = "prompt_version"
        case mediaPaths = "media_paths"
        case state
        case attemptCount = "attempt_count"
        case nextAttemptAt = "next_attempt_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public actor AnalysisQueueProcessor {
    private let repository: ProfileRepository
    private let client: any VLMClientProtocol
    private let configuration: VLMConfiguration

    public init(repository: ProfileRepository, client: any VLMClientProtocol, configuration: VLMConfiguration) {
        self.repository = repository
        self.client = client
        self.configuration = configuration
    }

    @discardableResult
    public func processNext(now: Date = Date()) async -> Bool {
        guard let job = try? repository.nextAnalysisJob(now: now) else { return false }
        do {
            try repository.updateAnalysisJob(id: job.id, state: .running, attemptCount: job.attemptCount + 1, nextAttemptAt: nil, error: nil, now: now)
            let selectedPaths = Array(job.mediaPaths.prefix(3))
            let imageReferences = selectedPaths.enumerated().map {
                AnalysisImageReference(sourceImageID: "image-\($0.offset + 1)", filePath: $0.element)
            }
            let prompt = VLMPromptLibrary.prompt(Self.prompt(for: job.analysisType), imageReferences: imageReferences)
            let images = try selectedPaths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
            let response = try await client.generateJSON(prompt: prompt, images: images)
            let decoded = try Self.decode(response, type: job.analysisType)
            let requestTrace = try JSONEncoder().encode(AnalysisRequestTrace(images: imageReferences))
            let run = AnalysisRunRecord(
                id: UUID().uuidString,
                profileID: job.profileID,
                analysisType: job.analysisType.rawValue,
                modelName: job.modelName,
                promptVersion: job.promptVersion,
                requestJSON: String(decoding: requestTrace, as: UTF8.self),
                responseJSON: String(data: response, encoding: .utf8),
                startedAt: now,
                completedAt: Date(),
                success: true,
                error: nil
            )
            try repository.saveAnalysisRun(run)
            try apply(decoded, to: job.profileID)
            try repository.updateAnalysisJob(id: job.id, state: .succeeded, attemptCount: job.attemptCount + 1, nextAttemptAt: nil, error: nil)
            return true
        } catch {
            let attempts = job.attemptCount + 1
            let final = attempts > configuration.maximumRetries
            let delay = min(300.0, pow(2, Double(attempts)) * 5)
            try? repository.updateAnalysisJob(
                id: job.id,
                state: final ? .failed : .retryWaiting,
                attemptCount: attempts,
                nextAttemptAt: final ? nil : now.addingTimeInterval(delay),
                error: error.localizedDescription
            )
            return false
        }
    }

    private static func prompt(for type: AnalysisType) -> String {
        switch type {
        case .faceVerification: VLMPromptLibrary.faceVerification
        case .visualAppeal: VLMPromptLibrary.visualAppeal
        case .lifestyle: VLMPromptLibrary.lifestyle
        }
    }

    private enum DecodedResult {
        case faceVerification(FaceVerificationResult)
        case visualAppeal(VisualAppealResult)
        case lifestyle(LifestyleSignalResult)
    }

    private static func decode(_ data: Data, type: AnalysisType) throws -> DecodedResult {
        switch type {
        case .faceVerification:
            return .faceVerification(try JSONDecoder().decode(FaceVerificationResult.self, from: data))
        case .visualAppeal:
            return .visualAppeal(try JSONDecoder().decode(VisualAppealResult.self, from: data))
        case .lifestyle:
            let result = try JSONDecoder().decode(LifestyleSignalResult.self, from: data)
            guard result.actualWealth.lowercased() == "unknown" else { throw VLMClientError.invalidResponse }
            return .lifestyle(result)
        }
    }

    private func apply(_ result: DecodedResult, to profileID: String) throws {
        guard let profile = try repository.profile(id: profileID) else { return }
        var face = profile.faceScore
        var lifestyle = profile.lifestyleScore
        var confidence = profile.analysisConfidence
        switch result {
        case .faceVerification(let verification):
            confidence = max(confidence, normalizedConfidence(verification.confidence))
        case .visualAppeal(let value):
            face = min(100, max(0, value.visualAppealScore - value.photoQualityPenalty))
            confidence = combinedConfidence(existing: confidence, new: value.confidence)
        case .lifestyle(let value):
            lifestyle = min(100, max(0, value.lifestyleAffluenceSignal))
            confidence = combinedConfidence(existing: confidence, new: value.confidence)
        }

        let overall: Double?
        if let face, let lifestyle, let group = profile.typedGroup {
            overall = ScoringEngine().score(
                group: group,
                components: ScoreComponents(
                    face: face,
                    lifestyle: lifestyle,
                    location: Double(profile.locationScore ?? 10),
                    completeness: profile.profileCompletenessScore,
                    confidence: confidence
                )
            ).overall
        } else {
            overall = profile.overallScore
        }
        try repository.updateScores(
            id: profileID,
            face: face,
            lifestyle: lifestyle,
            overall: overall,
            confidence: confidence
        )
    }

    private func combinedConfidence(existing: Double, new: Double) -> Double {
        let normalized = normalizedConfidence(new)
        return existing > 0 ? (existing + normalized) / 2 : normalized
    }

    private func normalizedConfidence(_ value: Double) -> Double {
        let ratio = value > 1 ? value / 100 : value
        return min(1, max(0, ratio))
    }
}
