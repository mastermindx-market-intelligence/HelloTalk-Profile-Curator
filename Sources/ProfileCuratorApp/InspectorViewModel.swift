import AppKit
import Foundation
import ProfileCuratorCore

private enum AutomationPhase: String {
    case acquireSeed = "Finding a profile"
    case scanProfile = "Reading profile"
    case returnToTop = "Returning to profile header"
    case openPFP = "Capturing profile photo"
    case openMoments = "Opening Moments"
    case scanMoments = "Scanning Moments"
    case exitMoments = "Finishing media collection"
    case seekSuggestions = "Finding similar profiles"
    case openRecommendation = "Opening next similar profile"
}

private enum AutomationRuntimeError: LocalizedError {
    case permissionsMissing
    case mirroringWindowMissing
    case calibrationMissing(String)
    case actionBlocked(String)
    case postconditionFailed(String)
    case unknownState(String)

    var errorDescription: String? {
        switch self {
        case .permissionsMissing:
            "Screen Recording and Accessibility must both be enabled."
        case .mirroringWindowMissing:
            "No visible iPhone Mirroring window was found."
        case .calibrationMissing(let label):
            "Required safe calibration is missing: \(label)."
        case .actionBlocked(let reason):
            "Safety gate blocked the action: \(reason)."
        case .postconditionFailed(let reason):
            "The app could not verify the last navigation action: \(reason)."
        case .unknownState(let reason):
            "Collection paused on an unrecognized screen: \(reason)."
        }
    }
}

@MainActor
final class InspectorViewModel: ObservableObject {
    enum AutomationRunState: String {
        case idle = "Ready"
        case running = "Running"
        case paused = "Paused"
        case stopped = "Stopped"
        case completed = "Completed"
    }

    @Published var fixtureImage: NSImage?
    @Published var fixtureURL: URL?
    @Published var analysis: FixtureAnalysis?
    @Published var errorMessage: String?
    @Published var permissionStatus = PermissionInspector.currentStatus()
    @Published var mirroringWindows: [MirroringWindowDescriptor] = []
    @Published var selectedWindowID: CGWindowID?
    @Published var windowSearchStatus = "Not searched"
    @Published var navigationState: NavigationState = .acquireMirroringWindow
    @Published var showOCRBoxes = true
    @Published var showFaceBoxes = true
    @Published var showSafetyPreview = true
    @Published var calibrationMode = false
    @Published var selectedCalibrationContext: CalibrationContext = .profile
    @Published var selectedCalibrationKind: CalibrationMarkKind = .safeAvatar
    @Published var calibrationMarks: [CalibrationMark] = []
    @Published var calibrationStatus = "Not saved"
    @Published var temporalLocation: TemporalLocationResolution?
    @Published var screenClassification: ScreenClassification?
    @Published var observationSnapshot: ObservationSnapshot?
    @Published var pendingPostcondition: VisiblePostcondition?
    @Published var lastPostconditionResult: PostconditionResult?
    @Published var navigationEvents: [NavigationEvent] = []
    @Published var sessionState = NavigationSessionState()
    @Published var galleryGesture: PlannedGesture?
    @Published var galleryGestureStatus = "Visible-card profile hopping is active"
    @Published var proposedVisibleCardTarget: VisibleRecommendationTarget?
    @Published var visibleCardProposalStatus = "No visible-card proposal"
    @Published var proposedMomentThumbnailTarget: MomentThumbnailTarget?
    @Published var momentThumbnailProposalStatus = "No Moment thumbnail proposal"
    @Published var recommendationLedger = RecommendationTraversalLedger()
    @Published var pendingGraphDecision: RecommendationTraversalDecision?
    @Published var collectionStatus = "No verified profile checkpoint"
    @Published var automationRunState: AutomationRunState = .idle
    @Published var automationStatus = "Ready to collect automatically"
    @Published var automationActionCount = 0
    @Published var automationProfileCount = 0

    let previewExclusions = DefaultInspectorCalibration.previewExclusions

    private let analyzer = VisionFixtureAnalyzer()
    private let mbtiParser = MBTIParser()
    private let locationNormalizer = LocationNormalizer()
    private let profileHeaderParser = ProfileHeaderParser()
    private let profileMetadataParser = ProfileMetadataParser()
    private let recommendationAgeParser = RecommendationAgeParser()
    private let genderBadgeClassifier = GenderBadgeClassifier()
    private let rotatingLocationBadgeParser = RotatingLocationBadgeParser()
    private let snapshotBuilder = ObservationSnapshotBuilder()
    private let postconditionEvaluator = NavigationPostconditionEvaluator()
    private let galleryGesturePlanner = GalleryGesturePlanner()
    private let sessionPolicy = NavigationSessionPolicy.conservativeDefault
    private let discoveryPolicy = DiscoveryPolicy.observedDefault
    private let visibleTargetDetector = VisibleRecommendationTargetDetector()
    private let momentThumbnailDetector = MomentThumbnailTargetDetector()
    private let momentDismissPlanner = MomentViewerDismissPlanner()
    private let socialControlDetector = SocialControlExclusionDetector()
    private let profileInteractionSafety = ProfileInteractionSafety()
    private let recommendationTargetRanker = VisibleRecommendationTargetRanker()
    private let liveInputExecutor = SafeInputExecutor(driver: CGEventInputDriver())
    private let eventStore: NavigationEventLogStore?
    private var currentCGImage: CGImage?
    private var lastProfileUsername: String?
    private var pendingGraphCandidate: VisibleRecommendationCandidate?
    private var windowGeometryGuard: WindowGeometryGuard?
    private let profileRepository: ProfileRepository?
    private let mediaStore: MediaStore?
    private var collectedProfileID: String?
    private var profileAccumulator = ProfileObservationAccumulator()
    private var automationTask: Task<Void, Never>?
    private var qwenWorkerTask: Task<Void, Never>?
    private var automationPhase: AutomationPhase = .acquireSeed
    private var automationAboutMeSelected = false
    private var automationScrollAttempts = 0
    private var automationNoProgressCount = 0
    private var automationUnknownCount = 0
    private var automationMomentKeys: Set<String> = []
    private var automationPendingMomentKey: String?
    private var automationCollectedUsername: String?
    private var automationLastFingerprint: String?
    private var automationWindowFrame: CGRect?

    init() {
        eventStore = try? NavigationEventLogStore.defaultStore()
        profileRepository = try? ProfileRepository.defaultRepository()
        if let profileRepository,
           let root = try? ProfileRepository.defaultDataDirectory() {
            mediaStore = try? MediaStore(
                rootURL: root.appendingPathComponent("media", isDirectory: true),
                repository: profileRepository
            )
        } else {
            mediaStore = nil
        }
    }

    var mbtiMatches: [MBTIMatch] {
        guard let analysis else { return [] }
        return mbtiParser.matches(in: analysis.text)
    }

    var targetMBTI: MBTIMatch? {
        guard let analysis else { return nil }
        return mbtiParser.firstTarget(in: analysis.text)
    }

    var detectedLocation: NormalizedLocation? {
        guard let analysis else { return nil }
        return locationNormalizer.normalize(analysis.text.map(\.text).joined(separator: " · "))
    }

    var detectedProfileAge: ProfileAgeMatch? {
        guard let analysis else { return nil }
        return profileHeaderParser.bestAge(in: analysis.text)
    }

    var detectedGenderBadge: GenderBadgeEvidence? {
        guard let currentCGImage, let detectedProfileAge else { return nil }
        return genderBadgeClassifier.classify(image: currentCGImage, ageMatch: detectedProfileAge)
    }

    var visibleRecommendationAges: [RecommendationAgeCandidate] {
        guard let analysis else { return [] }
        return recommendationAgeParser.allAges(in: analysis.text)
    }

    var visibleRecommendationTargets: [VisibleRecommendationTarget] {
        guard let analysis else { return [] }
        return visibleTargetDetector.targets(in: analysis.text)
    }

    var dynamicSocialExclusions: [ExclusionZone] {
        guard let analysis else { return [] }
        return socialControlDetector.exclusions(in: analysis.text)
            + profileInteractionSafety.learningStatsExclusions(in: analysis.text)
    }

    var momentThumbnailTargets: [MomentThumbnailTarget] {
        guard screenClassification?.kind == .momentsFeed,
              let currentCGImage,
              let analysis else { return [] }
        return momentThumbnailDetector.targets(
            in: currentCGImage,
            from: calibrationMarks,
            observations: analysis.text,
            faces: analysis.faces
        )
    }

    var activePreviewExclusions: [ExclusionZone] {
        previewExclusions + dynamicSocialExclusions + exclusionZones(for: activeCalibrationContext)
    }

    var previewAction: PlannedAction {
        proposedMomentThumbnailTarget?.plannedAction
            ?? proposedVisibleCardTarget?.plannedAction
            ?? DefaultInspectorCalibration.previewAction
    }

