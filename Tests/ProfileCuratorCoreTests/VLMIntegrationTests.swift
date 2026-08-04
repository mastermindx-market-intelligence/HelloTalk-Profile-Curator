import Foundation
import XCTest
@testable import ProfileCuratorCore

final class VLMIntegrationTests: XCTestCase {
    func testFreshConfigurationUsesCurrentVisionDefault() {
        XCTAssertEqual(VLMConfiguration().model, "qwen3.5:9b")
    }

    func testConfigurationRejectsUnsafeOrMalformedEndpoint() throws {
        XCTAssertThrowsError(try VLMConfiguration().validatedBaseURL())
        XCTAssertThrowsError(try VLMConfiguration(baseURL: URL(string: "file:///tmp/ollama")).validatedBaseURL())
        XCTAssertNoThrow(try VLMConfiguration(baseURL: URL(string: "http://qwen-box:11434")).validatedBaseURL())
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
        let profile = try context.repository.upsert(ProfileDraft(usernameRaw: "@evidence", age: 19, gender: .female, mbti: .infj))
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
        XCTAssertEqual(run.lifestyleEvidence(sourceImageID: "image-2").first?.category, "travel")
        XCTAssertEqual(try XCTUnwrap(context.repository.profile(id: profile.id)).analysisConfidence, 0.8, accuracy: 0.001)
        let prompt = await client.lastPrompt
        XCTAssertTrue(prompt?.contains("image-1, image-2") == true)
    }

    private func temporaryRepository() throws -> (repository: ProfileRepository, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try ProfileRepository(databasePath: root.appendingPathComponent("test.sqlite").path), root)
    }
}

private actor MockVLMClient: VLMClientProtocol {
    let result: Result<Data, Error>
    private(set) var lastPrompt: String?
    init(result: Result<Data, Error>) { self.result = result }
    func health() async throws -> VLMHealth { VLMHealth(reachable: true, configuredModelAvailable: true, availableModels: []) }
    func generateJSON(prompt: String, images: [Data]) async throws -> Data {
        lastPrompt = prompt
        return try result.get()
    }
}
