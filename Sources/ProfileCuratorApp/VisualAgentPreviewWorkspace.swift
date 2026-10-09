import ProfileCuratorCore
import SwiftUI

#if DEBUG
/// Focused native acceptance surface for the existing read-only panel. The
/// debug flag only selects this workspace; it never starts collection or input.
struct VisualAgentPreviewWorkspace: View {
    @ObservedObject var model: InspectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local AI navigation preview").font(.title2)
                Spacer()
                Button("Load Fixture…") { model.chooseFixture() }
            }
            Text("Offline preview · local image analysis · no desktop input")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                FixtureCanvas(image: model.fixtureImage, analysis: model.analysis,
                    showOCRBoxes: false, showFaceBoxes: false, showSafetyPreview: false,
                    action: model.previewAction, gesture: nil, exclusions: model.activePreviewExclusions,
                    calibrationMode: false, calibrationMarks: [], onCalibrationRect: { _ in })
                    .frame(minWidth: 500, maxWidth: .infinity)
                ScrollView {
                    VisualAgentOfflineInspector(model: model)
                        .padding(4)
                }.frame(width: 460)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .padding(20)
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--visual-agent-fixture"),
                  arguments.indices.contains(index + 1) else { return }
            model.loadFixture(at: URL(fileURLWithPath: arguments[index + 1]))
        }
    }
}
#endif
