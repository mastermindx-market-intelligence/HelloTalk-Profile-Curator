import SwiftUI

@main
struct ProfileCuratorApp: App {
    @StateObject private var model = InspectorViewModel()

    var body: some Scene {
        WindowGroup("Profile Curator Inspector") {
            ContentView(model: model)
                .frame(minWidth: 1_100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}
