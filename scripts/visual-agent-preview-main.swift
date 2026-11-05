import AppKit
import SwiftUI

/// Native DEBUG acceptance launcher for the exact app views, compiled without
/// changing the production @main or any Jimu-owned file. No installation/input.
@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileHandle.standardError.write(Data("Preview didFinishLaunching\n".utf8))
        let model = InspectorViewModel()
        let view = VisualAgentPreviewWorkspace(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Profile Curator — Offline Navigation Preview"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate()
        FileHandle.standardError.write(Data("Preview window visible=\(window.isVisible) number=\(window.windowNumber) bundle=\(Bundle.main.bundleIdentifier ?? "none")\n".utf8))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
enum PreviewLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
