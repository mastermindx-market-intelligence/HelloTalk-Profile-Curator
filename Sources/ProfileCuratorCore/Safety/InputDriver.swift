import CoreGraphics
import Foundation

public enum InputCommand: Hashable, Sendable {
    case click(NormalizedPoint)
    case verticalScroll(lines: Int)
}

public protocol InputDriving: Sendable {
    func emit(_ command: InputCommand, in windowFrame: CGRect) async throws
}

public actor CGEventInputDriver: InputDriving {
    public init() {}

    public func emit(_ command: InputCommand, in windowFrame: CGRect) async throws {
        switch command {
        case .click(let point):
            let global = CGPoint(
                x: windowFrame.minX + point.x * windowFrame.width,
                y: windowFrame.minY + point.y * windowFrame.height
            )
            guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: global, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: global, mouseButton: .left) else {
                throw InputDriverError.eventCreationFailed
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        case .verticalScroll(let lines):
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(lines), wheel2: 0, wheel3: 0) else {
                throw InputDriverError.eventCreationFailed
            }
            event.post(tap: .cghidEventTap)
        }
    }
}

public actor SafeInputExecutor {
    private let driver: any InputDriving
    private var awaitingPostcondition = false

    public init(driver: any InputDriving) { self.driver = driver }

    public func resolvePostcondition(passed: Bool) {
        awaitingPostcondition = false
    }

    public func executeClick(
        action: PlannedAction,
        windowFrame: CGRect,
        exclusions: [ExclusionZone],
        emergencyStopActive: Bool,
        sessionPauseReason: String?,
        liveInputEnabled: Bool
    ) async throws -> ActionSafetyDecision {
        if awaitingPostcondition {
            return ActionSafetyDecision(isAllowed: false, rejection: .sessionPaused("Previous action postcondition is unresolved"))
        }
        let decision = ActionSafetyValidator().validate(
            action,
            exclusionZones: exclusions,
            emergencyStopActive: emergencyStopActive,
            sessionPauseReason: sessionPauseReason,
            liveInputEnabled: liveInputEnabled
        )
        guard decision.isAllowed else { return decision }
        try await driver.emit(.click(action.point), in: windowFrame)
        awaitingPostcondition = true
        return decision
    }
}

public enum InputDriverError: Error, LocalizedError, Sendable {
    case eventCreationFailed
    public var errorDescription: String? { "macOS could not create the requested input event." }
}
