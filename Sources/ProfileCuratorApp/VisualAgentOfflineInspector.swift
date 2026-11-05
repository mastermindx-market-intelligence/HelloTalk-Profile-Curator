import AppKit
import CryptoKit
import ProfileCuratorCore
import SwiftUI

/// Local-only, reviewable navigation inspector. It NEVER contacts a model or drives input.
/// Provider inference belongs to an admitted interactive Fabric worker, not this app.
@MainActor
struct VisualAgentOfflineInspector: View {
    @ObservedObject var model: InspectorViewModel

    @State private var inspectedFrame: VisualAgentFrame?
    @State private var pastedProposalJSON = ""
    @State private var verdict = "Inspect a frame to begin."
    @State private var verdictIsRefusal = false

    var body: some View {
        GroupBox("AI navigation preview — offline") {
            VStack(alignment: .leading, spacing: 9) {
                Label("No model calls or desktop input", systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Use an existing local screenshot or captured frame. Only synthetic, authorized fixtures may be sent to an admitted Fabric worker outside this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Inspect current frame", systemImage: "eye") {
                    inspectCurrentFrame()
                }
                .disabled(model.fixtureImage == nil || model.analysis == nil || model.observationSnapshot == nil)

                if let frame = inspectedFrame {
                    LabeledContent("Screen", value: frame.screenKind)
                    LabeledContent("Frame SHA-256", value: String(frame.id.prefix(16)) + "…")
                    Text(frame.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if frame.elements.isEmpty {
                        Text("No safely grounded navigation controls were recognized.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Grounded navigation candidates")
                            .font(.caption.weight(.semibold))
                        ForEach(frame.elements, id: \.id) { element in
                            Text("\(element.id) · \(element.label) · \(element.role.rawValue)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    DisclosureGroup("Planner prompt (text only)") {
                        Text(VisualAgentPrompt.system + "\n" + VisualAgentPrompt.user(goal: .locateNavigationTab, frame: frame))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }

                    Text("Paste model proposal JSON for deterministic review")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $pastedProposalJSON)
                        .font(.caption.monospaced())
                        .frame(height: 116)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                        .accessibilityLabel("Offline model proposal JSON")

                    Button("Validate proposal — preview only", systemImage: "checkmark.shield") {
                        validatePastedProposal()
                    }
                    .disabled(pastedProposalJSON.isEmpty)
                }
                Text(verdict)
                    .font(.caption)
                    .foregroundStyle(verdictIsRefusal ? .red : .secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buildCurrentFrame() throws -> VisualAgentFrame {
        guard let image = model.fixtureImage,
              let analysis = model.analysis,
              let observation = model.observationSnapshot else {
            throw PreviewError.noSource
        }
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw PreviewError.noPixelDigest
        }
        // Hash the real image bytes, not OCR text. No image bytes are transmitted.
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return try VisualAgentFrameAdapter().build(
            screenshotDigest: digest,
            observation: observation,
            analysis: analysis,
            calibratedExclusions: model.activePreviewExclusions
        )
    }

    private func inspectCurrentFrame() {
        do {
            let current = try buildCurrentFrame()
            if inspectedFrame?.id != current.id { pastedProposalJSON = "" }
            inspectedFrame = current
            verdictIsRefusal = false
            verdict = "Local snapshot ready; no navigation action has run."
        } catch {
            inspectedFrame = nil
            pastedProposalJSON = ""
            verdictIsRefusal = true
            verdict = "Inspection unavailable: \(error)"
        }
    }

    private func validatePastedProposal() {
        guard let inspectedFrame else { return }
        do {
            let current = try buildCurrentFrame()
            guard current.id == inspectedFrame.id,
                  current.stableObservationID == inspectedFrame.stableObservationID,
                  current.screenKind == inspectedFrame.screenKind,
                  sameCandidatesAndExclusions(current, inspectedFrame) else {
                verdict = "REJECTED: The visible screen, controls, or exclusion areas changed. Inspect again."
                verdictIsRefusal = true
                self.inspectedFrame = nil
                return
            }
            let proposal = try VisualAgentProposal.decodeJSON(Data(pastedProposalJSON.utf8))
            switch VisualAgentSafetyGate().review(proposal, on: current) {
            case .rejected(let reason):
                verdict = "REJECTED: \(reason). No action taken."
                verdictIsRefusal = true
            case .approved(let preview):
                verdict = previewDescription(preview) + " — PREVIEW ONLY. No action taken."
                verdictIsRefusal = false
            }
        } catch {
            verdict = "REJECTED: \(error). No action taken."
            verdictIsRefusal = true
        }
    }

    /// A same-image source can be reclassified after analysis or calibration changes.
    /// Validate all candidate and exclusion geometry before reviewing pasted model output.
    private func sameCandidatesAndExclusions(_ a: VisualAgentFrame, _ b: VisualAgentFrame) -> Bool {
        guard a.elements.count == b.elements.count, a.exclusions.count == b.exclusions.count else { return false }
        for (lhs, rhs) in zip(a.elements, b.elements) {
            guard lhs.id == rhs.id, lhs.label == rhs.label, lhs.role == rhs.role,
                  lhs.actionKind == rhs.actionKind, lhs.bounds == rhs.bounds else { return false }
        }
        for (lhs, rhs) in zip(a.exclusions, b.exclusions) {
            guard lhs.label == rhs.label, lhs.bounds == rhs.bounds else { return false }
        }
        return true
    }

    private func previewDescription(_ preview: VisualAgentPreview) -> String {
        switch preview {
        case .tap(let action, let expectation):
            return "APPROVED PREVIEW: \(action.kind.rawValue) at \(action.point.x), \(action.point.y); verify \(expectation.kind.rawValue) \(expectation.value ?? "")"
        case .scroll(let lines, let point):
            return "APPROVED PREVIEW: scroll \(lines) at \(point.x), \(point.y)"
        case .wait:
            return "APPROVED PREVIEW: wait"
        case .pause:
            return "APPROVED PREVIEW: pause"
        }
    }

    private enum PreviewError: Error {
        case noSource
        case noPixelDigest
    }
}
