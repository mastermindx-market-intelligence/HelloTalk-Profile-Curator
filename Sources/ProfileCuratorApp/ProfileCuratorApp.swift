import SwiftUI

@main
struct ProfileCuratorApp: App {
    @StateObject private var model = InspectorViewModel()

    var body: some Scene {
        WindowGroup("Profile Curator Inspector") {
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
        .windowResizability(.contentMinSize)
    }
}
