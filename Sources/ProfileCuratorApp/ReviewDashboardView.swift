import AppKit
import ProfileCuratorCore
import SwiftUI

struct ReviewDashboardView: View {
    @ObservedObject var model: ReviewDashboardViewModel

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)]

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                controls
                Divider()
                if model.records.isEmpty {
                    ContentUnavailableView(
                        "No profiles",
                        systemImage: "person.crop.rectangle.stack",
                        description: Text(model.statusMessage)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(model.records) { item in
                                ProfileGridCard(item: item, selected: item.id == model.selectedProfileID)
                                    .onTapGesture { model.select(item) }
                            }
                        }
                        .padding(14)
                    }
                }
                Divider()
                pagination
            }
            .frame(minWidth: 620)

            ProfileDetailView(model: model)
                .frame(minWidth: 340, idealWidth: 410)
        }
        .onAppear { model.refresh() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Search username or name", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.refresh(resetPage: true) }
                Picker("Section", selection: $model.section) {
                    ForEach(DashboardSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 210)
                .onChange(of: model.section) { _, _ in model.refresh(resetPage: true) }
                Picker("Sort", selection: $model.sort) {
                    ForEach(ProfileSort.allCases, id: \.self) { Text(sortLabel($0)).tag($0) }
                }
                .frame(width: 180)
                .onChange(of: model.sort) { _, _ in model.refresh(resetPage: true) }
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
            }
            DisclosureGroup("Advanced filters") {
                HStack {
                    TextField("Min age", text: $model.minimumAgeText).frame(width: 80)
                    TextField("Max age", text: $model.maximumAgeText).frame(width: 80)
                    TextField("City", text: $model.city).frame(width: 140)
                    TextField("Min face", text: $model.minimumFaceScoreText).frame(width: 90)
                    TextField("Min lifestyle", text: $model.minimumLifestyleScoreText).frame(width: 100)
                    TextField("Min overall", text: $model.minimumOverallScoreText).frame(width: 95)
                    TextField("Min confidence %", text: $model.minimumConfidenceText).frame(width: 115)
                    Toggle("Usable face", isOn: $model.usableFaceRequired)
                    Button("Apply") { model.refresh(resetPage: true) }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 6)
            }
            .font(.caption)
            HStack {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    private var pagination: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left") { model.previousPage() }.disabled(!model.canGoBack)
            Text("Page \(model.page + 1) of \(model.totalPages)").font(.caption.monospacedDigit())
            Button("Next", systemImage: "chevron.right") { model.nextPage() }.disabled(!model.canGoForward)
            Spacer()
            Picker("Rows", selection: $model.pageSize) {
                Text("20").tag(20); Text("50").tag(50); Text("100").tag(100)
            }
            .frame(width: 110)
            .onChange(of: model.pageSize) { _, _ in model.refresh(resetPage: true) }
        }
        .padding(10)
    }

    private func sortLabel(_ sort: ProfileSort) -> String {
        switch sort {
        case .overallScore: "Overall score"
        case .faceScore: "Face score"
        case .lifestyleScore: "Lifestyle signal"
        case .locationScore: "Location score"
        case .confidenceAdjustedScore: "Confidence-adjusted"
        case .newest: "Newest"
        case .recentlyUpdated: "Recently updated"
        case .username: "Username"
        }
    }
}

