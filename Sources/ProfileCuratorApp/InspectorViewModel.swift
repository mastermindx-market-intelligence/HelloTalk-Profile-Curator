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
    @Published var galleryGestureStatus = "No proposal"

    let previewAction = DefaultInspectorCalibration.previewAction
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
    private let eventStore: NavigationEventLogStore?
    private var currentCGImage: CGImage?
    private var lastProfileUsername: String?

    init() {
        eventStore = try? NavigationEventLogStore.defaultStore()
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

    var previewDecision: ActionSafetyDecision {
        ActionSafetyValidator().validate(
            previewAction,
            exclusionZones: previewExclusions,
            emergencyStopActive: sessionState.pauseReason == .emergencyStop,
            sessionPauseReason: sessionState.pauseReason?.summary,
            liveInputEnabled: false
        )
    }

    var galleryGestureDecision: GestureSafetyDecision? {
        guard let galleryGesture else { return nil }
        let mark = calibrationMarks.first {
            $0.context == .profile && $0.kind == .safeCarouselGesture
        }
        let requiredExclusions: Set<CalibrationMarkKind> = [.excludeFollow, .excludeSayHi, .excludeGift]
        let confirmedExclusions = Set(calibrationMarks.filter {
            $0.context == .profile && $0.confirmed && $0.kind.isExclusion
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

    func resetDryRunSession() {
        sessionState = NavigationSessionState()
        pendingPostcondition = nil
        lastPostconditionResult = nil
        galleryGesture = nil
        galleryGestureStatus = "No proposal"
        navigationState = screenClassification?.navigationState ?? .identifyCurrentScreen
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
        temporalLocation = rotatingLocationBadgeParser.resolve(frames: [result.text])
        screenClassification = snapshot.screen
        observationSnapshot = snapshot

        sessionState.recordScreen(snapshot.screen.kind, policy: sessionPolicy, now: capturedAt)
        if let username = snapshot.username, username != lastProfileUsername,
           [.profileTop, .profilePersonalInfo, .suggestedProfilesGallery, .momentsFeed].contains(snapshot.screen.kind) {
            sessionState.recordProfileVisit(policy: sessionPolicy, now: capturedAt)
            lastProfileUsername = username
        }

        if let pendingPostcondition {
            let result = postconditionEvaluator.evaluate(pendingPostcondition, against: snapshot)
            lastPostconditionResult = result
            self.pendingPostcondition = nil
            recordEvent(.postcondition, summary: "\(result.status.rawValue) · \(result.summary)")
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
}
