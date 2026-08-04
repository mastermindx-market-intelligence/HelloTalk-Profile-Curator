import Foundation
import XCTest
@testable import ProfileCuratorCore

final class VLMIntegrationTests: XCTestCase {
    func testFreshConfigurationUsesCurrentVisionDefault() {
        XCTAssertEqual(VLMConfiguration().model, "qwen3.5:9b")
        XCTAssertTrue(VLMConfiguration().enforceNoFaceForPrimary)
    }

    func testLegacyConfigurationDefaultsPrimaryNoFaceRuleOn() throws {
        let legacy = Data(#"{"baseURL":null,"model":"qwen3.5:9b","requestTimeoutSeconds":45,"maximumRetries":2}"#.utf8)
        let decoded = try JSONDecoder().decode(VLMConfiguration.self, from: legacy)
        XCTAssertTrue(decoded.enforceNoFaceForPrimary)
    }

    func testConfigurationRejectsUnsafeOrMalformedEndpoint() throws {
        XCTAssertThrowsError(try VLMConfiguration().validatedBaseURL())
        XCTAssertThrowsError(try VLMConfiguration(baseURL: URL(string: "file:///tmp/ollama")).validatedBaseURL())
        XCTAssertNoThrow(try VLMConfiguration(baseURL: URL(string: "http://qwen-box:11434")).validatedBaseURL())
    }

    func testOllamaAssistantMessageMayOmitRequestOnlyImagesField() throws {
        let envelope = Data(#"{"message":{"role":"assistant","content":"{\"visual_appeal_score\":82}"}}"#.utf8)

        let payload = try OllamaVLMClient.decodeJSONPayload(envelope)

        XCTAssertEqual(String(decoding: payload, as: UTF8.self), #"{"visual_appeal_score":82}"#)
    }

    func testVisualAppealAcceptsSingleNoteAndClampsNegativePenalty() throws {
        let response = Data(#"{"visual_appeal_score":82,"confidence":0.95,"photo_quality_penalty":-3,"notes":"clear"}"#.utf8)

        let result = try JSONDecoder().decode(VisualAppealResult.self, from: response)

        XCTAssertEqual(result.notes, ["clear"])
        XCTAssertEqual(result.photoQualityPenalty, 0)
        XCTAssertEqual(result.visualAppealScore, 82)
    }

    func testQwenScoresAndConfidenceAreNormalizedAtDecodeBoundary() throws {
        let visual = Data(#"{"visual_appeal_score":140,"confidence":95,"photo_quality_penalty":120,"notes":[]}"#.utf8)
        let lifestyle = Data(#"{"lifestyle_affluence_signal":-8,"confidence":85,"evidence":[],"actual_wealth":"unknown"}"#.utf8)
        let face = Data(#"{"is_photographic_human_face":true,"is_illustration_or_anime":false,"is_heavily_filtered":false,"is_face_clear_enough_to_score":true,"confidence":98}"#.utf8)

        let visualResult = try JSONDecoder().decode(VisualAppealResult.self, from: visual)
        let lifestyleResult = try JSONDecoder().decode(LifestyleSignalResult.self, from: lifestyle)
        let faceResult = try JSONDecoder().decode(FaceVerificationResult.self, from: face)

        XCTAssertEqual(visualResult.visualAppealScore, 100)
        XCTAssertEqual(visualResult.photoQualityPenalty, 100)
        XCTAssertEqual(visualResult.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(lifestyleResult.lifestyleAffluenceSignal, 0)
        XCTAssertEqual(lifestyleResult.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(faceResult.confidence, 0.98, accuracy: 0.001)
    }

    func testFaceAnalysisPrefersCloseupOverSmallFaceInsideScreenshot() {
        let closeup = mediaRecord(id: "closeup", sequence: 2, ratio: 0.54, quality: 0.52)
        let screenshot = mediaRecord(id: "screenshot", sequence: 1, ratio: 0.06, quality: 0.60)
        let portrait = mediaRecord(id: "portrait", sequence: 3, ratio: 0.18, quality: 0.45)

        let selected = AnalysisMediaSelector.faceMedia(from: [screenshot, portrait, closeup])

        XCTAssertEqual(selected.map(\.id), ["closeup", "portrait"])
    }

    func testOfflineFailureStaysInPersistentRetryQueue() async throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(usernameRaw: "@offline", age: 19, gender: .female, mbti: .infj))
        _ = try context.repository.enqueueAnalysis(
            profileID: profile.id,
            type: .visualAppeal,
            modelName: "qwen3-vl:4b",
            promptVersion: VLMPromptLibrary.visualAppealVersion,
            mediaPaths: []
        )
        let processor = AnalysisQueueProcessor(
            repository: context.repository,
            client: MockVLMClient(result: .failure(VLMClientError.httpStatus(503))),
            configuration: VLMConfiguration(maximumRetries: 2)
        )

        let processed = await processor.processNext()
        XCTAssertFalse(processed)
        let jobs = try context.repository.analysisJobs(profileID: profile.id)
        XCTAssertEqual(jobs.first?.state, .retryWaiting)
        XCTAssertEqual(jobs.first?.attemptCount, 1)
        XCTAssertNotNil(jobs.first?.nextAttemptAt)
    }

    func testValidStructuredResponseCompletesQueuedJob() async throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(usernameRaw: "@success", age: 20, gender: .female, mbti: .intj))
        _ = try context.repository.enqueueAnalysis(
            profileID: profile.id,
            type: .visualAppeal,
            modelName: "qwen3-vl:4b",
            promptVersion: VLMPromptLibrary.visualAppealVersion,
            mediaPaths: []
        )
        let response = Data(#"{"visual_appeal_score":82,"confidence":0.7,"photo_quality_penalty":2,"notes":["clear"]}"#.utf8)
        let processor = AnalysisQueueProcessor(
            repository: context.repository,
            client: MockVLMClient(result: .success(response)),
            configuration: VLMConfiguration()
        )

        let processed = await processor.processNext()
        XCTAssertTrue(processed)
        XCTAssertEqual(try context.repository.analysisJobs(profileID: profile.id).first?.state, .succeeded)
        let updated = try XCTUnwrap(context.repository.profile(id: profile.id))
        XCTAssertEqual(try XCTUnwrap(updated.faceScore), 80, accuracy: 0.001)
        XCTAssertEqual(updated.analysisConfidence, 0.7, accuracy: 0.001)
        XCTAssertEqual(try context.repository.analysisRuns(profileID: profile.id).count, 1)
    }

    func testSuccessfulRunPersistsOrderedImageEvidenceLinks() async throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@evidence",
            age: 19,
            gender: .female,
            mbti: .infj,
            hobbies: ["Psychology"],
            education: "International Student",
            occupation: "Student"
        ))
        let first = context.root.appendingPathComponent("first.png")
        let second = context.root.appendingPathComponent("second.png")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        _ = try context.repository.enqueueAnalysis(
            profileID: profile.id,
            type: .lifestyle,
            modelName: "qwen3.5:9b",
            promptVersion: VLMPromptLibrary.lifestyleVersion,
            mediaPaths: [first.path, second.path]
        )
        let response = Data(#"{"lifestyle_affluence_signal":66,"confidence":80,"evidence":[{"category":"travel","strength":"moderate","source_image_id":"image-2","explanation":"Visible landmark"}],"actual_wealth":"unknown"}"#.utf8)
        let client = MockVLMClient(result: .success(response))
        let processor = AnalysisQueueProcessor(
            repository: context.repository,
            client: client,
            configuration: VLMConfiguration()
        )

        let processed = await processor.processNext()
        XCTAssertTrue(processed)
        let run = try XCTUnwrap(context.repository.analysisRuns(profileID: profile.id).first)
        XCTAssertEqual(run.requestTrace?.images.map(\.sourceImageID), ["image-1", "image-2"])
        XCTAssertEqual(run.requestTrace?.images.map(\.filePath), [first.path, second.path])
        XCTAssertEqual(run.lifestyleEvidence(sourceImageID: "image-1").first?.category, "travel")
        XCTAssertEqual(run.lifestyleEvidence(sourceImageID: "image-2").first?.category, "travel")
        let updated = try XCTUnwrap(context.repository.profile(id: profile.id))
        XCTAssertEqual(updated.analysisConfidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(updated.lifestyleScore), 73.65, accuracy: 0.001)
        let prompts = await client.prompts
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(prompts[0].contains("must be image-1"))
        XCTAssertTrue(prompts[1].contains("must be image-2"))
    }

    func testPreferredLocationNoMBTIReceivesDeratedOverallAfterAnalysis() async throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@tier2-no-mbti",
            age: 20,
            gender: .female,
            location: NormalizedLocation(
                rawText: "Beijing",
                city: "Beijing",
                province: nil,
                country: "China",
                tier: 2,
                score: 85,
                confidence: 0.95
            )
        ))
        try context.repository.updateScores(
            id: profile.id,
            face: 88,
            lifestyle: nil,
            overall: nil,
            confidence: 0.8
        )
        let image = context.root.appendingPathComponent("context.png")
        try Data("image".utf8).write(to: image)
        _ = try context.repository.enqueueAnalysis(
            profileID: profile.id,
            type: .lifestyle,
            modelName: "qwen3.5:9b",
            promptVersion: VLMPromptLibrary.lifestyleVersion,
            mediaPaths: [image.path]
        )
        let response = Data(#"{"lifestyle_affluence_signal":70,"confidence":80,"evidence":[],"actual_wealth":"unknown"}"#.utf8)
        let processor = AnalysisQueueProcessor(
            repository: context.repository,
            client: MockVLMClient(result: .success(response)),
            configuration: VLMConfiguration()
        )

        let processed = await processor.processNext()
        XCTAssertTrue(processed)
        let updated = try XCTUnwrap(context.repository.profile(id: profile.id))
        XCTAssertTrue(updated.isPreferredLocationNoMBTI)
        XCTAssertEqual(try XCTUnwrap(updated.lifestyleScore), 70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(updated.overallScore), 73.4, accuracy: 0.001)
    }

    func testUnknownLocationNoMBTIIsRetainedAndReceivesBothDeductions() async throws {
        let context = try temporaryRepository()
        let profile = try context.repository.upsert(ProfileDraft(
            usernameRaw: "@unknown-location-no-mbti",
            age: 20,
            gender: .female
        ))
        try context.repository.updateScores(
            id: profile.id,
            face: 88,
            lifestyle: nil,
            overall: nil,
            confidence: 0.8
        )
        let image = context.root.appendingPathComponent("unknown-location-context.png")
        try Data("image".utf8).write(to: image)
        _ = try context.repository.enqueueAnalysis(
            profileID: profile.id,
            type: .lifestyle,
            modelName: "qwen3.5:9b",
            promptVersion: VLMPromptLibrary.lifestyleVersion,
            mediaPaths: [image.path]
        )
        let response = Data(#"{"lifestyle_affluence_signal":70,"confidence":80,"evidence":[],"actual_wealth":"unknown"}"#.utf8)
        let processor = AnalysisQueueProcessor(
            repository: context.repository,
            client: MockVLMClient(result: .success(response)),
            configuration: VLMConfiguration()
        )

        let processed = await processor.processNext()
        XCTAssertTrue(processed)
        let updated = try XCTUnwrap(context.repository.profile(id: profile.id))
        XCTAssertTrue(updated.isUnknownLocationNoMBTI)
        XCTAssertEqual(try XCTUnwrap(updated.overallScore), 65, accuracy: 0.001)
    }

    private func temporaryRepository() throws -> (repository: ProfileRepository, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try ProfileRepository(databasePath: root.appendingPathComponent("test.sqlite").path), root)
    }

    private func mediaRecord(id: String, sequence: Int, ratio: Double, quality: Double) -> MediaRecord {
        MediaRecord(
            id: id,
            profileID: "profile",
            kind: MediaKind.moment.rawValue,
            filePath: "/tmp/\(id).png",
            perceptualHash: id,
            sourceSequence: sequence,
            faceCount: 1,
            largestFaceRatio: ratio,
            faceCaptureQuality: quality,
            usableFace: true,
            retained: true,
            createdAt: Date()
        )
    }
}

private actor MockVLMClient: VLMClientProtocol {
    let result: Result<Data, Error>
    private(set) var lastPrompt: String?
    private(set) var prompts: [String] = []
    init(result: Result<Data, Error>) { self.result = result }
    func health() async throws -> VLMHealth { VLMHealth(reachable: true, configuredModelAvailable: true, availableModels: []) }
    func generateJSON(prompt: String, images: [Data]) async throws -> Data {
        lastPrompt = prompt
        prompts.append(prompt)
        return try result.get()
    }
}