    var previewDecision: ActionSafetyDecision {
        ActionSafetyValidator().validate(
            previewAction,
            exclusionZones: activePreviewExclusions,
            emergencyStopActive: sessionState.pauseReason == .emergencyStop,
            sessionPauseReason: sessionState.pauseReason?.summary,
            liveInputEnabled: false
        )
    }

    var galleryGestureDecision: GestureSafetyDecision? {
        guard let galleryGesture else { return nil }
        let context: CalibrationContext = galleryGesture.kind == .closeViewer ? .momentViewer : .profile
        let markKind: CalibrationMarkKind = galleryGesture.kind == .closeViewer
            ? .safeMomentDismissGesture
            : .safeCarouselGesture
        let mark = calibrationMarks.last { $0.context == context && $0.kind == markKind }
        let requiredExclusions: Set<CalibrationMarkKind> = galleryGesture.kind == .closeViewer
            ? [.excludeLike]
            : [.excludeFollow, .excludeSayHi, .excludeGift]
        let confirmedExclusions = Set(calibrationMarks.filter {
            $0.context == context && $0.confirmed && $0.kind.isExclusion
        }.map(\.kind))
        let calibrationReady = mark?.confirmed == true && requiredExclusions.isSubset(of: confirmedExclusions)
        return GestureSafetyValidator().validate(
            galleryGesture,
            exclusionZones: exclusionZones(for: .profile),
            calibrationConfirmed: calibrationReady,
            emergencyStopActive: sessionState.pauseReason == .emergencyStop,
            sessionPauseReason: sessionState.pauseReason?.summary,
            liveInputEnabled: false
        )
    }

    var sessionStatus: String {
        if let reason = sessionState.pauseReason { return "Paused · \(reason.summary)" }
        if automationRunState == .running {
            return "Live automatic · \(sessionState.proposalCount)/\(sessionPolicy.maximumProposals) actions"
        }
        return "Ready · \(sessionState.proposalCount)/\(sessionPolicy.maximumProposals) actions"
    }

    private var activeCalibrationContext: CalibrationContext {
        switch screenClassification?.kind {
        case .connectFeed, .customSearch: .connectFeed
        case .pfpViewer: .pfpViewer
        case .momentsFeed, .momentDetails: .momentsFeed
        case .momentViewer: .momentViewer
        default: .profile
        }
    }

    var discoveryTraversalStatus: String {
        "Visible-card graph · \(recommendationLedger.visitedProfileKeys.count) visited · depth \(recommendationLedger.routingDepth)/\(discoveryPolicy.maximumRoutingDepth)"
    }

    var profileEligibilityDecision: ProfileEligibilityDecision {
        ProfileEligibilityPolicy().evaluate(profileAccumulator.evidence)
    }

    var canCheckpointProfile: Bool {
        profileEligibilityDecision.isCollectible && currentCGImage != nil && profileRepository != nil
    }

    func startAutonomousCollection() {
        guard automationTask == nil else { return }
        refreshPermissions()
        guard permissionStatus.screenRecordingGranted, permissionStatus.accessibilityGranted else {
            automationRunState = .paused
            automationStatus = AutomationRuntimeError.permissionsMissing.localizedDescription
            errorMessage = automationStatus
            return
        }

        if calibrationMarks.isEmpty {
            if let saved = try? CalibrationStore.defaultStore().load() {
                calibrationMarks = saved.marks
                calibrationStatus = "Loaded saved calibration for automatic collection"
            } else {
                calibrationMarks = ObservedHelloTalkCalibration.marks
                calibrationStatus = "Loaded supervised 2026-08-03 baseline"
            }
        }

        sessionState = NavigationSessionState()
        automationPhase = .acquireSeed
        automationAboutMeSelected = false
        automationScrollAttempts = 0
        automationNoProgressCount = 0
        automationUnknownCount = 0
        automationMomentKeys = []
        automationPendingMomentKey = nil
        let checkpoint = try? CollectionCheckpointStore.defaultStore().load()
        automationCollectedUsername = checkpoint?.currentUsername
        automationLastFingerprint = nil
        automationWindowFrame = nil
        collectedProfileID = checkpoint?.currentProfileID
        windowGeometryGuard = nil
        errorMessage = nil
        automationRunState = .running
        automationStatus = "Starting automatic collection…"
        recordEvent(.sessionReset, summary: "Automatic collection started")

        automationTask = Task { [weak self] in
            await self?.runAutonomousCollection()
        }
        startQwenWorkerIfNeeded()
    }

    func pauseAutonomousCollection() {
        guard automationRunState == .running else { return }
        automationTask?.cancel()
        automationTask = nil
        automationRunState = .paused
        automationStatus = "Paused by user · tap Resume to continue"
        recordEvent(.sessionPaused, summary: automationStatus)
    }

    func resumeAutonomousCollection() {
        guard automationRunState == .paused,
              sessionState.pauseReason != .emergencyStop else { return }
        errorMessage = nil
        automationRunState = .running
        automationStatus = "Resuming · \(automationPhase.rawValue)"
        automationTask = Task { [weak self] in
            await self?.runAutonomousCollection()
        }
    }

    func stopAutonomousCollection() {
        engageEmergencyStop()
    }

