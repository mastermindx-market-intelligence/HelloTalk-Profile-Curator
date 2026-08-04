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
                TextField("Search name, bio, hobby, school, or job", text: $model.search)
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
                    TextField("City or country", text: $model.city).frame(width: 140)
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
        case .profileSignalsScore: "Profile signals"
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
                    ZStack {
                        Color.black.opacity(0.88)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                } else {
                    ZStack {
                        Color.secondary.opacity(0.08)
                        Image(systemName: "person.crop.square").font(.system(size: 42)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 5, contentMode: .fit)
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
                signal(item.profile.cityNormalized ?? item.profile.countryNormalized ?? "Location ?")
            }
            HStack {
                score("Face", item.profile.faceScore)
                score("Life", item.profile.lifestyleScore)
                score("Profile", item.profile.profileSignalsScore)
                score("Overall", item.profile.overallScore)
            }
            if !item.profile.hobbies.isEmpty {
                Text(item.profile.hobbies.prefix(3).joined(separator: " · "))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(value.map(scoreColor) ?? .secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileDetailView: View {
    @ObservedObject var model: ReviewDashboardViewModel
    @State private var enlargedImage: EnlargedImage?

    var body: some View {
        ScrollView {
            if let item = model.selected {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.profile.displayName ?? item.profile.usernameNormalized)
                            .font(.title.bold())
                        HStack(spacing: 8) {
                            Text(item.profile.usernameNormalized)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                            Text(humanized(item.profile.status))
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    HStack {
                        Button("Keep") { model.setStatus(.shortlisted) }.keyboardShortcut("k", modifiers: [])
                        Button("Reject") { model.setStatus(.rejected) }.keyboardShortcut("r", modifiers: [])
                        Button("Contacted") { model.setStatus(.contacted) }.keyboardShortcut("c", modifiers: [])
                        Button("Reset") { model.setStatus(.review) }
                    }
                    DetailSection(title: "Profile facts", systemImage: "person.text.rectangle") {
                        VStack(alignment: .leading, spacing: 7) {
                            DetailFieldRow(label: "Age", value: item.profile.age.map(String.init) ?? "Unverified")
                            DetailFieldRow(label: "Gender", value: humanized(item.profile.gender ?? "Unverified"))
                            DetailFieldRow(label: "MBTI", value: item.profile.mbti ?? "Missing")
                            DetailFieldRow(label: "Group", value: humanized(item.profile.mbtiGroup ?? "None"))
                            DetailFieldRow(
                                label: "Location",
                                value: item.profile.cityNormalized
                                    ?? item.profile.provinceNormalized
                                    ?? item.profile.countryNormalized
                                    ?? "Unknown"
                            )
                            DetailFieldRow(label: "Location tier", value: item.profile.locationTier.map(String.init) ?? "—")
                            DetailFieldRow(label: "First seen", value: item.profile.firstSeenAt.formatted(date: .abbreviated, time: .shortened))
                            DetailFieldRow(label: "Last seen", value: item.profile.lastSeenAt.formatted(date: .abbreviated, time: .shortened))
                            DetailFieldRow(label: "Visits", value: String(item.profile.visitCount))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DetailSection(title: "Score breakdown", systemImage: "chart.bar.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            ScoreMetricRow(label: "Face presentation", value: item.profile.faceScore)
                            ScoreMetricRow(label: "Lifestyle + profile signal", value: item.profile.lifestyleScore)
                            ScoreMetricRow(label: "Profile signals", value: item.profile.profileSignalsScore)
                            ScoreMetricRow(label: "Location", value: item.profile.locationScore.map(Double.init))
                            ScoreMetricRow(label: "Profile completeness", value: item.profile.profileCompletenessScore)
                            ScoreMetricRow(label: "Overall", value: item.profile.overallScore, emphasized: true)
                            ScoreMetricRow(label: "Analysis confidence", value: item.profile.analysisConfidence * 100)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if item.profile.bio != nil
                        || !item.profile.hobbies.isEmpty
                        || item.profile.education != nil
                        || item.profile.occupation != nil {
                        DetailSection(title: "Profile signals", systemImage: "person.crop.circle.badge.checkmark") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let bio = item.profile.bio {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Bio (OCR)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        Text(bio)
                                            .font(.callout)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                if !item.profile.hobbies.isEmpty {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text("Hobbies")
                                                .font(.caption.bold())
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            scoreValue(item.profile.hobbyScore)
                                        }
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), alignment: .leading)], alignment: .leading, spacing: 6) {
                                            ForEach(item.profile.hobbies, id: \.self) { hobby in
                                                Text(hobby)
                                                    .font(.caption.weight(.medium))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(Color.accentColor.opacity(0.11), in: Capsule())
                                            }
                                        }
                                    }
                                }
                                if let education = item.profile.education {
                                    DetailFieldRow(label: "Education", value: education)
                                    ScoreMetricRow(label: "Education signal", value: item.profile.educationScore)
                                }
                                if let occupation = item.profile.occupation {
                                    DetailFieldRow(label: "Occupation", value: occupation)
                                    ScoreMetricRow(label: "Occupation signal", value: item.profile.occupationScore)
                                }
                                Text("Lifestyle uses 70% visible Qwen evidence and 30% explicit profile signals when both are available. Bio is displayed only and never scored.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if !model.selectedMedia.isEmpty {
                        DetailSection(title: "Retained media", systemImage: "photo.on.rectangle.angled") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                                ForEach(model.selectedMedia) { media in
                                    if let image = NSImage(contentsOfFile: media.filePath) {
                                        Button {
                                            enlargedImage = EnlargedImage(
                                                path: media.filePath,
                                                title: mediaTitle(media),
                                                detail: "Saved \(media.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                            )
                                        } label: {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(height: 100)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .overlay(alignment: .bottomTrailing) {
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .font(.caption.bold())
                                                        .padding(6)
                                                        .foregroundStyle(.white)
                                                        .background(.black.opacity(0.62), in: Circle())
                                                        .padding(6)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open larger view")
                                    }
                                }
                            }
                        }
                    }
                    if !model.selectedAnalysisRuns.isEmpty {
                        DetailSection(title: "Qwen analysis", systemImage: "sparkles.rectangle.stack") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Scores and evidence are normalized for display.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if model.isReanalyzing { ProgressView().controlSize(.small) }
                                    Button("Re-run", systemImage: "arrow.triangle.2.circlepath") {
                                        model.reanalyzeSelected()
                                    }
                                    .disabled(model.isReanalyzing)
                                }
                                ForEach(model.selectedAnalysisRuns) { run in
                                    QwenAnalysisCard(run: run) { reference in
                                        enlargedImage = EnlargedImage(
                                            path: reference.filePath,
                                            title: reference.sourceImageID,
                                            detail: "Qwen analysis input"
                                        )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    DetailSection(title: "Notes", systemImage: "note.text") {
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
        .sheet(item: $enlargedImage) { item in
            EnlargedImageView(item: item)
        }
    }

    private func mediaTitle(_ media: MediaRecord) -> String {
        switch media.typedKind {
        case .profileTop: "Profile overview"
        case .pfp: "Profile photo"
        case .moment: "Moment"
        case .faceCrop: "Face crop"
        case .diagnostic: "Diagnostic capture"
        }
    }

    private func scoreValue(_ value: Double?) -> some View {
        Text(value.map { String(format: "%.0f", $0) } ?? "—")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(value.map(scoreColor) ?? .secondary)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor).opacity(0.7)))
    }
}

private struct DetailFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.callout.weight(.medium))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct ScoreMetricRow: View {
    let label: String
    let value: Double?
    var emphasized = false
    var higherIsBetter = true

    private var tint: Color {
        guard let value else { return .secondary }
        return scoreColor(higherIsBetter ? value : 100 - value)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(emphasized ? .callout.bold() : .callout)
                Spacer()
                Text(value.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.callout.bold().monospacedDigit())
                    .foregroundStyle(tint)
            }
            ProgressView(value: min(100, max(0, value ?? 0)), total: 100)
                .tint(tint)
                .controlSize(.small)
        }
    }
}

private struct QwenAnalysisCard: View {
    let run: AnalysisRunRecord
    let openImage: (AnalysisImageReference) -> Void

    private var references: [AnalysisImageReference] { run.requestTrace?.images ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysisTitle).font(.headline)
                    Text("\(run.modelName) · \(run.promptVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(run.success ? "Complete" : "Failed")
                    .font(.caption.bold())
                    .foregroundStyle(run.success ? Color.green : Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((run.success ? Color.green : Color.red).opacity(0.13), in: Capsule())
            }

            analysisSummary

            if !references.isEmpty {
                DisclosureGroup("Model inputs (\(references.count))") {
                    AnalysisInputStrip(references: references, openImage: openImage)
                        .padding(.top, 8)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            if let response = run.responseJSON {
                DisclosureGroup("Raw Qwen JSON") {
                    Text(response)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 6)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var analysisSummary: some View {
        if let result = run.faceVerificationResult {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    BooleanBadge(label: "Photographic face", value: result.isPhotographicHumanFace)
                    BooleanBadge(label: "Clear enough", value: result.isFaceClearEnoughToScore)
                }
                HStack(spacing: 6) {
                    BooleanBadge(label: "Not illustration", value: !result.isIllustrationOrAnime)
                    BooleanBadge(label: "Not heavily filtered", value: !result.isHeavilyFiltered)
                }
                ScoreMetricRow(label: "Confidence", value: result.confidence * 100)
            }
        } else if let result = run.visualAppealResult {
            VStack(alignment: .leading, spacing: 10) {
                ScoreMetricRow(
                    label: "Final face score",
                    value: max(0, result.visualAppealScore - result.photoQualityPenalty),
                    emphasized: true
                )
                ScoreMetricRow(label: "Presentation estimate", value: result.visualAppealScore)
                ScoreMetricRow(label: "Photo-quality penalty", value: result.photoQualityPenalty, higherIsBetter: false)
                ScoreMetricRow(label: "Confidence", value: result.confidence * 100)
                if !result.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Model notes").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                            Label(note, systemImage: "circle.fill")
                                .font(.caption)
                                .labelStyle(TinyBulletLabelStyle())
                        }
                    }
                }
            }
        } else if let result = run.lifestyleSignalResult {
            VStack(alignment: .leading, spacing: 10) {
                ScoreMetricRow(label: "Lifestyle signal", value: result.lifestyleAffluenceSignal, emphasized: true)
                ScoreMetricRow(label: "Confidence", value: result.confidence * 100)
                Text("Evidence")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                if result.evidence.isEmpty {
                    Text("No specific visible evidence returned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, evidence in
                        QwenEvidenceRow(
                            evidence: evidence,
                            reference: references.first { $0.sourceImageID == evidence.sourceImageID },
                            openImage: openImage
                        )
                    }
                }
                Text("Actual wealth is intentionally not inferred.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(run.error ?? "This response could not be normalized.")
                .font(.caption)
                .foregroundStyle(run.success ? Color.secondary : Color.red)
        }
    }

    private var analysisTitle: String {
        switch AnalysisType(rawValue: run.analysisType) {
        case .faceVerification: "Face verification"
        case .visualAppeal: "Face presentation"
        case .lifestyle: "Lifestyle evidence"
        case nil: humanized(run.analysisType)
        }
    }
}

private struct QwenEvidenceRow: View {
    let evidence: LifestyleEvidence
    let reference: AnalysisImageReference?
    let openImage: (AnalysisImageReference) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let reference {
                AnalysisThumbnail(reference: reference, width: 86, height: 72) { openImage(reference) }
            } else {
                ZStack {
                    Color.secondary.opacity(0.08)
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                }
                .frame(width: 86, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(humanized(evidence.category))
                        .font(.callout.bold())
                    Text(humanized(evidence.strength))
                        .font(.caption2.bold())
                        .foregroundStyle(strengthColor(evidence.strength))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(strengthColor(evidence.strength).opacity(0.14), in: Capsule())
                    Spacer()
                    Text("Qwen cited \(evidence.sourceImageID)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Text(evidence.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AnalysisInputStrip: View {
    let references: [AnalysisImageReference]
    let openImage: (AnalysisImageReference) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(references) { reference in
                    VStack(alignment: .leading, spacing: 3) {
                        AnalysisThumbnail(reference: reference, width: 84, height: 64) { openImage(reference) }
                        Text(reference.sourceImageID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct AnalysisThumbnail: View {
    let reference: AnalysisImageReference
    let width: CGFloat
    let height: CGFloat
    let openImage: () -> Void

    var body: some View {
        Button(action: openImage) {
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
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Open \(reference.sourceImageID) larger")
    }
}

private struct BooleanBadge: View {
    let label: String
    let value: Bool

    var body: some View {
        Label(label, systemImage: value ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(value ? Color.green : Color.red)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((value ? Color.green : Color.red).opacity(0.12), in: Capsule())
    }
}

private struct TinyBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 4)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}

private func humanized(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}

private func scoreColor(_ value: Double) -> Color {
    switch value {
    case 75...: .green
    case 55..<75: .yellow
    default: .red
    }
}

private func strengthColor(_ strength: String) -> Color {
    switch strength.lowercased() {
    case "high", "strong": .green
    case "medium", "moderate": .yellow
    default: .red
    }
}

private struct EnlargedImage: Identifiable {
    let path: String
    let title: String
    let detail: String

    var id: String { path }
}

private struct EnlargedImageView: View {
    @Environment(\.dismiss) private var dismiss
    let item: EnlargedImage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open in Preview", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
                }
                Button("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            ZStack {
                Color.black.opacity(0.94)
                if let image = NSImage(contentsOfFile: item.path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                } else {
                    ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 980, minHeight: 580, idealHeight: 760)
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
