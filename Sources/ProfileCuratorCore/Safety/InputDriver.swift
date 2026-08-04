import CoreGraphics
import Foundation

public enum InputCommand: Hashable, Sendable {
    case click(NormalizedPoint)
    case drag(start: NormalizedPoint, end: NormalizedPoint)
    case verticalScroll(lines: Int, at: NormalizedPoint)
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
        case .drag(let start, let end):
            let globalStart = globalPoint(start, in: windowFrame)
            let globalEnd = globalPoint(end, in: windowFrame)
            guard let moveToStart = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: globalStart,
                mouseButton: .left
            ) else {
                throw InputDriverError.eventCreationFailed
            }
            // Teleporting the pointer and pressing in the same HID cycle is
            // intermittently interpreted by iPhone Mirroring as a tap. Settle at
            // the calibrated origin first, then hold briefly before moving.
            moveToStart.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(45))
            guard let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: globalStart,
                mouseButton: .left
            ) else {
                throw InputDriverError.eventCreationFailed
            }
            down.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(55))
            for step in 1...18 {
                let progress = CGFloat(step) / 18
                let point = CGPoint(
                    x: globalStart.x + (globalEnd.x - globalStart.x) * progress,
                    y: globalStart.y + (globalEnd.y - globalStart.y) * progress
                )
                guard let moved = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseDragged,
                    mouseCursorPosition: point,
                    mouseButton: .left
                ) else {
                    throw InputDriverError.eventCreationFailed
                }
                moved.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(10))
            }
            guard let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: globalEnd,
                mouseButton: .left
            ) else {
                throw InputDriverError.eventCreationFailed
            }
            up.post(tap: .cghidEventTap)
        case .verticalScroll(let lines, let point):
            let global = globalPoint(point, in: windowFrame)
            guard let move = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: global,
                mouseButton: .left
            ) else {
                throw InputDriverError.eventCreationFailed
            }
            move.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(40))
            // iPhone Mirroring ignores ordinary mouse-wheel line events. A bounded
            // pixel scroll matches the keyboard/trackpad-style scrolling it accepts.
            let pixelDelta = Int32(lines * 80)
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: pixelDelta,
                wheel2: 0,
                wheel3: 0
            ) else {
                throw InputDriverError.eventCreationFailed
            }
            event.location = global
            event.post(tap: .cghidEventTap)
        }
    }

    private func globalPoint(_ point: NormalizedPoint, in windowFrame: CGRect) -> CGPoint {
        CGPoint(
            x: windowFrame.minX + point.x * windowFrame.width,
            y: windowFrame.minY + point.y * windowFrame.height
        )
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

    public func executeGesture(
        gesture: PlannedGesture,
        windowFrame: CGRect,
        exclusions: [ExclusionZone],
        calibrationConfirmed: Bool,
        emergencyStopActive: Bool,
        sessionPauseReason: String?,
        liveInputEnabled: Bool
    ) async throws -> GestureSafetyDecision {
        if awaitingPostcondition {
            return GestureSafetyDecision(
                isAllowed: false,
                rejection: .sessionPaused("Previous action postcondition is unresolved")
            )
        }
        let decision = GestureSafetyValidator().validate(
            gesture,
            exclusionZones: exclusions,
            calibrationConfirmed: calibrationConfirmed,
            emergencyStopActive: emergencyStopActive,
            sessionPauseReason: sessionPauseReason,
            liveInputEnabled: liveInputEnabled
        )
        guard decision.isAllowed else { return decision }
        try await driver.emit(.drag(start: gesture.start, end: gesture.end), in: windowFrame)
        awaitingPostcondition = true
        return decision
    }

    public func executeVerticalScroll(
        action: PlannedAction,
        lines: Int,
        windowFrame: CGRect,
        exclusions: [ExclusionZone],
        emergencyStopActive: Bool,
        sessionPauseReason: String?,
        liveInputEnabled: Bool
    ) async throws -> ActionSafetyDecision {
        if awaitingPostcondition {
            return ActionSafetyDecision(
                isAllowed: false,
                rejection: .sessionPaused("Previous action postcondition is unresolved")
            )
        }
        guard action.kind == .verticalScroll else {
            return ActionSafetyDecision(isAllowed: false, rejection: .outsideRequiredSafeRegion)
        }
        let decision = ActionSafetyValidator().validate(
            action,
            exclusionZones: exclusions,
            emergencyStopActive: emergencyStopActive,
            sessionPauseReason: sessionPauseReason,
            liveInputEnabled: liveInputEnabled
        )
        guard decision.isAllowed else { return decision }
        try await driver.emit(.verticalScroll(lines: lines, at: action.point), in: windowFrame)
        awaitingPostcondition = true
        return decision
    }
}

public enum InputDriverError: Error, LocalizedError, Sendable {
    case eventCreationFailed
    public var errorDescription: String? { "macOS could not create the requested input event." }
}
