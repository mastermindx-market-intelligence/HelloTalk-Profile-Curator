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
            let imageLimit = job.analysisType == .tattooDetection ? 5 : 3
            let selectedPaths = Array(job.mediaPaths.prefix(imageLimit))
            let imageReferences = selectedPaths.enumerated().map {
                AnalysisImageReference(sourceImageID: "image-\($0.offset + 1)", filePath: $0.element)
            }
            let images = try selectedPaths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
            let response = try await generateResponse(
                type: job.analysisType,
                references: imageReferences,
                images: images
            )
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
        case .tattooDetection: VLMPromptLibrary.tattooDetection
        case .lifestyle: VLMPromptLibrary.lifestyle
        }
    }

    private func generateResponse(
        type: AnalysisType,
        references: [AnalysisImageReference],
        images: [Data]
    ) async throws -> Data {
        guard type == .lifestyle, !references.isEmpty else {
            let prompt = VLMPromptLibrary.prompt(Self.prompt(for: type), imageReferences: references)
            return try await client.generateJSON(prompt: prompt, images: images)
        }

        var results: [LifestyleSignalResult] = []
        var evidence: [LifestyleEvidence] = []
        for (reference, image) in zip(references, images) {
            let prompt = VLMPromptLibrary.prompt(VLMPromptLibrary.lifestyle, imageReferences: [reference]) + """

            This request contains exactly one image. Every evidence source_image_id must be \(reference.sourceImageID).
            """
            let response = try await client.generateJSON(prompt: prompt, images: [image])
            let result = try JSONDecoder().decode(LifestyleSignalResult.self, from: response)
            guard result.actualWealth.lowercased() == "unknown" else { throw VLMClientError.invalidResponse }
            results.append(result)
            evidence.append(contentsOf: result.evidence.map {
                LifestyleEvidence(
                    category: $0.category,
                    strength: $0.strength,
                    sourceImageID: reference.sourceImageID,
                    explanation: $0.explanation
                )
            })
        }

        let totalWeight = results.reduce(0.0) { $0 + max(0.05, $1.confidence) }
        let aggregateScore = results.reduce(0.0) {
            $0 + $1.lifestyleAffluenceSignal * max(0.05, $1.confidence)
        } / totalWeight
        let aggregateConfidence = results.map(\.confidence).reduce(0, +) / Double(results.count)
        let aggregate = LifestyleSignalResult(
            lifestyleAffluenceSignal: aggregateScore,
            confidence: aggregateConfidence,
            evidence: evidence
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(aggregate)
    }

    private enum DecodedResult {
        case faceVerification(FaceVerificationResult)
        case visualAppeal(VisualAppealResult)
        case tattooDetection(TattooDetectionResult)
        case lifestyle(LifestyleSignalResult)
    }

    private static func decode(_ data: Data, type: AnalysisType) throws -> DecodedResult {
        switch type {
        case .faceVerification:
            return .faceVerification(try JSONDecoder().decode(FaceVerificationResult.self, from: data))
        case .visualAppeal:
            return .visualAppeal(try JSONDecoder().decode(VisualAppealResult.self, from: data))
        case .tattooDetection:
            return .tattooDetection(try JSONDecoder().decode(TattooDetectionResult.self, from: data))
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
        var hasVisibleTattoo = profile.hasVisibleTattoo
        var confidence = profile.analysisConfidence
        switch result {
        case .faceVerification(let verification):
            confidence = max(confidence, normalizedConfidence(verification.confidence))
        case .visualAppeal(let value):
            face = value.visualAppealScore
            confidence = combinedConfidence(existing: confidence, new: value.confidence)
        case .tattooDetection(let value):
            hasVisibleTattoo = value.isConfirmed
            confidence = combinedConfidence(existing: confidence, new: value.confidence)
        case .lifestyle(let value):
            lifestyle = ProfileSignalScorer().enrichLifestyle(
                visualScore: value.lifestyleAffluenceSignal,
                profileSignalScore: profile.profileSignalsScore
            )
            confidence = combinedConfidence(existing: confidence, new: value.confidence)
        }
        if hasVisibleTattoo { lifestyle = 0 }

        let overall: Double?
        if let face, let lifestyle {
            let components = ScoreComponents(
                face: face,
                lifestyle: lifestyle,
                location: Double(profile.locationScore ?? 10),
                completeness: profile.profileCompletenessScore,
                confidence: confidence
            )
            if let group = profile.typedGroup {
                overall = ScoringEngine().score(
                    group: group,
                    components: components,
                    locationMissing: profile.isLocationMissing
                ).overall
            } else if profile.isPreferredLocationNoMBTI {
                overall = ScoringEngine().scorePreferredLocationNoMBTI(components: components).overall
            } else if profile.isUnknownLocationNoMBTI {
                overall = ScoringEngine().scorePreferredLocationNoMBTI(
                    components: components,
                    locationMissing: true
                ).overall
            } else {
                overall = profile.overallScore
            }
        } else {
            overall = profile.overallScore
        }
        try repository.updateScores(
            id: profileID,
            face: face,
            lifestyle: lifestyle,
            overall: overall,
            confidence: confidence,
            hasVisibleTattoo: hasVisibleTattoo
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
