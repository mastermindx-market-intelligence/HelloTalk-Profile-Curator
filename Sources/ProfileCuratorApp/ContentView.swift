import ProfileCuratorCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: InspectorViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HSplitView {
                FixtureCanvas(
                    image: model.fixtureImage,
                    analysis: model.analysis,
                    showOCRBoxes: model.showOCRBoxes,
                    showFaceBoxes: model.showFaceBoxes,
                    showSafetyPreview: model.showSafetyPreview,
                    action: model.previewAction,
                    gesture: model.galleryGesture,
                    exclusions: model.previewExclusions,
                    calibrationMode: model.calibrationMode,
                    calibrationMarks: model.calibrationMarks,
                    onCalibrationRect: model.addCalibrationMark
                )
                .frame(minWidth: 650)
                .padding(12)

                inspectorSidebar
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 430)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Load Fixture…", systemImage: "photo.badge.plus") {
                model.chooseFixture()
            }
            .keyboardShortcut("o")

            Button("Locate iPhone Mirroring", systemImage: "iphone.gen3.radiowaves.left.and.right") {
                model.locateMirroringWindow()
            }

            Button("Capture Selected", systemImage: "viewfinder") {
                model.captureSelectedWindow()
            }
            .disabled(model.selectedWindowID == nil)

            Button("Location Burst", systemImage: "rectangle.stack") {
                model.captureLocationBurst()
            }
            .disabled(model.selectedWindowID == nil)

            Spacer()

            Label("Dry run only", systemImage: "shield.checkered")
                .foregroundStyle(.blue)

            Text(model.navigationState.rawValue)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())

            Button("STOP", systemImage: "stop.fill") {
                model.engageEmergencyStop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.sessionState.pauseReason == .emergencyStop)
            .help("Latch the dry-run emergency stop and block every proposal")
        }
        .padding(12)
    }

    private var inspectorSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                permissionSection
                windowSection
                navigationSection
                overlaySection
                calibrationSection
                parsedSection
                eventLogSection
                observationSection
            }
            .padding(16)
        }
    }

    private var permissionSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    "Screen Recording",
                    granted: model.permissionStatus.screenRecordingGranted,
                    request: model.requestScreenRecording
                )
                permissionRow(
                    "Accessibility",
                    granted: model.permissionStatus.accessibilityGranted,
                    request: model.requestAccessibility
                )
                Button("Refresh status") { model.refreshPermissions() }
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ label: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(label)
            Spacer()
            if !granted {
                Button("Request", action: request)
            }
        }
    }

    private var windowSection: some View {
        GroupBox("Mirroring window") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.windowSearchStatus)
                    .font(.callout)
                ForEach(model.mirroringWindows) { window in
                    Button {
                        model.selectedWindowID = window.id
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: model.selectedWindowID == window.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.selectedWindowID == window.id ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(window.title).fontWeight(.medium)
                                Text("\(window.applicationName) · \(Int(window.frame.width))×\(Int(window.frame.height)) · ID \(window.id)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button("Capture and inspect selected window") {
                    model.captureSelectedWindow()
                }
                .disabled(model.selectedWindowID == nil)

                Button("Capture rotating location badge (5 frames)") {
                    model.captureLocationBurst()
                }
                .disabled(model.selectedWindowID == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var overlaySection: some View {
        GroupBox("Inspector overlays") {
            VStack(alignment: .leading) {
                Toggle("OCR boxes", isOn: $model.showOCRBoxes)
                Toggle("Face boxes", isOn: $model.showFaceBoxes)
                Toggle("Safety preview", isOn: $model.showSafetyPreview)
                Divider()
                Label("Yellow: OCR", systemImage: "square")
                    .foregroundStyle(.yellow)
                Label("Green: faces", systemImage: "square")
                    .foregroundStyle(.green)
                Label("Blue: safe fallback", systemImage: "square.dashed")
                    .foregroundStyle(.blue)
                Label("Red: never-click", systemImage: "square")
                    .foregroundStyle(.red)
                Text("Cyan dot: proposed point")
                    .font(.caption)
                Text("Orange path: proposed gallery swipe")
                    .font(.caption)
                Text("Action result: blocked because dry-run is mandatory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var navigationSection: some View {
        GroupBox("Dry-run navigation") {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent("Session", value: model.sessionStatus)
                LabeledContent("Profiles", value: "\(model.sessionState.profileVisitCount)")
                LabeledContent("Unknown streak", value: "\(model.sessionState.consecutiveUnknownScreens)")
                LabeledContent("Traversal", value: model.discoveryTraversalStatus)

                if let classification = model.screenClassification {
                    LabeledContent(
                        "Detected screen",
                        value: "\(classification.kind.rawValue) · \(Int(classification.confidence * 100))%"
                    )
                    if !classification.evidence.isEmpty {
                        Text(classification.evidence.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Label("Horizontal carousel disabled", systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text(model.galleryGestureStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.galleryGesture != nil {
                    Button("Arm content-change check") {
                        model.armGalleryPostcondition()
                    }
                    .disabled(model.observationSnapshot == nil)
                }

                if model.observationSnapshot?.username != nil {
                    Button("Arm profile-change check") {
                        model.armProfileChangePostcondition()
                    }
                }

                if let result = model.lastPostconditionResult {
                    Label(
                        result.summary,
                        systemImage: result.status == .passed
                            ? "checkmark.circle.fill"
                            : result.status == .failed ? "xmark.circle.fill" : "questionmark.circle.fill"
                    )
                    .foregroundStyle(result.status == .passed ? .green : result.status == .failed ? .red : .orange)
                    .font(.caption)
                }

                Button("New dry-run session") {
                    model.resetDryRunSession()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var parsedSection: some View {
        GroupBox("Parsed signals") {
            VStack(alignment: .leading, spacing: 8) {
                if let target = model.targetMBTI {
                    LabeledContent("Target MBTI", value: "\(target.type.rawValue) · \(target.type.group?.rawValue ?? "none")")
                } else {
                    LabeledContent("Target MBTI", value: "Not found")
                }

                if !model.mbtiMatches.isEmpty {
                    LabeledContent("All exact MBTI", value: model.mbtiMatches.map(\.type.rawValue).joined(separator: ", "))
                }

                if let age = model.detectedProfileAge {
                    LabeledContent(
                        "Profile age",
                        value: "\(age.age)\(age.usedBadgeArtifactCorrection ? " · badge correction" : "")"
                    )
                }

                if let gender = model.detectedGenderBadge {
                    LabeledContent(
                        "Gender badge",
                        value: "\(gender.hint.rawValue) · \(Int(gender.confidence * 100))%"
                    )
                }

                if !model.visibleRecommendationAges.isEmpty {
                    LabeledContent(
                        "Visible card ages",
                        value: model.visibleRecommendationAges.map { String($0.age) }.joined(separator: ", ")
                    )
                }

                if let resolution = model.temporalLocation,
                   let location = resolution.location {
                    LabeledContent("Temporal location", value: location.city ?? location.province ?? "Unknown")
                    LabeledContent("Location tier", value: "\(location.tier) · score \(location.score)")
                    LabeledContent("Frames sampled", value: "\(resolution.framesExamined)")
                    if !resolution.nearbyCountsIgnored.isEmpty {
                        LabeledContent(
                            "Nearby metadata",
                            value: resolution.nearbyCountsIgnored.map(String.init).joined(separator: ", ")
                        )
                    }
                } else if let location = model.detectedLocation {
                    LabeledContent("Location", value: location.city ?? location.province ?? "Unknown")
                    LabeledContent("Location tier", value: "\(location.tier) · score \(location.score)")
                }

                if let analysis = model.analysis {
                    LabeledContent("Faces", value: "\(analysis.faces.count)")
                    LabeledContent("OCR observations", value: "\(analysis.text.count)")
                    LabeledContent("Pixels", value: "\(analysis.imageWidth)×\(analysis.imageHeight)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var calibrationSection: some View {
        GroupBox("Calibration editor") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Draw calibration regions", isOn: $model.calibrationMode)
                Picker("Screen", selection: $model.selectedCalibrationContext) {
                    ForEach(CalibrationContext.allCases) { context in
                        Text(context.displayName).tag(context)
                    }
                }
                .pickerStyle(.menu)
                Picker("Region", selection: $model.selectedCalibrationKind) {
                    ForEach(CalibrationMarkKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                Text("Drag over the image to replace the selected region. Purple marks are safe regions/anchors; red marks are exclusions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Observed baseline") { model.loadObservedBaseline() }
                    Button("Confirm selected") { model.confirmSelectedCalibrationMark() }
                    Button("Undo") { model.undoCalibrationMark() }
                        .disabled(model.calibrationMarks.isEmpty)
                    Button("Clear") { model.clearCalibrationMarks() }
                        .disabled(model.calibrationMarks.isEmpty)
                    Spacer()
                    Button("Load") { model.loadCalibration() }
                    Button("Save") { model.saveCalibration() }
                        .disabled(model.calibrationMarks.isEmpty || model.analysis == nil)
                }

                Text(model.calibrationStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                ForEach(model.calibrationMarks.filter { $0.context == model.selectedCalibrationContext }) { mark in
                    HStack {
                        Circle()
                            .fill(mark.kind.isExclusion ? .red : .purple)
                            .frame(width: 7, height: 7)
                        Text(mark.kind.displayName)
                            .font(.caption)
                        if mark.confirmed {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .help("Confirmed in the current supervised calibration")
                        }
                        Spacer()
                        Text(String(format: "%.3f, %.3f", mark.bounds.x, mark.bounds.y))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var eventLogSection: some View {
        GroupBox("Navigation event log") {
            VStack(alignment: .leading, spacing: 7) {
                if model.navigationEvents.isEmpty {
                    Text("Capture or load a frame to begin the audit trail.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.navigationEvents.suffix(12).reversed()) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.kind.rawValue)
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(event.occurredAt.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var observationSection: some View {
        GroupBox("OCR replay") {
            VStack(alignment: .leading, spacing: 6) {
                if let url = model.fixtureURL {
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                }
                if let observations = model.analysis?.text, !observations.isEmpty {
                    ForEach(observations.prefix(40)) { observation in
                        HStack(alignment: .firstTextBaseline) {
                            Text(observation.text)
                                .lineLimit(2)
                            Spacer()
                            Text("\(Int(observation.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Load a fixture to inspect OCR output.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
