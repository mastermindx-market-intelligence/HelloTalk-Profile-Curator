import XCTest
@testable import ProfileCuratorCore

final class CollectionPolicyTests: XCTestCase {
    func testOpenedProfileMustVerifyUsernameFemaleAdultAgeAndTargetMBTI() {
        let policy = ProfileEligibilityPolicy()
        XCTAssertEqual(
            policy.evaluate(OpenedProfileEvidence(username: "@a", age: 19, gender: .female, mbti: .infj)),
            .collectPrimary
        )
        XCTAssertEqual(
            policy.evaluate(OpenedProfileEvidence(username: "@b", age: 21, gender: .female, mbti: .entp)),
            .collectSecondary
        )
        XCTAssertFalse(policy.evaluate(
            OpenedProfileEvidence(username: "@c", age: 22, gender: .female, mbti: .infj)
        ).isCollectible)
        XCTAssertFalse(policy.evaluate(
            OpenedProfileEvidence(username: "@d", age: 19, gender: .unknown, mbti: .infj)
        ).isCollectible)
    }

    func testRetentionCapsAndDeduplicatesBeforeCountingRetained() {
        let duplicate = MediaCandidate(perceptualHash: "same", faceCount: 1, largestFaceRatio: 0.2, captureQuality: 0.8)
        var candidates = [duplicate, duplicate]
        for index in 0..<30 {
            let hasFace = index < 8
            candidates.append(MediaCandidate(
                perceptualHash: "hash\(index)",
                faceCount: hasFace ? 1 : 0,
                largestFaceRatio: hasFace ? 0.2 : 0,
                captureQuality: hasFace ? 0.7 : nil,
                contextStrength: Double(index) / 30
            ))
        }
        let plan = MediaRetentionPlanner().plan(candidates: candidates)
        XCTAssertEqual(plan.scannedCount, 20)
        XCTAssertLessThanOrEqual(plan.retainedIDs.count, 10)
        XCTAssertTrue(plan.reachedScanLimit)
        XCTAssertEqual(plan.duplicateCount, 1)
    }

    func testSecondaryNoFaceRuleCannotBeDisabled() {
        let noFaces = (0..<20).map {
            MediaCandidate(perceptualHash: "\($0)", faceCount: 0, largestFaceRatio: 0, captureQuality: nil)
        }
        let policy = NoFacePolicy(enabledForPrimary: false)
        XCTAssertEqual(policy.decision(group: .secondary, candidates: noFaces, feedExhausted: false), .rejectAndPurge)
        XCTAssertEqual(policy.decision(group: .primary, candidates: noFaces, feedExhausted: false), .retainForReview)
    }

    func testScoringUsesSeparateWeightsAndExplicitConfidenceAdjustment() {
        let components = ScoreComponents(face: 80, lifestyle: 60, location: 100, completeness: 50, confidence: 0.5)
        let primary = ScoringEngine().score(group: .primary, components: components)
        XCTAssertEqual(primary.overall, 76, accuracy: 0.001)
        XCTAssertEqual(primary.confidenceAdjusted, 66.5, accuracy: 0.001)
        XCTAssertFalse(primary.secondaryHighPriority)

        let secondary = ScoringEngine().score(group: .secondary, components: components)
        XCTAssertTrue(secondary.secondaryHighPriority)
    }
}