    private func runAutonomousCollection() async {
        do {
            try await prepareAutomationWindow()
            while !Task.isCancelled && automationRunState == .running {
                let snapshot = try await captureAutomationFrame()
                try Task.checkCancellation()
                try await handleAutomationSnapshot(snapshot)
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch is CancellationError {
            // Pause and Stop deliberately cancel the task. Their button handlers own status text.
        } catch {
            guard automationRunState == .running else {
                automationTask = nil
                return
            }
            automationRunState = .paused
            automationStatus = "Paused safely · \(error.localizedDescription)"
            errorMessage = error.localizedDescription
            recordEvent(.sessionPaused, summary: automationStatus)
        }
        automationTask = nil
    }

    private func prepareAutomationWindow() async throws {
        if selectedWindowID == nil {
            windowSearchStatus = "Locating iPhone Mirroring automatically…"
            let candidates = try await MirroringWindowLocator().locateCandidates()
            mirroringWindows = candidates
            selectedWindowID = candidates.first?.id
        }
        guard selectedWindowID != nil else { throw AutomationRuntimeError.mirroringWindowMissing }
        try await focusMirroringApp()
        windowSearchStatus = "Automatic collector attached to iPhone Mirroring"
    }

    private func focusMirroringApp() async throws {
        guard let mirroringApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.ScreenContinuity"
        ).first else {
            throw AutomationRuntimeError.mirroringWindowMissing
        }
        mirroringApp.activate()
        try await Task.sleep(for: .milliseconds(300))
    }

    @discardableResult
    private func captureAutomationFrame() async throws -> ObservationSnapshot {
        guard let selectedWindowID else { throw AutomationRuntimeError.mirroringWindowMissing }
        let frame = try await WindowCaptureService().capture(windowID: selectedWindowID)
        try validateWindowGeometry(frame)
        automationWindowFrame = frame.windowFrame
        let result = try analyzer.analyze(frame.image)
        let image = NSImage(
            cgImage: frame.image,
            size: NSSize(width: frame.image.width, height: frame.image.height)
        )
        acceptAnalysis(
            result,
            image: image,
            cgImage: frame.image,
            fixtureURL: nil,
            capturedAt: frame.capturedAt
        )
        guard let observationSnapshot else {
            throw AutomationRuntimeError.unknownState("No analyzable window snapshot")
        }
        windowSearchStatus = "Live · captured \(observationSnapshot.screen.kind.rawValue)"
        return observationSnapshot
    }

    private func handleAutomationSnapshot(_ snapshot: ObservationSnapshot) async throws {
        if sessionState.isPaused {
            throw AutomationRuntimeError.actionBlocked(sessionState.pauseReason?.summary ?? "session guard")
        }

        automationStatus = "\(automationPhase.rawValue) · \(snapshot.screen.kind.rawValue) · \(automationProfileCount) saved"
        if let observations = analysis?.text,
           profileInteractionSafety.isLearningStatsPopup(observations) {
            automationStatus = "Recovering · dismissing accidental learning-statistics popup"
            _ = try await performClick(
                profileInteractionSafety.dismissLearningStatsPopupAction(),
                context: .profile,
                expecting: .ocrAnchorAbsent("Total learning points")
            )
            return
        }
        if snapshot.screen.kind == .unknown {
            try await recoverFromUnknownScreen(snapshot)
            return
        }
        automationUnknownCount = 0

        switch snapshot.screen.kind {
        case .connectFeed:
            automationPhase = .acquireSeed
            let action = try calibratedAction(
                context: .connectFeed,
                kind: .safeRecommendationCard,
                actionKind: .openRecommendationCard,
                rationale: "Open the visible seed profile photo"
            )
            _ = try await performClick(action, context: .connectFeed, expecting: .profilePageDetected)
            prepareForNewProfile()
            automationPhase = .scanProfile

        case .customSearch:
            throw AutomationRuntimeError.unknownState("Custom Search is a seed fallback; open one result or return to Connect")

        case .profileTop:
            try await handleProfileTop(snapshot)

        case .profilePersonalInfo:
            try await handlePersonalInfo()

        case .suggestedProfilesGallery:
            if automationPhase != .openRecommendation {
                automationScrollAttempts = 0
                automationNoProgressCount = 0
            }
            automationPhase = .openRecommendation
            try await openNextRecommendation(snapshot)

        case .pfpViewer:
            guard automationPhase == .openPFP else {
                throw AutomationRuntimeError.unknownState("Unexpected profile-photo viewer")
            }
            checkpointViewerPhoto()
            let close = try calibratedAction(
                context: .pfpViewer,
                kind: .safeBackClose,
                actionKind: .closeViewer,
                rationale: "Close the profile-photo viewer"
            )
            _ = try await performClick(close, context: .pfpViewer, expecting: .profilePageDetected)
            automationPhase = .openMoments

        case .momentsFeed:
            if automationPhase == .openMoments { automationPhase = .scanMoments }
            try await scanVisibleMoments(snapshot)

        case .momentViewer:
            if automationPhase == .acquireSeed, currentCollectedProfile() != nil {
                automationPhase = .scanMoments
            }
            guard automationPhase == .scanMoments else {
                throw AutomationRuntimeError.unknownState("Unexpected Moment viewer")
            }
            checkpointViewerPhoto()
            if let key = automationPendingMomentKey { automationMomentKeys.insert(key) }
            automationPendingMomentKey = nil
            try await dismissMomentViewer(snapshot)

        case .momentDetails:
            let back = fallbackBackAction(rationale: "Return from Moment details to the Moments feed")
            _ = try await performClick(back, context: .momentsFeed, expecting: .contentHashChanged(previous: snapshot.fingerprint))
            automationPhase = .scanMoments

        case .unknown:
            break
        }
    }

    private func handleProfileTop(_ snapshot: ObservationSnapshot) async throws {
        switch automationPhase {
        case .returnToTop:
            automationPhase = .openPFP
            fallthrough
        case .openPFP:
            let avatar = try calibratedAction(
                context: .profile,
                kind: .safeAvatar,
                actionKind: .openAvatar,
                rationale: "Open the verified profile photo"
            )
            _ = try await performClick(avatar, context: .profile, expecting: .viewerDetected)

        case .openMoments:
            guard let observations = analysis?.text,
                  let moments = profileInteractionSafety.tabAction(named: "Moments", in: observations) else {
                throw AutomationRuntimeError.unknownState("The live Moments tab OCR anchor is unavailable; refusing a blind calibrated click")
            }
            _ = try await performClick(moments, context: .profile, expecting: .contentHashChanged(previous: snapshot.fingerprint))
            automationPhase = .scanMoments

        case .exitMoments, .seekSuggestions, .openRecommendation:
            automationPhase = .seekSuggestions
            automationScrollAttempts = 0
            _ = try await performVerticalScroll(lines: -7, context: .profile, previousFingerprint: snapshot.fingerprint)

        default:
            automationPhase = .scanProfile
            if !automationAboutMeSelected {
                guard let observations = analysis?.text,
                      profileInteractionSafety.tabAction(named: "About Me", in: observations) != nil else {
                    throw AutomationRuntimeError.unknownState("The live About Me tab OCR anchor is unavailable; refusing to scan an unverified tab")
                }
                // A newly opened profile already lands on About Me. Verify the live
                // OCR anchor and scroll; do not tap the tab or any nearby stats card.
                automationAboutMeSelected = true
            }
            automationScrollAttempts += 1
            guard automationScrollAttempts <= 10 else {
                throw AutomationRuntimeError.unknownState("Personal Info was not found after 10 bounded scrolls")
            }
            _ = try await performVerticalScroll(lines: -7, context: .profile, previousFingerprint: snapshot.fingerprint)
        }
    }

    private func handlePersonalInfo() async throws {
        switch automationPhase {
        case .returnToTop, .openPFP:
            automationPhase = .returnToTop
            _ = try await performVerticalScroll(lines: 10, context: .profile, previousFingerprint: observationSnapshot?.fingerprint)

        case .seekSuggestions, .exitMoments, .openRecommendation:
            automationPhase = .seekSuggestions
            automationScrollAttempts += 1
            guard automationScrollAttempts <= 14 else {
                throw AutomationRuntimeError.unknownState("Suggested for You was not found after 14 bounded scrolls")
            }
            _ = try await performVerticalScroll(lines: -7, context: .profile, previousFingerprint: observationSnapshot?.fingerprint)

        default:
            switch profileEligibilityDecision {
            case .collectPrimary, .collectSecondary, .collectPreferredLocationNoMBTI:
                checkpointVerifiedProfile()
                guard collectedProfileID != nil, let username = profileAccumulator.username else {
                    throw AutomationRuntimeError.unknownState(collectionStatus)
                }
                automationCollectedUsername = username
                automationPhase = .returnToTop
                automationScrollAttempts = 0
                _ = try await performVerticalScroll(lines: 12, context: .profile, previousFingerprint: observationSnapshot?.fingerprint)
            case .routingOnly(let reason):
                automationStatus = "Routing past ineligible profile · \(reason)"
                automationPhase = .seekSuggestions
                automationScrollAttempts = 0
                _ = try await performVerticalScroll(lines: -7, context: .profile, previousFingerprint: observationSnapshot?.fingerprint)
            }
        }
    }

    private func scanVisibleMoments(_ snapshot: ObservationSnapshot) async throws {
        if scannedMomentCount() >= CollectionLimits.hardenedDefault.maximumScannedPhotos {
            try await finishMediaCollection(snapshot)
            return
        }

        let available = momentThumbnailTargets.first { target in
            !automationMomentKeys.contains(momentKey(target, fingerprint: snapshot.fingerprint))
        }
        if let target = available {
            let key = momentKey(target, fingerprint: snapshot.fingerprint)
            automationPendingMomentKey = key
            proposedMomentThumbnailTarget = target
            _ = try await performClick(target.plannedAction, context: .momentsFeed, expecting: .viewerDetected)
            automationNoProgressCount = 0
            return
        }

        _ = try await performVerticalScroll(
            lines: -6,
            context: .momentsFeed,
            previousFingerprint: snapshot.fingerprint,
            unchangedIsAllowed: true
        )
        automationNoProgressCount += 1
        if automationNoProgressCount >= 5 {
            try await finishMediaCollection(snapshot)
        }
    }

    private func finishMediaCollection(_ snapshot: ObservationSnapshot) async throws {
        finalizeCurrentProfileMedia()
        recordEvent(.transition, summary: collectionStatus)
        queueCurrentProfileAnalysis()
        recordEvent(.transition, summary: collectionStatus)
        startQwenWorkerIfNeeded()
        automationProfileCount += 1
        automationPhase = .exitMoments
        automationNoProgressCount = 0
        let back = fallbackBackAction(rationale: "Return to the profile after finishing Moments")
        _ = try await performClick(back, context: .momentsFeed, expecting: .contentHashChanged(previous: snapshot.fingerprint))
        automationPhase = .seekSuggestions
        automationScrollAttempts = 0
    }

    private func openNextRecommendation(_ snapshot: ObservationSnapshot) async throws {
        guard let previousUsername = profileAccumulator.username
                ?? observationSnapshot?.username
                ?? automationCollectedUsername
                ?? currentCollectedProfile()?.usernameNormalized else {
            throw AutomationRuntimeError.unknownState("The current username is unavailable for identity verification")
        }
        let proposals = recommendationTargetRanker.ranked(visibleRecommendationTargets).compactMap { target -> (VisibleRecommendationTarget, VisibleRecommendationCandidate, RecommendationTraversalDecision)? in
            let candidate = VisibleRecommendationCandidate(
                profileKey: target.profileKey,
                displayedAge: target.displayedAge,
                genderHint: .unknown
            )
            let decision = recommendationLedger.decision(for: candidate)
            return decision.isOpenProposal ? (target, candidate, decision) : nil
        }
        guard let proposal = proposals.first else {
            if automationScrollAttempts < 3 {
                automationScrollAttempts += 1
                _ = try await performVerticalScroll(
                    lines: -4,
                    context: .profile,
                    previousFingerprint: snapshot.fingerprint,
                    unchangedIsAllowed: true
                )
                return
            }
            automationRunState = .completed
            automationStatus = "Automatic session complete · visible similar-profile graph exhausted"
            recordEvent(.transition, summary: automationStatus)
            automationTask?.cancel()
            return
        }

        let (target, candidate, decision) = proposal
        proposedVisibleCardTarget = target
        let next = try await performClick(
            target.plannedAction,
            context: .profile,
            expecting: .profileIdentityChanged(previousUsername: previousUsername)
        )
        recommendationLedger.recordOpened(candidate, decision: decision)
        if let username = next.username { recommendationLedger.recordVerifiedProfileKey(username) }
        prepareForNewProfile()
        automationPhase = .scanProfile
        automationScrollAttempts = 0
    }

    private func recoverFromUnknownScreen(_ snapshot: ObservationSnapshot) async throws {
        automationUnknownCount += 1
        guard automationUnknownCount <= 4 else {
            throw AutomationRuntimeError.unknownState("Four consecutive captures could not be classified")
        }

        switch automationPhase {
        case .scanProfile, .seekSuggestions, .exitMoments, .openRecommendation:
            automationScrollAttempts += 1
            guard automationScrollAttempts <= 14 else {
                throw AutomationRuntimeError.unknownState("Bounded profile scan exhausted")
            }
            _ = try await performVerticalScroll(
                lines: -7,
                context: .profile,
                previousFingerprint: snapshot.fingerprint,
                unchangedIsAllowed: true
            )
        case .returnToTop, .openPFP:
            _ = try await performVerticalScroll(
                lines: 10,
                context: .profile,
                previousFingerprint: snapshot.fingerprint,
                unchangedIsAllowed: true
            )
        case .scanMoments:
            _ = try await performVerticalScroll(
                lines: -6,
                context: .momentsFeed,
                previousFingerprint: snapshot.fingerprint,
                unchangedIsAllowed: true
            )
            automationNoProgressCount += 1
            if automationNoProgressCount >= 5 { try await finishMediaCollection(snapshot) }
        default:
            throw AutomationRuntimeError.unknownState("Expected \(automationPhase.rawValue)")
        }
    }

    private func calibratedAction(
        context: CalibrationContext,
        kind: CalibrationMarkKind,
        actionKind: PlannedActionKind,
        rationale: String
    ) throws -> PlannedAction {
        guard let mark = calibrationMarks.last(where: { $0.context == context && $0.kind == kind }) else {
            throw AutomationRuntimeError.calibrationMissing("\(context.displayName) / \(kind.displayName)")
        }
        return PlannedAction(
            kind: actionKind,
            point: mark.bounds.center,
            requiredSafeRegion: mark.bounds,
            rationale: rationale
        )
    }

    private func fallbackBackAction(rationale: String) -> PlannedAction {
        let bounds = calibrationMarks.last(where: {
            $0.context == .profile && $0.kind == .safeBackClose
        })?.bounds ?? NormalizedRect(x: 0.057, y: 0.103, width: 0.062, height: 0.04)
        return PlannedAction(kind: .back, point: bounds.center, requiredSafeRegion: bounds, rationale: rationale)
    }

    @discardableResult
    private func performClick(
        _ action: PlannedAction,
        context: CalibrationContext,
        expecting condition: VisiblePostcondition
    ) async throws -> ObservationSnapshot {
        guard let automationWindowFrame else { throw AutomationRuntimeError.mirroringWindowMissing }
        try await focusMirroringApp()
        sessionState.recordProposal(policy: sessionPolicy)
        let decision = try await liveInputExecutor.executeClick(
            action: action,
            windowFrame: automationWindowFrame,
            exclusions: exclusionZones(for: context) + dynamicSocialExclusions,
            emergencyStopActive: sessionState.pauseReason == .emergencyStop,
            sessionPauseReason: sessionState.pauseReason?.summary,
            liveInputEnabled: true
        )
        guard decision.isAllowed else {
            await liveInputExecutor.resolvePostcondition(passed: false)
            throw AutomationRuntimeError.actionBlocked(decision.rejection.map(actionRejectionDescription) ?? "unknown rejection")
        }
        automationActionCount += 1
        recordEvent(.safetyDecision, summary: "Executed \(action.kind.rawValue) · \(action.rationale)")

        var lastResult: PostconditionResult?
        for delay in [800, 650, 650] {
            try await Task.sleep(for: .milliseconds(delay))
            let snapshot = try await captureAutomationFrame()
            let result = postconditionEvaluator.evaluate(condition, against: snapshot)
            lastPostconditionResult = result
            lastResult = result
            if result.status == .passed {
                await liveInputExecutor.resolvePostcondition(passed: true)
                recordEvent(.postcondition, summary: "passed · \(result.summary)")
                return snapshot
            }
        }
        await liveInputExecutor.resolvePostcondition(passed: false)
        throw AutomationRuntimeError.postconditionFailed(lastResult?.summary ?? "No verification frame")
    }

    @discardableResult
    private func performVerticalScroll(
        lines: Int,
        context: CalibrationContext,
        previousFingerprint: String?,
        unchangedIsAllowed: Bool = false
    ) async throws -> Bool {
        guard let automationWindowFrame else { throw AutomationRuntimeError.mirroringWindowMissing }
        try await focusMirroringApp()
        let dynamicExclusions = exclusionZones(for: context) + dynamicSocialExclusions
        guard let action = profileInteractionSafety.scrollAction(lines: lines, avoiding: dynamicExclusions) else {
            throw AutomationRuntimeError.actionBlocked("No non-interactive profile scroll point is available")
        }
        sessionState.recordProposal(policy: sessionPolicy)
        let decision = try await liveInputExecutor.executeVerticalScroll(
            action: action,
            lines: lines,
            windowFrame: automationWindowFrame,
            exclusions: dynamicExclusions,
            emergencyStopActive: sessionState.pauseReason == .emergencyStop,
            sessionPauseReason: sessionState.pauseReason?.summary,
            liveInputEnabled: true
        )
        guard decision.isAllowed else {
            await liveInputExecutor.resolvePostcondition(passed: false)
            throw AutomationRuntimeError.actionBlocked(decision.rejection.map(actionRejectionDescription) ?? "unknown rejection")
        }
        automationActionCount += 1
        try await Task.sleep(for: .milliseconds(700))
        let next = try await captureAutomationFrame()
        let changed = previousFingerprint.map { $0 != next.fingerprint } ?? true
        await liveInputExecutor.resolvePostcondition(passed: changed || unchangedIsAllowed)
        recordEvent(.postcondition, summary: changed ? "passed · content changed after scroll" : "unchanged · bounded feed edge")
        if !changed && !unchangedIsAllowed {
            throw AutomationRuntimeError.postconditionFailed("The vertical scroll did not change visible content")
        }
        return changed
    }

    private func dismissMomentViewer(_ snapshot: ObservationSnapshot) async throws {
        guard let automationWindowFrame,
              let gesture = momentDismissPlanner.proposal(from: calibrationMarks) else {
            throw AutomationRuntimeError.calibrationMissing("Moment viewer / dismiss gesture")
        }
        let mark = calibrationMarks.last {
            $0.context == .momentViewer && $0.kind == .safeMomentDismissGesture
        }
        let required: Set<CalibrationMarkKind> = [.excludeLike]
        let confirmed = Set(calibrationMarks.filter {
            $0.context == .momentViewer && $0.confirmed && $0.kind.isExclusion
        }.map(\.kind))
        for attempt in 0..<2 {
            try await focusMirroringApp()
            sessionState.recordProposal(policy: sessionPolicy)
            let decision = try await liveInputExecutor.executeGesture(
                gesture: gesture,
                windowFrame: automationWindowFrame,
                exclusions: exclusionZones(for: .momentViewer) + dynamicSocialExclusions,
                calibrationConfirmed: mark?.confirmed == true && required.isSubset(of: confirmed),
                emergencyStopActive: sessionState.pauseReason == .emergencyStop,
                sessionPauseReason: sessionState.pauseReason?.summary,
                liveInputEnabled: true
            )
            guard decision.isAllowed else {
                await liveInputExecutor.resolvePostcondition(passed: false)
                throw AutomationRuntimeError.actionBlocked(decision.rejection.map { gestureRejectionDescription($0) } ?? "unknown rejection")
            }
            automationActionCount += 1
            try await Task.sleep(for: .milliseconds(attempt == 0 ? 750 : 950))
            let next = try await captureAutomationFrame()
            let changed = next.screen.kind != .momentViewer
            await liveInputExecutor.resolvePostcondition(passed: changed)
            if changed {
                automationPhase = .scanMoments
                return
            }
            recordEvent(.postcondition, summary: "retry · Moment viewer remained open after dismiss gesture")
            try await Task.sleep(for: .milliseconds(250))
        }
        throw AutomationRuntimeError.postconditionFailed("Moment viewer did not dismiss after two calibrated attempts")
    }

    private func momentKey(_ target: MomentThumbnailTarget, fingerprint: String) -> String {
        if target.index >= 100,
           let date = analysis?.text.first(where: {
               $0.text.range(
                   of: #"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b"#,
                   options: .regularExpression
               ) != nil
           }) {
            return "timeline|\(date.text.lowercased())"
        }
        return "\(fingerprint)|\(target.index)"
    }

    private func scannedMomentCount() -> Int {
        guard let profile = currentCollectedProfile() else { return 0 }
        return (try? profileRepository?.media(profileID: profile.id).filter {
            $0.typedKind == .moment
        }.count) ?? 0
    }

    private func prepareForNewProfile() {
        collectedProfileID = nil
        automationCollectedUsername = nil
        automationAboutMeSelected = false
        automationScrollAttempts = 0
        automationNoProgressCount = 0
        automationUnknownCount = 0
        automationMomentKeys = []
        automationPendingMomentKey = nil
    }

    private func startQwenWorkerIfNeeded() {
        guard qwenWorkerTask == nil,
              let profileRepository,
              let configuration = try? VLMConfigurationStore.defaultStore().load() else { return }
        qwenWorkerTask = Task { [weak self] in
            let processor = AnalysisQueueProcessor(
                repository: profileRepository,
                client: OllamaVLMClient(configuration: configuration),
                configuration: configuration
            )
            while !Task.isCancelled, await processor.processNext() {}
            await MainActor.run { self?.qwenWorkerTask = nil }
        }
    }

    func chooseFixture() {
        let panel = NSOpenPanel()
        panel.title = "Choose a private screenshot fixture"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFixture(at: url)
    }

    func loadFixture(at url: URL) {
        errorMessage = nil
        analysis = nil

        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Could not decode the selected image."
            return
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            errorMessage = "Could not create a pixel image for Vision."
            return
        }

        do {
            let result = try analyzer.analyze(cgImage)
            acceptAnalysis(result, image: image, cgImage: cgImage, fixtureURL: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPermissions() {
        permissionStatus = PermissionInspector.currentStatus()
    }

    func requestScreenRecording() {
        PermissionInspector.requestScreenRecording()
        refreshPermissions()
    }

    func requestAccessibility() {
        PermissionInspector.requestAccessibilityPrompt()
        refreshPermissions()
    }

    func locateMirroringWindow() {
        windowSearchStatus = "Searching…"
        errorMessage = nil

        Task {
            do {
                let candidates = try await MirroringWindowLocator().locateCandidates()
                mirroringWindows = candidates
                if candidates.isEmpty {
                    windowSearchStatus = "No iPhone Mirroring window found"
                } else {
                    windowSearchStatus = "Found \(candidates.count) candidate\(candidates.count == 1 ? "" : "s")"
                    if selectedWindowID == nil || !candidates.contains(where: { $0.id == selectedWindowID }) {
                        selectedWindowID = candidates.first?.id
                    }
                    navigationState = .identifyCurrentScreen
                }
                refreshPermissions()
            } catch {
                windowSearchStatus = "Window search failed"
                errorMessage = error.localizedDescription
            }
        }
    }

    func captureSelectedWindow() {
        guard let selectedWindowID else {
            errorMessage = "Locate and select an iPhone Mirroring window first."
            return
        }

        windowSearchStatus = "Capturing selected window…"
        errorMessage = nil

        Task {
            do {
                let frame = try await WindowCaptureService().capture(windowID: selectedWindowID)
                try validateWindowGeometry(frame)
                let image = NSImage(
                    cgImage: frame.image,
                    size: NSSize(width: frame.image.width, height: frame.image.height)
                )
                let result = try analyzer.analyze(frame.image)
                acceptAnalysis(
                    result,
                    image: image,
                    cgImage: frame.image,
                    fixtureURL: nil,
                    capturedAt: frame.capturedAt
                )
                windowSearchStatus = "Captured window \(selectedWindowID) at \(frame.capturedAt.formatted(date: .omitted, time: .standard))"
                refreshPermissions()
            } catch {
                windowSearchStatus = "Window capture failed"
                errorMessage = error.localizedDescription
                refreshPermissions()
            }
        }
    }

    func captureLocationBurst() {
        guard let selectedWindowID else {
            errorMessage = "Locate and select an iPhone Mirroring window first."
            return
        }

        let frameCount = 5
        windowSearchStatus = "Capturing \(frameCount)-frame location burst…"
        errorMessage = nil

        Task {
            do {
                let frames = try await WindowCaptureService().captureBurst(
                    windowID: selectedWindowID,
                    frameCount: frameCount,
                    intervalMilliseconds: 700
                )
                for frame in frames { try validateWindowGeometry(frame) }
                let analyses = try frames.map { try analyzer.analyze($0.image) }
                guard let lastFrame = frames.last, let lastAnalysis = analyses.last else { return }

                let image = NSImage(
                    cgImage: lastFrame.image,
                    size: NSSize(width: lastFrame.image.width, height: lastFrame.image.height)
                )
                acceptAnalysis(
                    lastAnalysis,
                    image: image,
                    cgImage: lastFrame.image,
                    fixtureURL: nil,
                    capturedAt: lastFrame.capturedAt
                )
                temporalLocation = rotatingLocationBadgeParser.resolve(frames: analyses.map(\.text))

                if let city = temporalLocation?.location?.city {
                    windowSearchStatus = "Resolved \(city) across \(frames.count) frames"
                } else {
                    windowSearchStatus = "No stable city label found across \(frames.count) frames"
                }
                refreshPermissions()
            } catch {
                windowSearchStatus = "Location burst failed"
                errorMessage = error.localizedDescription
                refreshPermissions()
            }
        }
    }

    func proposeGalleryGesture() {
        guard discoveryPolicy.horizontalCarouselEnabledByDefault else {
            galleryGesture = nil
            galleryGestureStatus = "Blocked · horizontal motion failed supervised mirroring validation; use visible-card graph traversal"
            recordEvent(.safetyDecision, summary: galleryGestureStatus)
            return
        }
        galleryGesture = galleryGesturePlanner.proposal(from: calibrationMarks)
        guard galleryGesture != nil else {
            galleryGestureStatus = "Blocked · draw a Profile / Carousel gesture zone first"
            recordEvent(.proposal, summary: galleryGestureStatus)
            return
        }

        sessionState.recordProposal(policy: sessionPolicy)
        if let decision = galleryGestureDecision {
            galleryGestureStatus = decision.isAllowed
                ? "Allowed"
                : "Blocked · \(gestureRejectionDescription(decision.rejection))"
        }
        recordEvent(.proposal, summary: "Gallery swipe proposed")
        recordEvent(.safetyDecision, summary: galleryGestureStatus)
        recordSessionPauseIfNeeded()
    }

    func proposeNextVisibleCard() {
        let targets = visibleRecommendationTargets
        guard !targets.isEmpty else {
            proposedVisibleCardTarget = nil
            visibleCardProposalStatus = "Blocked · no name- or age-anchored visible recommendation photo found"
            recordEvent(.proposal, summary: visibleCardProposalStatus)
            return
        }

        guard let currentUsername = observationSnapshot?.username else {
            proposedVisibleCardTarget = nil
            visibleCardProposalStatus = "Blocked · current username is unavailable, so identity change cannot be verified"
            recordEvent(.proposal, summary: visibleCardProposalStatus)
            return
        }

        let proposals = targets.compactMap { target -> (VisibleRecommendationTarget, VisibleRecommendationCandidate, RecommendationTraversalDecision)? in
            let candidate = VisibleRecommendationCandidate(
                profileKey: target.profileKey,
                displayedAge: target.displayedAge,
                genderHint: .unknown
            )
            let graphDecision = recommendationLedger.decision(for: candidate)
            return graphDecision.isOpenProposal ? (target, candidate, graphDecision) : nil
        }
        guard let proposal = proposals.first(where: { $0.0.displayedAge.map { (18...21).contains($0) } == true })
                ?? proposals.first else {
            proposedVisibleCardTarget = nil
            visibleCardProposalStatus = "Blocked · every visible card is already visited or exceeds the routing limit"
            recordEvent(.proposal, summary: visibleCardProposalStatus)
            return
        }

        let (target, candidate, graphDecision) = proposal
        proposedVisibleCardTarget = target
        sessionState.recordProposal(policy: sessionPolicy)
        let safetyDecision = previewDecision
        let ageLabel = target.displayedAge.map(String.init) ?? "unknown"
        if let rejection = safetyDecision.rejection, rejection != .dryRunRequired {
            pendingGraphCandidate = nil
            pendingGraphDecision = nil
            visibleCardProposalStatus = "\(target.profileKey) · age \(ageLabel) · blocked: \(actionRejectionDescription(rejection))"
        } else {
            pendingGraphCandidate = candidate
            pendingGraphDecision = graphDecision
            pendingPostcondition = .profileIdentityChanged(previousUsername: currentUsername)
            lastPostconditionResult = nil
            visibleCardProposalStatus = "\(target.profileKey) · age \(ageLabel) · safe photo geometry; identity check armed"
        }
        recordEvent(.proposal, summary: "Visible-card photo proposed for \(target.profileKey), displayed age \(ageLabel)")
        recordEvent(.safetyDecision, summary: visibleCardProposalStatus)
        recordSessionPauseIfNeeded()
    }

    func proposeNextMomentThumbnail() {
        let targets = momentThumbnailTargets
        guard !targets.isEmpty else {
            proposedMomentThumbnailTarget = nil
            momentThumbnailProposalStatus = "Blocked · capture the scrolled Moments grid and confirm its safe region"
            recordEvent(.proposal, summary: momentThumbnailProposalStatus)
            return
        }
        let scannedCount = (try? currentCollectedProfile().map {
            try profileRepository?.media(profileID: $0.id).filter { $0.typedKind == .moment }.count ?? 0
        }) ?? 0
        let target = targets[scannedCount % targets.count]
        proposedMomentThumbnailTarget = target
        proposedVisibleCardTarget = nil
        pendingPostcondition = .viewerDetected
        lastPostconditionResult = nil
        sessionState.recordProposal(policy: sessionPolicy)
        let decision = previewDecision
        if decision.rejection == .dryRunRequired {
            momentThumbnailProposalStatus = "Cell \(target.index + 1) · safe image geometry; viewer check armed"
        } else if let rejection = decision.rejection {
            momentThumbnailProposalStatus = "Cell \(target.index + 1) · blocked: \(actionRejectionDescription(rejection))"
        } else {
            momentThumbnailProposalStatus = "Cell \(target.index + 1) · allowed"
        }
        recordEvent(.proposal, summary: momentThumbnailProposalStatus)
        recordEvent(.safetyDecision, summary: momentThumbnailProposalStatus)
        recordSessionPauseIfNeeded()
    }

    func proposeMomentViewerDismiss() {
        galleryGesture = momentDismissPlanner.proposal(from: calibrationMarks)
        guard galleryGesture != nil else {
            galleryGestureStatus = "Blocked · confirm a Moment viewer dismiss gesture region first"
            return
        }
        galleryGestureStatus = galleryGestureDecision?.rejection == .dryRunRequired
            ? "Safe downward viewer-dismiss path; profile-page check required after execution"
            : "Blocked · \(gestureRejectionDescription(galleryGestureDecision?.rejection))"
        recordEvent(.proposal, summary: galleryGestureStatus)
        recordEvent(.safetyDecision, summary: galleryGestureStatus)
    }

    func armGalleryPostcondition() {
        guard let observationSnapshot else {
            galleryGestureStatus = "Capture a baseline frame before arming a postcondition"
            return
        }
        pendingPostcondition = .contentHashChanged(previous: observationSnapshot.fingerprint)
        lastPostconditionResult = nil
        galleryGestureStatus = "Armed · manually swipe, then capture the next frame"
        recordEvent(.postcondition, summary: "Armed content-change postcondition")
    }

    func armProfileChangePostcondition() {
        guard let username = observationSnapshot?.username else {
            galleryGestureStatus = "Current profile username is not visible; identity check cannot be armed"
            return
        }
        pendingPostcondition = .profileIdentityChanged(previousUsername: username)
        lastPostconditionResult = nil
        galleryGestureStatus = "Armed · manually open a safe card, then capture the new profile"
        recordEvent(.postcondition, summary: "Armed profile-identity postcondition from \(username)")
    }

    func engageEmergencyStop() {
        automationTask?.cancel()
        automationTask = nil
        qwenWorkerTask?.cancel()
        qwenWorkerTask = nil
        sessionState.engageEmergencyStop()
        navigationState = .emergencyStopped
        automationRunState = .stopped
        automationStatus = "STOPPED · all automatic input is blocked"
        galleryGestureStatus = "Blocked · emergency stop is latched"
        recordEvent(.emergencyStop, summary: sessionState.pauseReason?.summary ?? "Emergency stop")
    }

    func checkpointVerifiedProfile() {
        guard canCheckpointProfile,
              let username = profileAccumulator.username,
              let image = currentCGImage,
              let profileRepository else {
            collectionStatus = "Blocked · opened profile must verify username, female badge, age 18–21, and target MBTI"
            return
        }
        do {
            let record = try profileRepository.upsert(ProfileDraft(
                usernameRaw: username,
                displayName: profileAccumulator.displayName,
                age: profileAccumulator.age,
                gender: profileAccumulator.gender,
                mbti: profileAccumulator.mbti,
                location: profileAccumulator.location,
                bio: profileAccumulator.bio,
                hobbies: profileAccumulator.hobbies,
                education: profileAccumulator.education,
                occupation: profileAccumulator.occupation,
                profileCompletenessScore: profileAccumulator.completenessScore,
                status: .new
            ))
            collectedProfileID = record.id
            let largestFace = analysis?.faces.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
            let area = largestFace.map { $0.bounds.width * $0.bounds.height } ?? 0
            let quality = largestFace?.captureQuality.map(Double.init)
            let usable = area >= CollectionLimits.hardenedDefault.minimumFaceAreaRatio
                && (quality ?? 0) >= CollectionLimits.hardenedDefault.minimumFaceCaptureQuality
            _ = try mediaStore?.persist(
                image: image,
                profileID: record.id,
                kind: .profileTop,
                sourceSequence: record.visitCount,
                faceCount: analysis?.faces.count ?? 0,
                largestFaceRatio: area,
                faceCaptureQuality: quality,
                usableFace: usable,
                retained: false
            )
            try saveCollectionCheckpoint(profileID: record.id)
            collectionStatus = "Checkpointed \(record.usernameNormalized) locally · visit \(record.visitCount)"
            recordEvent(.transition, summary: collectionStatus)
        } catch {
            collectionStatus = "Checkpoint failed · \(error.localizedDescription)"
        }
    }

    func checkpointViewerPhoto() {
        guard let screen = screenClassification?.kind,
              let kind = screen == .pfpViewer ? MediaKind.pfp : screen == .momentViewer ? MediaKind.moment : nil,
              let sourceImage = currentCGImage,
              let observations = analysis?.text,
              let region = ViewerPhotoRegionDetector().region(for: screen, observations: observations),
              let cropped = WindowPhotoCropper().crop(sourceImage, to: region.bounds),
              let profile = currentCollectedProfile(),
              let profileRepository,
              let mediaStore else {
            collectionStatus = "Blocked · capture a recognized PFP or Moment viewer for a checkpointed profile"
            return
        }

        do {
            let existing = try profileRepository.media(profileID: profile.id)
            let scannedPhotos = existing.filter { $0.typedKind == .pfp || $0.typedKind == .moment }
            let scannedMoments = existing.filter { $0.typedKind == .moment }
            guard kind != .moment || scannedMoments.count < CollectionLimits.hardenedDefault.maximumScannedPhotos else {
                collectionStatus = "Blocked · 20-Moment scan limit reached"
                return
            }
            let retainedPhotos = scannedPhotos.filter(\.retained)
            let croppedAnalysis = try analyzer.analyze(cropped)
            if kind == .moment,
               let reason = MomentMediaCaptureValidator().rejectionReason(observations: croppedAnalysis.text) {
                collectionStatus = "Skipped Moment capture · \(reason); open the full photo before saving"
                return
            }
            let largest = croppedAnalysis.faces.max {
                $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
            }
            let area = largest.map { $0.bounds.width * $0.bounds.height } ?? 0
            let quality = largest?.captureQuality.map(Double.init)
            let usable = area >= CollectionLimits.hardenedDefault.minimumFaceAreaRatio
                && (quality ?? 0) >= CollectionLimits.hardenedDefault.minimumFaceCaptureQuality
            let shouldRetain = retainedPhotos.count < CollectionLimits.hardenedDefault.maximumRetainedPhotos
            let record = try mediaStore.persist(
                image: cropped,
                profileID: profile.id,
                kind: kind,
                sourceSequence: scannedPhotos.count + 1,
                faceCount: croppedAnalysis.faces.count,
                largestFaceRatio: area,
                faceCaptureQuality: quality,
                usableFace: usable,
                retained: shouldRetain
            )
            guard record != nil else {
                collectionStatus = "Duplicate photo ignored by perceptual hash"
                return
            }
            try saveCollectionCheckpoint(profileID: profile.id)
            let scanLabel = kind == .moment ? "Moment \(scannedMoments.count + 1)/20" : "PFP"
            collectionStatus = "Saved visible \(kind.rawValue) frame as PNG · \(scanLabel) · retained \(shouldRetain ? retainedPhotos.count + 1 : retainedPhotos.count)/10"
        } catch {
            collectionStatus = "Photo checkpoint failed · \(error.localizedDescription)"
        }
    }

    func finalizeCurrentProfileMedia() {
        guard let profile = currentCollectedProfile(),
              let profileRepository else {
            collectionStatus = "Checkpoint an eligible profile before finalizing media"
            return
        }
        guard let retentionGroup = profile.typedGroup
                ?? (profile.isPreferredLocationNoMBTI ? MBTIGroup.secondary : nil) else {
            collectionStatus = "Profile is neither target MBTI nor a preferred-location exception"
            return
        }
        do {
            let photos = try profileRepository.media(profileID: profile.id).filter {
                $0.typedKind == .pfp || $0.typedKind == .moment
            }
            let candidates = photos.map {
                MediaCandidate(
                    id: UUID(uuidString: $0.id) ?? UUID(),
                    perceptualHash: $0.perceptualHash,
                    faceCount: $0.faceCount,
                    largestFaceRatio: $0.largestFaceRatio,
                    captureQuality: $0.faceCaptureQuality,
                    contextStrength: $0.typedKind == .moment ? 0.5 : 0
                )
            }
            let plan = MediaRetentionPlanner().plan(candidates: candidates)
            let retainedIDs = Set(plan.retainedIDs.map(\.uuidString))
            let configuration = try? VLMConfigurationStore.defaultStore().load()
            let noFacePolicy = NoFacePolicy(enabledForPrimary: configuration?.enforceNoFaceForPrimary ?? true)
            switch noFacePolicy.decision(group: retentionGroup, candidates: candidates, feedExhausted: true) {
            case .rejectAndPurge:
                try profileRepository.updateStatus(id: profile.id, status: .rejectedNoFace, reason: "no_usable_face_in_pfp_or_scanned_moments")
                try profileRepository.purgeMedia(profileID: profile.id)
                collectionStatus = "Rejected no-face · media purged; username tombstone retained"
            case .retainForReview:
                try profileRepository.setRetainedMedia(profileID: profile.id, mediaIDs: retainedIDs)
                try profileRepository.updateStatus(id: profile.id, status: .review)
                collectionStatus = "Media finalized for local review · retained \(retainedIDs.count)/\(plan.scannedCount) balanced photos"
            case .continueScanning:
                collectionStatus = "Continue scanning until a usable face, feed bottom, or 20 photos"
            }
        } catch {
            collectionStatus = "Media finalization failed · \(error.localizedDescription)"
        }
    }

    func queueCurrentProfileAnalysis() {
        guard let profile = currentCollectedProfile(), let profileRepository else {
            collectionStatus = "Checkpoint a profile before queueing analysis"
            return
        }
        do {
            let media = try profileRepository.media(profileID: profile.id, retainedOnly: true)
            guard !media.isEmpty else {
                collectionStatus = "Retain at least one PFP or Moment photo before queueing analysis"
                return
            }
            let config = try VLMConfigurationStore.defaultStore().load()
            let facePaths = AnalysisMediaSelector.faceMedia(from: media).map(\.filePath)
            let lifestylePaths = AnalysisMediaSelector.lifestyleMedia(from: media).map(\.filePath)
            var queued = 0
            if !facePaths.isEmpty {
                _ = try profileRepository.enqueueAnalysis(
                    profileID: profile.id,
                    type: .faceVerification,
                    modelName: config.model,
                    promptVersion: VLMPromptLibrary.faceVerificationVersion,
                    mediaPaths: Array(facePaths)
                )
                _ = try profileRepository.enqueueAnalysis(
                    profileID: profile.id,
                    type: .visualAppeal,
                    modelName: config.model,
                    promptVersion: VLMPromptLibrary.visualAppealVersion,
                    mediaPaths: Array(facePaths)
                )
                queued += 2
            }
            if !lifestylePaths.isEmpty {
                _ = try profileRepository.enqueueAnalysis(
                    profileID: profile.id,
                    type: .lifestyle,
                    modelName: config.model,
                    promptVersion: VLMPromptLibrary.lifestyleVersion,
                    mediaPaths: Array(lifestylePaths)
                )
                queued += 1
            }
            collectionStatus = queued == 0
                ? "No eligible retained media for analysis"
                : "Queued \(queued) versioned Qwen job\(queued == 1 ? "" : "s") locally"
        } catch {
            collectionStatus = "Analysis queue failed · \(error.localizedDescription)"
        }
    }

    func resetDryRunSession() {
        automationTask?.cancel()
        automationTask = nil
        sessionState = NavigationSessionState()
        pendingPostcondition = nil
        lastPostconditionResult = nil
        galleryGesture = nil
        galleryGestureStatus = "Visible-card profile hopping is active"
        proposedVisibleCardTarget = nil
        visibleCardProposalStatus = "No visible-card proposal"
        proposedMomentThumbnailTarget = nil
        momentThumbnailProposalStatus = "No Moment thumbnail proposal"
        recommendationLedger = RecommendationTraversalLedger()
        pendingGraphCandidate = nil
        pendingGraphDecision = nil
        navigationState = screenClassification?.navigationState ?? .identifyCurrentScreen
        windowGeometryGuard = nil
        automationRunState = .idle
        automationStatus = "Ready to collect automatically"
        recordEvent(.sessionReset, summary: "Started a new session")
    }

    func addCalibrationMark(bounds: NormalizedRect) {
        guard bounds.isValidNormalizedRect, bounds.width >= 0.005, bounds.height >= 0.005 else {
            errorMessage = "Calibration regions must be drawn inside the captured image."
            return
        }
        calibrationMarks.removeAll {
            $0.context == selectedCalibrationContext && $0.kind == selectedCalibrationKind
        }
        calibrationMarks.append(
            CalibrationMark(
                context: selectedCalibrationContext,
                kind: selectedCalibrationKind,
                bounds: bounds
            )
        )
        calibrationStatus = "Unsaved changes"
    }

    func undoCalibrationMark() {
        guard !calibrationMarks.isEmpty else { return }
        calibrationMarks.removeLast()
        calibrationStatus = "Unsaved changes"
    }

    func clearCalibrationMarks() {
        calibrationMarks = []
        calibrationStatus = "Unsaved changes"
    }

    func loadObservedBaseline() {
        calibrationMarks = ObservedHelloTalkCalibration.marks
        calibrationStatus = "Loaded supervised 2026-08-03 baseline; confirm before live use"
    }

    func confirmSelectedCalibrationMark() {
        guard analysis != nil else {
            calibrationStatus = "Load or capture the matching screen before confirming a region"
            return
        }
        guard let index = calibrationMarks.firstIndex(where: {
            $0.context == selectedCalibrationContext && $0.kind == selectedCalibrationKind
        }) else {
            calibrationStatus = "Draw the selected region before confirming it"
            return
        }
        let mark = calibrationMarks[index]
        calibrationMarks[index] = CalibrationMark(
            id: mark.id,
            context: mark.context,
            kind: mark.kind,
            bounds: mark.bounds,
            confirmed: true
        )
        calibrationStatus = "Confirmed locally for this calibration session"
        if mark.kind == .safeCarouselGesture { proposeGalleryGesture() }
    }

    func saveCalibration() {
        guard let analysis else {
            errorMessage = "Load or capture an image before saving calibration."
            return
        }
        do {
            let store = try CalibrationStore.defaultStore()
            let profile = CalibrationProfile(
                referencePixelWidth: analysis.imageWidth,
                referencePixelHeight: analysis.imageHeight,
                marks: calibrationMarks
            )
            try store.save(profile)
            calibrationStatus = "Saved locally: \(store.fileURL.path)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCalibration() {
        do {
            let store = try CalibrationStore.defaultStore()
            guard let profile = try store.load() else {
                calibrationStatus = "No saved calibration"
                return
            }
            calibrationMarks = profile.marks
            calibrationStatus = "Loaded \(profile.marks.count) marks"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    private func acceptAnalysis(
        _ result: FixtureAnalysis,
        image: NSImage,
        cgImage: CGImage,
        fixtureURL: URL?,
        capturedAt: Date = Date()
    ) {
        let previousState = navigationState
        let snapshot = snapshotBuilder.build(from: result, image: cgImage, capturedAt: capturedAt)

        fixtureImage = image
        self.fixtureURL = fixtureURL
        currentCGImage = cgImage
        analysis = result
        proposedVisibleCardTarget = nil
        visibleCardProposalStatus = "No visible-card proposal for this frame"
        proposedMomentThumbnailTarget = nil
        momentThumbnailProposalStatus = "No Moment thumbnail proposal for this frame"
        temporalLocation = rotatingLocationBadgeParser.resolve(frames: [result.text])
        screenClassification = snapshot.screen
        observationSnapshot = snapshot
        let profileMetadata: ParsedProfileMetadata
        if [.profileTop, .profilePersonalInfo].contains(snapshot.screen.kind) {
            profileMetadata = profileMetadataParser.parse(result.text)
        } else {
            profileMetadata = ParsedProfileMetadata()
        }
        profileAccumulator.observe(
            snapshot: snapshot,
            analysis: result,
            age: profileHeaderParser.bestAge(in: result.text),
            gender: profileHeaderParser.bestAge(in: result.text).map {
                genderBadgeClassifier.classify(image: cgImage, ageMatch: $0).hint
            },
            mbti: mbtiParser.matches(in: result.text).first?.type,
            location: locationNormalizer.normalize(result.text.map(\.text).joined(separator: " · ")),
            metadata: profileMetadata
        )

        let automationCanTraverseUnknown = automationRunState == .running && [
            AutomationPhase.scanProfile,
            .returnToTop,
            .scanMoments,
            .exitMoments,
            .seekSuggestions,
            .openRecommendation
        ].contains(automationPhase)
        if snapshot.screen.kind != .unknown || !automationCanTraverseUnknown {
            sessionState.recordScreen(snapshot.screen.kind, policy: sessionPolicy, now: capturedAt)
        }
        if let username = snapshot.username, username != lastProfileUsername,
           [.profileTop, .profilePersonalInfo, .suggestedProfilesGallery, .momentsFeed].contains(snapshot.screen.kind) {
            sessionState.recordProfileVisit(policy: sessionPolicy, now: capturedAt)
            lastProfileUsername = username
        }

        if let pendingPostcondition {
            let postconditionResult = postconditionEvaluator.evaluate(pendingPostcondition, against: snapshot)
            lastPostconditionResult = postconditionResult
            self.pendingPostcondition = nil
            if postconditionResult.status == .passed,
               let candidate = pendingGraphCandidate,
               let decision = pendingGraphDecision {
                recommendationLedger.recordOpened(candidate, decision: decision)
                if let username = snapshot.username {
                    recommendationLedger.recordVerifiedProfileKey(username)
                }
                recordEvent(.transition, summary: "Verified graph hop to \(snapshot.username ?? candidate.profileKey)")
            }
            pendingGraphCandidate = nil
            pendingGraphDecision = nil
            recordEvent(.postcondition, summary: "\(postconditionResult.status.rawValue) · \(postconditionResult.summary)")
        }

        if sessionState.pauseReason == .emergencyStop {
            navigationState = .emergencyStopped
        } else if sessionState.isPaused {
            navigationState = .pausedUnknownState
        } else {
            navigationState = snapshot.screen.navigationState
        }

        recordEvent(
            .observation,
            summary: "\(snapshot.screen.kind.rawValue) · \(Int(snapshot.screen.confidence * 100))% · \(snapshot.fingerprint)"
        )
        if previousState != navigationState {
            recordEvent(.transition, summary: "\(previousState.rawValue) → \(navigationState.rawValue)")
        }
        recordSessionPauseIfNeeded()
    }

    private func exclusionZones(for context: CalibrationContext) -> [ExclusionZone] {
        calibrationMarks.filter { $0.context == context && $0.kind.isExclusion }.map {
            ExclusionZone(label: $0.kind.displayName, bounds: $0.bounds)
        }
    }

    private func validateWindowGeometry(_ frame: CapturedWindowFrame) throws {
        if let windowGeometryGuard {
            try windowGeometryGuard.validate(frame)
        } else {
            windowGeometryGuard = WindowGeometryGuard(frame: frame)
        }
    }

    private func currentCollectedProfile() -> ProfileRecord? {
        if let collectedProfileID, let profile = try? profileRepository?.profile(id: collectedProfileID) {
            return profile
        }
        if let username = profileAccumulator.username,
           let profile = try? profileRepository?.profile(username: username) {
            return profile
        }
        return nil
    }

    private func saveCollectionCheckpoint(profileID: String) throws {
        guard let profileRepository else { return }
        let media = try profileRepository.media(profileID: profileID)
        let photos = media.filter { $0.typedKind == .pfp || $0.typedKind == .moment }
        let checkpointUsername: String?
        if let observedUsername = profileAccumulator.username {
            checkpointUsername = observedUsername
        } else {
            checkpointUsername = try profileRepository.profile(id: profileID)?.usernameNormalized
        }
        let checkpoint = CollectionCheckpoint(
            navigation: NavigationSnapshot(state: navigationState, pendingPostcondition: pendingPostcondition),
            currentUsername: checkpointUsername,
            currentProfileID: profileID,
            scannedPhotoCount: photos.count,
            retainedPhotoCount: photos.filter(\.retained).count,
            perceptualHashes: Set(photos.map(\.perceptualHash))
        )
        try CollectionCheckpointStore.defaultStore().save(checkpoint)
    }

    private func recordSessionPauseIfNeeded() {
        guard let reason = sessionState.pauseReason else { return }
        recordEvent(.sessionPaused, summary: reason.summary)
    }

    private func recordEvent(_ kind: NavigationEventKind, summary: String) {
        let event = NavigationEvent(kind: kind, state: navigationState, summary: summary)
        navigationEvents.append(event)
        if navigationEvents.count > 100 {
            navigationEvents.removeFirst(navigationEvents.count - 100)
        }
        if let eventStore {
            Task { try? await eventStore.append(event) }
        }
    }

    private func gestureRejectionDescription(_ rejection: GestureSafetyRejection?) -> String {
        switch rejection {
        case .unsupportedGestureKind: "unsupported gesture"
        case .outsideWindow: "path leaves the window"
        case .outsideRequiredSafeRegion: "path leaves the calibrated zone"
        case .intersectsExclusionZone(let label): "path intersects \(label)"
        case .calibrationIncomplete: "carousel or fixed social-bar calibration is incomplete"
        case .emergencyStopActive: "emergency stop is active"
        case .sessionPaused(let reason): reason
        case .dryRunRequired: "dry-run mode forbids input"
        case nil: "unknown safety rejection"
        }
    }

    private func actionRejectionDescription(_ rejection: ActionSafetyRejection) -> String {
        switch rejection {
        case .outsideWindow: "point leaves the window"
        case .outsideRequiredSafeRegion: "point leaves the photo-safe region"
        case .intersectsExclusionZone(let label): "point intersects \(label)"
        case .emergencyStopActive: "emergency stop is active"
        case .sessionPaused(let reason): reason
        case .dryRunRequired: "dry-run mode forbids input"
        }
    }
}

private struct ProfileObservationAccumulator {
    var username: String?
    var displayName: String?
    var age: Int?
    var gender: GenderBadgeHint = .unknown
    var mbti: MBTIType?
    var location: NormalizedLocation?
    var bio: String?
    var hobbies: [String] = []
    var education: String?
    var occupation: String?

    var evidence: OpenedProfileEvidence {
        OpenedProfileEvidence(
            username: username,
            age: age,
            gender: gender,
            mbti: mbti,
            locationScore: location?.score
        )
    }

    var completenessScore: Double {
        let signals: [Bool] = [
            username != nil,
            displayName != nil,
            age != nil,
            gender != .unknown,
            mbti != nil,
            location?.city != nil || location?.country != nil,
            bio != nil,
            !hobbies.isEmpty,
            education != nil,
            occupation != nil
        ]
        return Double(signals.filter { $0 }.count) / Double(signals.count) * 100
    }

    mutating func observe(
        snapshot: ObservationSnapshot,
        analysis: FixtureAnalysis,
        age: ProfileAgeMatch?,
        gender: GenderBadgeHint?,
        mbti: MBTIType?,
        location: NormalizedLocation,
        metadata: ParsedProfileMetadata
    ) {
        if let observed = snapshot.username, observed != username {
            self = ProfileObservationAccumulator(username: observed)
        }
        if username == nil { username = snapshot.username }
        if let age { self.age = age.age }
        if let gender, gender != .unknown { self.gender = gender }
        if let mbti { self.mbti = mbti }
        if location.city != nil || location.province != nil || location.country != nil { self.location = location }
        if let incomingBio = metadata.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingBio.isEmpty,
           incomingBio.count >= (bio?.count ?? 0) {
            bio = incomingBio
        }
        if !metadata.hobbies.isEmpty {
            var seen = Set(hobbies.map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
            })
            hobbies += metadata.hobbies.filter {
                seen.insert(
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
                ).inserted
            }
        }
        if let value = metadata.education, value.count >= (education?.count ?? 0) { education = value }
        if let value = metadata.occupation, value.count >= (occupation?.count ?? 0) { occupation = value }
        if displayName == nil {
            displayName = analysis.text
                .filter { !$0.text.hasPrefix("@") && $0.bounds.minY < 0.35 }
                .sorted { $0.bounds.minY < $1.bounds.minY }
                .first?.text
        }
    }
}
