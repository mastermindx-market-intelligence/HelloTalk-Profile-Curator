import XCTest
@testable import ProfileCuratorCore

final class CollectionPolicyTests: XCTestCase {
    func testOpenedProfileMustVerifyUsernameFemaleAdultAgeAndTargetMBTI() {
        let policy = ProfileEligibilityPolicy()
        XCTAssertEqual(
            policy.evaluate(OpenedProfileEvidence(
                username: "@a", age: 19, gender: .female, mbti: .infj, locationScore: 100
            )),
            .collectPrimary
        )
        XCTAssertEqual(
            policy.evaluate(OpenedProfileEvidence(
                username: "@b", age: 21, gender: .female, mbti: .entp, locationScore: 70
            )),
            .collectSecondary
        )
        XCTAssertFalse(policy.evaluate(
            OpenedProfileEvidence(username: "@c", age: 22, gender: .female, mbti: .infj)
        ).isCollectible)
        XCTAssertFalse(policy.evaluate(
            OpenedProfileEvidence(username: "@d", age: 19, gender: .unknown, mbti: .infj)
        ).isCollectible)
    }

    func testAgesTwentyThreeAndTwentyFourRequirePrimaryMBTI() {
        let policy = ProfileEligibilityPolicy()

        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@infj-23", age: 23, gender: .female, mbti: .infj, locationScore: 30
        )), .collectPrimary)
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@intj-24", age: 24, gender: .female, mbti: .intj, locationScore: 85
        )), .collectPrimary)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@entp-23", age: 23, gender: .female, mbti: .entp, locationScore: 100
        )).isCollectible)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@missing-24", age: 24, gender: .female, mbti: nil, locationScore: 100
        )).isCollectible)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@infj-22", age: 22, gender: .female, mbti: .infj, locationScore: 100
        )).isCollectible)
    }

    func testTierOneAndTwoAllowMissingMBTIWhileTierThreeRequiresTargetMBTI() {
        let policy = ProfileEligibilityPolicy()

        XCTAssertEqual(
            policy.evaluate(OpenedProfileEvidence(
                username: "@tier1",
                age: 20,
                gender: .female,
                mbti: nil,
                locationScore: 100
            )),
            .collectPreferredLocationNoMBTI
        )
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@tier2",
            age: 20,
            gender: .female,
            mbti: nil,
            locationScore: 85
        )), .collectPreferredLocationNoMBTI)
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@tier3-target",
            age: 20,
            gender: .female,
            mbti: .infj,
            locationScore: 70
        )), .collectPrimary)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@tier3-no-mbti",
            age: 20,
            gender: .female,
            mbti: nil,
            locationScore: 70
        )).isCollectible)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@tier4-secondary",
            age: 20,
            gender: .female,
            mbti: .entp,
            locationScore: 55
        )).isCollectible)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@non-target",
            age: 20,
            gender: .female,
            mbti: .isfj,
            locationScore: 100
        )).isCollectible)
    }

    func testMissingLocationIsCollectibleAndPrimaryOverridesKnownLowTierLocation() {
        let policy = ProfileEligibilityPolicy()

        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@primary-hidden",
            age: 20,
            gender: .female,
            mbti: .intj,
            locationScore: nil
        )), .collectPrimary)
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@secondary-hidden",
            age: 20,
            gender: .female,
            mbti: .entp,
            locationScore: 10
        )), .collectSecondary)
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@all-hidden",
            age: 20,
            gender: .female,
            mbti: nil,
            locationScore: nil
        )), .collectUnknownLocationNoMBTI)
        XCTAssertEqual(policy.evaluate(OpenedProfileEvidence(
            username: "@primary-known-low-tier",
            age: 20,
            gender: .female,
            mbti: .intj,
            locationScore: 30
        )), .collectPrimary)
        XCTAssertFalse(policy.evaluate(OpenedProfileEvidence(
            username: "@secondary-known-low-tier",
            age: 20,
            gender: .female,
            mbti: .entp,
            locationScore: 30
        )).isCollectible)
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

        let locationOnly = ScoringEngine().score(
            group: .secondary,
            components: ScoreComponents(face: 10, lifestyle: 10, location: 100, completeness: 0, confidence: 0.5)
        )
        XCTAssertTrue(locationOnly.secondaryHighPriority)
    }

    func testNoMBTIExceptionRemainsFaceAndLifestyleLedWithExplicitPenalty() {
        let scorer = ScoringEngine()
        let strong = scorer.scorePreferredLocationNoMBTI(
            components: ScoreComponents(face: 90, lifestyle: 90, location: 100, completeness: 75, confidence: 0.8)
        )
        let weak = scorer.scorePreferredLocationNoMBTI(
            components: ScoreComponents(face: 40, lifestyle: 35, location: 100, completeness: 75, confidence: 0.8)
        )

        XCTAssertEqual(strong.overall, 83, accuracy: 0.001)
        XCTAssertEqual(weak.overall, 36.25, accuracy: 0.001)
        XCTAssertGreaterThan(strong.overall, weak.overall + 40)
    }

    func testMissingLocationPenaltyIsWaivedForPrimaryOrVeryHighFace() {
        let scorer = ScoringEngine()
        let ordinary = ScoreComponents(
            face: 80, lifestyle: 60, location: 10, completeness: 50, confidence: 0.8
        )
        let veryHighFace = ScoreComponents(
            face: 90, lifestyle: 60, location: 10, completeness: 50, confidence: 0.8
        )

        let primary = scorer.score(group: .primary, components: ordinary, locationMissing: true)
        let secondary = scorer.score(group: .secondary, components: ordinary, locationMissing: true)
        let rescuedSecondary = scorer.score(group: .secondary, components: veryHighFace, locationMissing: true)
        let missingMBTI = scorer.scorePreferredLocationNoMBTI(
            components: ordinary,
            locationMissing: true
        )

        XCTAssertEqual(primary.overall, 70, accuracy: 0.001)
        XCTAssertEqual(secondary.overall, 64.5, accuracy: 0.001)
        XCTAssertEqual(rescuedSecondary.overall, 78.75, accuracy: 0.001)
        XCTAssertEqual(missingMBTI.overall, 56.222, accuracy: 0.001)
    }
}
