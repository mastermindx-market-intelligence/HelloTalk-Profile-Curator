import ApplicationServices
import CoreGraphics
import Foundation

public struct CuratorPermissionStatus: Equatable, Sendable {
    public let screenRecordingGranted: Bool
    public let accessibilityGranted: Bool

    public init(screenRecordingGranted: Bool, accessibilityGranted: Bool) {
        self.screenRecordingGranted = screenRecordingGranted
        self.accessibilityGranted = accessibilityGranted
    }
}

public enum PermissionInspector {
    public static func currentStatus() -> CuratorPermissionStatus {
        CuratorPermissionStatus(
            screenRecordingGranted: CGPreflightScreenCaptureAccess(),
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @discardableResult
    public static func requestAccessibilityPrompt() -> Bool {
        // String value of kAXTrustedCheckOptionPrompt. Using the stable key avoids
        // Swift 6 treating the imported C global itself as shared mutable state.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
