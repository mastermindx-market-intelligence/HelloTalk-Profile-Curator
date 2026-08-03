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
    @Published var selectedCalibrationKind: CalibrationMarkKind = .safeAvatar
    @Published var calibrationMarks: [CalibrationMark] = []
    @Published var calibrationStatus = "Not saved"

    let previewAction = DefaultInspectorCalibration.previewAction
    let previewExclusions = DefaultInspectorCalibration.previewExclusions

    private let analyzer = VisionFixtureAnalyzer()
    private let mbtiParser = MBTIParser()
    private let locationNormalizer = LocationNormalizer()

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

    var previewDecision: ActionSafetyDecision {
        ActionSafetyValidator().validate(
            previewAction,
            exclusionZones: previewExclusions,
            emergencyStopActive: false,
            liveInputEnabled: false
        )
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
            fixtureImage = image
            fixtureURL = url
            analysis = result
            navigationState = .identifyCurrentScreen
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
                fixtureImage = image
                fixtureURL = nil
                analysis = result
                windowSearchStatus = "Captured window \(selectedWindowID) at \(frame.capturedAt.formatted(date: .omitted, time: .standard))"
                navigationState = .identifyCurrentScreen
                refreshPermissions()
            } catch {
                windowSearchStatus = "Window capture failed"
                errorMessage = error.localizedDescription
                refreshPermissions()
            }
        }
    }

    func addCalibrationMark(bounds: NormalizedRect) {
        guard bounds.isValidNormalizedRect, bounds.width >= 0.005, bounds.height >= 0.005 else {
            errorMessage = "Calibration regions must be drawn inside the captured image."
            return
        }
        calibrationMarks.removeAll { $0.kind == selectedCalibrationKind }
        calibrationMarks.append(CalibrationMark(kind: selectedCalibrationKind, bounds: bounds))
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
}
