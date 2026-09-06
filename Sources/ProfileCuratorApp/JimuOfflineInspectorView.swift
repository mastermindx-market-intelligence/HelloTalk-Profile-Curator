import SwiftUI
import UniformTypeIdentifiers
import ProfileCuratorCore

/// Native consumer of the existing repository. No input driver or inference client is referenced here.
struct JimuOfflineInspectorView: View {
    @ObservedObject var model: JimuOfflineInspectorModel
    @State private var importing = false
    @State private var importingPolicy = false
    @State private var deleting = false
    @State private var selectedField = ""
    @State private var editState = "PRESENT"
    @State private var editValue = "\"\""
    @State private var editReason = ""
    @State private var actionContext = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                library.frame(minWidth: 240, idealWidth: 260, maxWidth: 310)
                if let snapshot = model.snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            identity(snapshot)
                            evidence(snapshot)
                            correction(snapshot)
                            feedbackControls(snapshot)
                            history(snapshot)
                        }.padding(22)
                    }.frame(minWidth: 670, maxWidth: .infinity)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 42)).foregroundStyle(.teal)
                        Text("Inspect evidence, not an opaque score").font(.title2.bold())
                        Text("Import a synthetic or explicitly admitted observation.\nOriginals stay immutable. Corrections and labels keep their history.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Import observation…") { importing = true }.buttonStyle(.borderedProminent).tint(.teal)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Image(systemName: model.errorCode == nil ? "checkmark.shield" : "exclamationmark.triangle")
                Text(model.errorCode ?? model.notice).font(.caption).textSelection(.enabled)
                Spacer()
                Text("LOCAL • NO NETWORK • NO ACTIONS").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }.foregroundStyle(model.errorCode == nil ? Color.secondary : Color.red).padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.importFile(url) }
        }
        .fileImporter(isPresented: $importingPolicy, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.loadPolicyFile(url) }
        }
        .alert("Delete this observation and its history?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { model.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes its original observation, corrections and feedback involving it. This cannot be undone.")
        }
        .onChange(of: model.snapshot?.id) { _, _ in resetEditor() }
        .onChange(of: selectedField) { _, value in
            if let field = model.snapshot?.effectiveFields.first(where: { $0.fieldID == value }) { populateEditor(field) }
        }
        .frame(minWidth: 1_050, minHeight: 720)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text("Jimu / Evidence Studio").font(.title2.bold())
                Text("Offline inspector · Original evidence → correction history → manual feedback").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("OFFLINE", systemImage: "lock.fill").font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 7)
                .background(Color.teal.opacity(0.12), in: Capsule()).foregroundStyle(.teal)
            Button("Local policy…") { importingPolicy = true }
            Button("Import…") { importing = true }.buttonStyle(.borderedProminent).tint(.teal)
        }.padding(18)
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OBSERVATIONS").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload from the existing database")
            }.padding(.horizontal, 16).padding(.top, 18)
            List(selection: Binding(get: { model.snapshot?.id }, set: { model.select($0) })) {
                ForEach(model.observations) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.id).font(.callout.weight(.medium)).lineLimit(2)
                        Text(row.platform.uppercased()).font(.caption2.monospaced()).foregroundStyle(.teal)
                        Text(row.observedAt).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 8).tag(row.id)
                }
            }.listStyle(.sidebar)
            HStack {
                Button("Previous") { model.page(-1) }.disabled(model.offset == 0)
                Spacer()
                Text("\(model.offset / 100 + 1)").font(.caption)
                Spacer()
                Button("Next") { model.page(1) }.disabled(model.observations.count < 100)
            }.padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 6) {
                Text("Current local policy").font(.caption.bold())
                Text(model.policy?.policyID ?? "Not configured").font(.caption).textSelection(.enabled)
                Text("No policy grants live permission. Native capability and overall candidate eligibility remain unverified.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3))
        }
    }
    private func identity(_ snapshot: JimuInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Observation evidence").font(.title3.bold())
                Spacer()
                Button("Delete…", role: .destructive) { deleting = true }
            }
            Text(snapshot.id).font(.callout.monospaced()).textSelection(.enabled)
            HStack(spacing: 16) {
                status("Age check", snapshot.report.ageEligibility)
                status("Candidate", "NOT EVALUATED")
                status("Actions", "DISABLED")
            }
            Text("Evidence captured \(snapshot.report.observedAt) · Imported \(snapshot.observation.importedAt.formatted())")
                .font(.caption).foregroundStyle(.secondary)
            Text("Raw SHA-256: \(snapshot.observation.inputSHA256)").font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            if !snapshot.report.reasonCodes.isEmpty {
                Text(snapshot.report.reasonCodes.joined(separator: " · ")).font(.caption).foregroundStyle(.orange)
            }
            Label("Text evidence only. Source-frame bytes are not imported or authenticated in this slice.", systemImage: "photo.badge.exclamationmark")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private func status(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.replacingOccurrences(of: "_", with: " ")).font(.caption.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func evidence(_ snapshot: JimuInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observed fields").font(.headline)
            ForEach(snapshot.effectiveFields, id: \.fieldID) { field in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(field.name).font(.callout.bold())
                        Spacer()
                        Text(field.state).font(.caption2.monospaced()).foregroundStyle(field.state == "PRESENT" ? .teal : .secondary)
                        Button("Correct") { populateEditor(field) }
                    }
                    Text(field.value.inspectorText).font(.body).textSelection(.enabled)
                    if let original = snapshot.report.fields.first(where: { $0.fieldID == field.fieldID }) {
                        if original != field {
                            Text("Original: \(original.value.inspectorText)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text("\(field.sourceKind) · \(field.extractorVersion) · sources: \(original.sourceObservationIDs.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        if let raw = original.rawText {
                            Text("Original source text: \(raw)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private func correction(_ snapshot: JimuInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Append a correction").font(.headline)
            Text("A manual correction does not replace platform evidence or establish adult eligibility.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Field", selection: $selectedField) {
                    Text("Select field").tag("")
                    ForEach(snapshot.effectiveFields, id: \.fieldID) { Text($0.name).tag($0.fieldID) }
                }
                Picker("State", selection: $editState) {
                    ForEach(["PRESENT", "ABSENT", "NOT_OBSERVED", "UNREADABLE", "CONFLICT"], id: \.self) { Text($0).tag($0) }
                }
            }
            TextField(correctionIsText ? "Corrected text" : "JSON value, for example 3 or true", text: $editValue).textFieldStyle(.roundedBorder).disabled(editState != "PRESENT")
            TextField("Why are you correcting this?", text: $editReason).textFieldStyle(.roundedBorder)
            Button("Append correction") {
                model.correct(fieldID: selectedField, state: editState, valueJSON: editValue, reason: editReason, valueIsText: correctionIsText)
                if model.errorCode == nil { editReason = "" }
            }.disabled(selectedField.isEmpty || editReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private func feedbackControls(_ snapshot: JimuInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual feedback / separate learning targets").font(.headline)
            Text("These labels describe the available text evidence only. No machine scores are shown; no action is submitted.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Approve profile evidence") { model.label(.approve, scope: .fullProfile) }
                Button("Reject profile evidence") { model.label(.reject, scope: .fullProfile) }
                Spacer()
                Label("Visual-only: image evidence unavailable", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }.disabled(!snapshot.preferenceLabelsAllowed)
            HStack {
                Picker("Compare", selection: Binding(get: { model.comparison?.id ?? "" }, set: { model.compare(with: $0.isEmpty ? nil : $0) })) {
                    Text("No comparison").tag("")
                    ForEach(model.observations.filter { $0.id != snapshot.id }) { Text($0.id).tag($0.id) }
                }
            }
            if let comparison = model.comparison {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Comparison: \(comparison.id)").font(.caption.bold())
                    ForEach(comparison.effectiveFields, id: \.fieldID) { field in
                        Text("\(field.name) [\(field.state)]: \(field.value.inspectorText)").font(.caption).textSelection(.enabled)
                    }
                    HStack {
                        Button("Prefer current") { model.label(.left, scope: .fullProfile, paired: true) }
                        Button("Prefer comparison") { model.label(.right, scope: .fullProfile, paired: true) }
                        Button("Tie") { model.label(.tie, scope: .fullProfile, paired: true) }
                        Button("Neither") { model.label(.neither, scope: .fullProfile, paired: true) }
                    }.disabled(!snapshot.preferenceLabelsAllowed || !comparison.preferenceLabelsAllowed)
                }.padding(10).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Text("Action-context label — recommendation only").font(.caption.bold())
            TextField("Describe attention, quota or other context for this judgment", text: $actionContext).textFieldStyle(.roundedBorder)
            HStack {
                ForEach([JimuFeedbackChoice.inspect, .hold, .pass, .rightSwipe, .note, .instant], id: \.rawValue) { choice in
                    Button(choice.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) {
                        model.label(choice, scope: .scarceAction, context: actionContext)
                    }
                }
            }.disabled(!snapshot.preferenceLabelsAllowed || actionContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !snapshot.preferenceLabelsAllowed {
                Text("Preference labeling is held: configure an eligible explicit-age policy and resolve any age correction through new platform evidence.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private func history(_ snapshot: JimuInspectorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Immutable history").font(.headline)
            Text("Imported under \(snapshot.observation.importReport.policyID ?? "no policy") · Current revision \(snapshot.revision.prefix(12))")
                .font(.caption).foregroundStyle(.secondary)
            if snapshot.corrections.isEmpty && model.feedback.isEmpty { Text("No corrections or labels yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(snapshot.corrections) { correction in
                VStack(alignment: .leading, spacing: 4) {
                    Text("CORRECTION · \(correction.fieldID) → \(correction.value.inspectorText)").font(.caption.bold())
                    Text(correction.reason).font(.caption)
                    Text("\(correction.createdAt.formatted()) · \(correction.id)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            ForEach(model.feedback) { label in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(label.scope.rawValue.uppercased()) · \(label.choice.rawValue)").font(.caption.bold())
                    Text("Text-evidence basis \(label.basis.revision.prefix(12)) · \(label.createdAt.formatted())")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let context = label.actionContext { Text(context).font(.caption) }
                    if label.scope == .fullProfile && label.comparison == nil && label.basis.observationID == snapshot.id &&
                        !model.feedback.contains(where: { $0.supersedesID == label.id }) {
                        Button("Append opposite judgment") {
                            model.label(label.choice == .approve ? .reject : .approve, scope: .fullProfile, supersedesID: label.id)
                        }.font(.caption).disabled(!snapshot.preferenceLabelsAllowed)
                    }
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private var correctionIsText: Bool {
        guard let field = model.snapshot?.report.fields.first(where: { $0.fieldID == selectedField }) else { return false }
        if case .string = field.value { return true }
        return false
    }
    private func populateEditor(_ field: JimuReplayField) {
        selectedField = field.fieldID; editState = field.state; editReason = ""
        if case .string(let text) = field.value { editValue = text }
        else { editValue = field.value.inspectorJSON }
    }
    private func resetEditor() {
        selectedField = ""; editState = "PRESENT"; editValue = "\"\""; editReason = ""
    }
}
