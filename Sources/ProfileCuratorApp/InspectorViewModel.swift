import AppKit
import Foundation
import ProfileCuratorCore

@MainActor
final class InspectorViewModel: ObservableObject {
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

    let previewExclusions = DefaultInspectorCalibration.previewExclusions

    private let analyzer = VisionFixtureAnalyzer()
    private let mbtiParser = MBTIParser()
    private let locationNormalizer = LocationNormalizer()
    private let profileHeaderParser = ProfileHeaderParser()
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
    private let eventStore: NavigationEventLogStore?
    private var currentCGImage: CGImage?
    private var lastProfileUsername: String?
    private var pendingGraphCandidate: VisibleRecommendationCandidate?
    private var windowGeometryGuard: WindowGeometryGuard?
    private let profileRepository: ProfileRepository?
    private let mediaStore: MediaStore?
    private var collectedProfileID: String?
    private var profileAccumulator = ProfileObservationAccumulator()

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
    }

    var momentThumbnailTargets: [MomentThumbnailTarget] {
        guard screenClassification?.kind == .momentsFeed else { return [] }
        return momentThumbnailDetector.targets(from: calibrationMarks)
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
        return "Dry run · \(sessionState.proposalCount)/\(sessionPolicy.maximumProposals) proposals"
    }

    private var activeCalibrationContext: CalibrationContext {
        switch screenClassification?.kind {
        case .connectFeed, .customSearch: .connectFeed
        case .pfpViewer: .pfpViewer
        case .momentsFeed: .momentsFeed
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
        sessionState.engageEmergencyStop()
        navigationState = .emergencyStopped
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
            guard scannedPhotos.count < CollectionLimits.hardenedDefault.maximumScannedPhotos else {
                collectionStatus = "Blocked · 20-photo scan limit reached"
                return
            }
            let retainedPhotos = scannedPhotos.filter(\.retained)
            let croppedAnalysis = try analyzer.analyze(cropped)
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
            collectionStatus = "Saved visible \(kind.rawValue) frame as PNG \(scannedPhotos.count + 1)/20 · retained \(shouldRetain ? retainedPhotos.count + 1 : retainedPhotos.count)/10"
        } catch {
            collectionStatus = "Photo checkpoint failed · \(error.localizedDescription)"
        }
    }

    func finalizeCurrentProfileMedia() {
        guard let profile = currentCollectedProfile(),
              let group = profile.typedGroup,
              let profileRepository else {
            collectionStatus = "Checkpoint an eligible profile before finalizing media"
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
            switch noFacePolicy.decision(group: group, candidates: candidates, feedExhausted: true) {
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
            let facePaths = media.filter { $0.usableFace || $0.typedKind == .pfp }.prefix(3).map(\.filePath)
            let lifestylePaths = media.filter { $0.typedKind == .moment }.prefix(10).map(\.filePath)
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
        recordEvent(.sessionReset, summary: "Started a new dry-run session")
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
        let snapshot = snapshotBuilder.build(from: result, capturedAt: capturedAt)

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
        profileAccumulator.observe(
            snapshot: snapshot,
            analysis: result,
            age: profileHeaderParser.bestAge(in: result.text),
            gender: profileHeaderParser.bestAge(in: result.text).map {
                genderBadgeClassifier.classify(image: cgImage, ageMatch: $0).hint
            },
            mbti: mbtiParser.firstTarget(in: result.text)?.type,
            location: locationNormalizer.normalize(result.text.map(\.text).joined(separator: " · "))
        )

        sessionState.recordScreen(snapshot.screen.kind, policy: sessionPolicy, now: capturedAt)
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
        let checkpoint = CollectionCheckpoint(
            navigation: NavigationSnapshot(state: navigationState, pendingPostcondition: pendingPostcondition),
            currentUsername: profileAccumulator.username,
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

    var evidence: OpenedProfileEvidence {
        OpenedProfileEvidence(username: username, age: age, gender: gender, mbti: mbti)
    }

    var completenessScore: Double {
        let signals: [Bool] = [username != nil, displayName != nil, age != nil, gender != .unknown, mbti != nil, location?.city != nil]
        return Double(signals.filter { $0 }.count) / Double(signals.count) * 100
    }

    mutating func observe(
        snapshot: ObservationSnapshot,
        analysis: FixtureAnalysis,
        age: ProfileAgeMatch?,
        gender: GenderBadgeHint?,
        mbti: MBTIType?,
        location: NormalizedLocation
    ) {
        if let observed = snapshot.username, observed != username {
            self = ProfileObservationAccumulator(username: observed)
        }
        if username == nil { username = snapshot.username }
        if let age { self.age = age.age }
        if let gender, gender != .unknown { self.gender = gender }
        if let mbti { self.mbti = mbti }
        if location.city != nil || location.province != nil { self.location = location }
        if displayName == nil {
            displayName = analysis.text
                .filter { !$0.text.hasPrefix("@") && $0.bounds.minY < 0.35 }
                .sorted { $0.bounds.minY < $1.bounds.minY }
                .first?.text
        }
    }
}