private struct ProfileGridCard: View {
    let item: DashboardProfile
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let path = item.previewPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        Image(systemName: "person.crop.square").font(.system(size: 42)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 130)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(item.profile.displayName ?? item.profile.usernameNormalized).font(.headline).lineLimit(1)
                Spacer()
                Text(item.profile.status).font(.caption2).padding(.horizontal, 6).padding(.vertical, 3).background(.quaternary, in: Capsule())
            }
            Text(item.profile.usernameNormalized).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                signal(item.profile.age.map(String.init) ?? "Age ?")
                signal(item.profile.mbti ?? "MBTI ?")
                signal(item.profile.cityNormalized ?? "City ?")
            }
            HStack {
                score("Face", item.profile.faceScore)
                score("Life", item.profile.lifestyleScore)
                score("Overall", item.profile.overallScore)
            }
            Text("\(item.mediaCount) retained · \(item.facePhotoCount) face · \(item.momentPhotoCount) Moments")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(11)
        .background(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }

    private func signal(_ text: String) -> some View { Text(text).font(.caption2).lineLimit(1) }
    private func score(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f", $0) } ?? "—").font(.caption.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileDetailView: View {
    @ObservedObject var model: ReviewDashboardViewModel

    var body: some View {
        ScrollView {
            if let item = model.selected {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.profile.displayName ?? item.profile.usernameNormalized).font(.title2.bold())
                    Text(item.profile.usernameNormalized).font(.callout.monospaced()).foregroundStyle(.secondary)
                    HStack {
                        Button("Keep") { model.setStatus(.shortlisted) }.keyboardShortcut("k", modifiers: [])
                        Button("Reject") { model.setStatus(.rejected) }.keyboardShortcut("r", modifiers: [])
                        Button("Contacted") { model.setStatus(.contacted) }.keyboardShortcut("c", modifiers: [])
                        Button("Reset") { model.setStatus(.review) }
                    }
                    GroupBox("Extracted fields") {
                        VStack(alignment: .leading, spacing: 7) {
                            row("Age", item.profile.age.map(String.init) ?? "Unverified")
                            row("Gender", item.profile.gender ?? "Unverified")
                            row("MBTI", item.profile.mbti ?? "Missing")
                            row("Group", item.profile.mbtiGroup ?? "None")
                            row("Location", item.profile.cityNormalized ?? item.profile.provinceNormalized ?? "Unknown")
                            row("Location tier", item.profile.locationTier.map(String.init) ?? "—")
                            row("First seen", item.profile.firstSeenAt.formatted())
                            row("Last seen", item.profile.lastSeenAt.formatted())
                            row("Visits", String(item.profile.visitCount))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Score breakdown") {
                        VStack(alignment: .leading, spacing: 7) {
                            row("Face visual appeal", format(item.profile.faceScore))
                            row("Lifestyle signal", format(item.profile.lifestyleScore))
                            row("Location", item.profile.locationScore.map(String.init) ?? "—")
                            row("Completeness", format(item.profile.profileCompletenessScore))
                            row("Overall", format(item.profile.overallScore))
                            row("Analysis confidence", String(format: "%.0f%%", item.profile.analysisConfidence * 100))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !model.selectedMedia.isEmpty {
                        GroupBox("Retained media") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                                ForEach(model.selectedMedia) { media in
                                    if let image = NSImage(contentsOfFile: media.filePath) {
                                        Image(nsImage: image).resizable().scaledToFill().frame(height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                    if !model.selectedAnalysisRuns.isEmpty {
                        GroupBox("Qwen analysis evidence") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.selectedAnalysisRuns) { run in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(run.analysisType) · \(run.modelName)").font(.caption.bold())
                                        Text("Prompt \(run.promptVersion) · \(run.success ? "complete" : "failed")")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        if let references = run.requestTrace?.images, !references.isEmpty {
                                            ScrollView(.horizontal) {
                                                HStack(alignment: .top, spacing: 8) {
                                                    ForEach(references) { reference in
                                                        AnalysisEvidenceImage(run: run, reference: reference)
                                                    }
                                                }
                                            }
                                            .scrollIndicators(.hidden)
                                        }
                                        if let response = run.responseJSON {
                                            Text(response).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(8)
                                        }
                                    }
                                    Divider()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("Notes") {
                        VStack {
                            TextEditor(text: $model.notesDraft).frame(minHeight: 90)
                            Button("Save notes") { model.saveNotes() }.frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    Button("Delete media, keep profile record", role: .destructive) { model.deleteSelectedMedia() }
                }
                .padding(16)
            } else {
                ContentUnavailableView("Select a profile", systemImage: "person.text.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 500)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
    private func format(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
    private func format(_ value: Double) -> String { String(format: "%.1f", value) }
}

private struct AnalysisEvidenceImage: View {
    let run: AnalysisRunRecord
    let reference: AnalysisImageReference

    private var evidence: [LifestyleEvidence] {
        run.lifestyleEvidence(sourceImageID: reference.sourceImageID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: reference.filePath))
            } label: {
                Group {
                    if let image = NSImage(contentsOfFile: reference.filePath) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.08)
                            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 112, height: 86)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Open \(reference.sourceImageID)")

            Text(reference.sourceImageID).font(.caption2.monospaced()).foregroundStyle(.secondary)
            if evidence.isEmpty {
                Text("Model input").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.category) · \(item.strength)").font(.caption2.bold())
                        Text(item.explanation).font(.caption2).lineLimit(4)
                    }
                }
            }
        }
        .frame(width: 112, alignment: .leading)
    }
}

struct LocalDataSettingsView: View {
    @ObservedObject var model: ReviewDashboardViewModel
    @StateObject private var vlmModel = VLMSettingsViewModel()
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Local data") {
                LabeledContent("Database", value: model.repository?.databasePath ?? "Unavailable")
                Button("Reveal data folder", systemImage: "folder") { model.revealDataFolder() }
                HStack {
                    Button("Export CSV") { model.export(format: .csv) }
                    Button("Export JSON") { model.export(format: .json) }
                }
                Button("Delete all collected data", role: .destructive) { showingDeleteConfirmation = true }
            }
            Section("Privacy boundary") {
                Text("Profiles, media, diagnostics, exports, configuration, and analysis queues remain under your local Application Support folder. Profile identity uses normalized usernames only; media identity uses perceptual hashes only. No face recognition or cross-account identity matching is implemented.")
                    .foregroundStyle(.secondary)
            }
            Section("Collection policy") {
                Toggle("Reject Primary profiles when no usable face is found", isOn: $vlmModel.enforceNoFaceForPrimary)
                Text("Secondary profiles always enforce the no-face rule. This safety requirement cannot be disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save collection settings") { vlmModel.saveCollectionSettings() }
            }
            Section("Optional Qwen over Tailscale") {
                TextField("Ollama URL (for example http://windows-pc:11434)", text: $vlmModel.endpoint)
                TextField("Model", text: $vlmModel.model)
                HStack {
                    Button("Save") { _ = vlmModel.save() }
                    Button("Test Connection") { vlmModel.testConnection() }
                        .disabled(vlmModel.isTesting || vlmModel.endpoint.isEmpty)
                    if vlmModel.isTesting { ProgressView().controlSize(.small) }
                }
                Text(vlmModel.status).font(.caption).foregroundStyle(.secondary)
                Text("The endpoint is called only from this native app. When unavailable, collection continues and versioned JSON analysis jobs remain in the local SQLite queue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("Delete every collected profile and media file?", isPresented: $showingDeleteConfirmation) {
            Button("Delete all collected data", role: .destructive) { model.deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Calibration and application settings are retained.")
        }
    }
}
