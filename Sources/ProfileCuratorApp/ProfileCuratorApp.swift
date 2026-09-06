import SwiftUI

@main
struct ProfileCuratorApp: App {
    @StateObject private var model = InspectorViewModel()

    var body: some Scene {
        WindowGroup("Profile Curator Inspector") {
            if ProcessInfo.processInfo.arguments.contains("--jimu-offline") {
                JimuOfflineWorkspace()
            } else {
                ContentView(model: model)
                    .dynamicTypeSize(.xLarge)
                    .frame(minWidth: 1_100, minHeight: 720)
#if DEBUG
                    .task {
                        guard ProcessInfo.processInfo.arguments.contains("--acceptance-autostart") else { return }
                        try? await Task.sleep(for: .seconds(1))
                        model.startAutonomousCollection()
                    }
#endif
            }
        }
        .windowResizability(.contentMinSize)

        Window("Jimu Offline Inspector", id: "jimu-offline") {
            JimuOfflineWorkspace()
        }
        .defaultSize(width: 1_280, height: 900)
        .windowResizability(.contentMinSize)
    }
}

private struct JimuOfflineWorkspace: View {
    @StateObject private var model = JimuOfflineInspectorModel()
    var body: some View { JimuOfflineInspectorView(model: model) }
}
