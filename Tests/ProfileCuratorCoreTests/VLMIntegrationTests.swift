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

    private func temporaryRepository() throws -> (repository: ProfileRepository, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try ProfileRepository(databasePath: root.appendingPathComponent("test.sqlite").path), root)
    }
}

private actor MockVLMClient: VLMClientProtocol {
    let result: Result<Data, Error>
    init(result: Result<Data, Error>) { self.result = result }
    func health() async throws -> VLMHealth { VLMHealth(reachable: true, configuredModelAvailable: true, availableModels: []) }
    func generateJSON(prompt: String, images: [Data]) async throws -> Data { try result.get() }
}
