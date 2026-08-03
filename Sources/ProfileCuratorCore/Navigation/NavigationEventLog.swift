import Foundation

public enum NavigationEventKind: String, Codable, Sendable {
    case observation
    case proposal
    case safetyDecision
    case postcondition
    case transition
    case sessionPaused
    case emergencyStop
    case sessionReset
}

public struct NavigationEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let kind: NavigationEventKind
    public let state: NavigationState
    public let summary: String

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        kind: NavigationEventKind,
        state: NavigationState,
        summary: String
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.state = state
        self.summary = summary
    }
}

public actor NavigationEventLogStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultStore(fileManager: FileManager = .default) throws -> NavigationEventLogStore {
        let directory = try ProfileRepository.defaultDataDirectory(fileManager: fileManager)
            .appendingPathComponent("navigation-logs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileURL = directory.appendingPathComponent("session-\(formatter.string(from: Date())).jsonl")
        return NavigationEventLogStore(fileURL: fileURL)
    }

    public func append(_ event: NavigationEvent) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(event)
        data.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try data.write(to: fileURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
