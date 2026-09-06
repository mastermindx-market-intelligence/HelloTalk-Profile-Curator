import SwiftUI
import ProfileCuratorCore

/// This view replaces the inspector and renders only crop images, neutral controls and session status.
struct JimuPhotoCalibrationView: View {
    @ObservedObject var model: JimuOfflineInspectorModel
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Photo-only calibration").font(.title2.bold())
                    Text(model.photoProgress).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label("NO ACTIONS", systemImage: "lock.fill").font(.caption.bold()).foregroundStyle(.teal)
                Button("Stop / Exit") { model.stopPhotoCalibration() }.keyboardShortcut(.escape, modifiers: [])
            }
            Divider()
            if let left = model.photoLeft {
                HStack(alignment: .top, spacing: 24) {
                    card(left, title: model.photoRight == nil ? "Photo" : "Photo A")
                    if let right = model.photoRight { card(right, title: "Photo B") }
                }.frame(maxHeight: .infinity)
                choices.disabled(model.photoSubmissionID != nil)
                HStack(spacing: 18) {
                    if model.photoSubmissionID != nil {
                        Label("Judgment saved", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                        Button("Revise judgment") { model.revisePhotoLabel() }
                    }
                    Spacer()
                    Button(model.photoSubmissionID == nil ? "Skip without labeling" : "Next") {
                        model.nextPhotoCalibration()
                    }.keyboardShortcut(.space, modifiers: [])
                }
            } else {
                Spacer()
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.teal)
                Text(model.errorCode == nil ? "Session complete" : "Photo unavailable").font(.title2.bold())
                Text("No judgment is recorded for skipped or unavailable evidence.").foregroundStyle(.secondary)
                Button("Continue to next prepared photo") { model.nextPhotoCalibration() }
                Spacer()
            }
            if let error = model.errorCode {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            Divider()
            VStack(spacing: 5) {
                Text("Your visual preference only. No scores, biography, location or action budgets are shown.")
                Text("Regions are human-confirmed. Earlier profile exposure is recorded, not erased.")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(minWidth: 1050, minHeight: 720)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private func card(_ view: JimuPhotoPresentation, title: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            Image(decorative: view.image, scale: 1).resizable().scaledToFit()
                .accessibilityLabel(title).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(18).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var choices: some View {
        HStack(spacing: 18) {
            if model.photoRight == nil {
                Button("Approve") { model.recordPhotoLabel(.approve) }
                    .keyboardShortcut("1", modifiers: [])
                Button("Reject") { model.recordPhotoLabel(.reject) }
                    .keyboardShortcut("2", modifiers: [])
            } else {
                Button("Prefer A") { model.recordPhotoLabel(.left) }
                    .keyboardShortcut("1", modifiers: [])
                Button("Prefer B") { model.recordPhotoLabel(.right) }
                    .keyboardShortcut("2", modifiers: [])
                Button("Tie") { model.recordPhotoLabel(.tie) }
                    .keyboardShortcut("3", modifiers: [])
                Button("Neither") { model.recordPhotoLabel(.neither) }
                    .keyboardShortcut("4", modifiers: [])
            }
        }.buttonStyle(.borderedProminent).controlSize(.large).tint(.teal)
    }
}
