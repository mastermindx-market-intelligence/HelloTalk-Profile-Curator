import Foundation

// An offline consumer of the same core used by the macOS app. No network or device APIs.
func boundedFile(_ path: String) throws -> Data {
    guard let handle = FileHandle(forReadingAtPath: path) else { throw JimuReplayError(code: "file_unavailable") }
    defer { try? handle.close() }
    let data = try handle.read(upToCount: JimuReplay.maximumInputBytes + 1) ?? Data()
    guard data.count <= JimuReplay.maximumInputBytes else { throw JimuReplayError(code: "input_too_large") }
    return data
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 1 || arguments.count == 2 else {
        throw JimuReplayError(code: "usage: jimu-replay observation.json [local-policy.json]")
    }
    let policy: JimuReplayPolicy?
    if arguments.count == 2 {
        do { policy = try JSONDecoder().decode(JimuReplayPolicy.self, from: boundedFile(arguments[1])) }
        catch let error as JimuReplayError { throw error }
        catch { throw JimuReplayError(code: "invalid_policy_json") }
    } else { policy = nil }
    let report = try JimuReplay.inspect(boundedFile(arguments[0]), policy: policy)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let output = try encoder.encode(report)
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    let message = (error as? JimuReplayError)?.code ?? "replay_failed"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
