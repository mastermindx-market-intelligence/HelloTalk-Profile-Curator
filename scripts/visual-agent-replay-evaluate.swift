import Foundation

/// Run with --self-test, or with <cases.json> <trials.json> for offline model evidence.
/// No network, model inference, or app input. Files must contain only authorized synthetic data.
@main
struct ReplayEvaluation {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let cases: [VisualAgentReplayCase]
        let trials: [VisualAgentReplayTrial]
        if args == ["--self-test"] {
            let element = VisualAgentElement(id: "tab-about-me", label: "About Me", role: .navigation,
                                             actionKind: .selectAboutMe,
                                             bounds: .init(x: 0.1, y: 0.35, width: 0.2, height: 0.07))
            let frame = VisualAgentFrame(id: "fictional-frame", screenKind: "profileTop",
                                         visibleText: ["About Me"], elements: [element], exclusions: [],
                                         stableObservationID: "fictional-layout")
            cases = [.init(id: "fictional-safe", goal: .locateDetails, frame: frame,
                           requiredAction: .tapElement, requiredElementID: "tab-about-me")]
            let answer = #"{"schema_version":"visual-agent.v1","frame_id":"fictional-frame","action":"tap_element","element_id":"tab-about-me","expectation":{"kind":"screen_kind","value":"profilePersonalInfo"},"confidence":0.98,"rationale":"Observed fictional About Me"}"#
            trials = [.init(caseID: "fictional-safe", modelPreference: .qwen,
                            responseJSON: answer, elapsedMilliseconds: 120)]
        } else if args.count == 2 {
            cases = try JSONDecoder().decode([VisualAgentReplayCase].self,
                                              from: Data(contentsOf: URL(fileURLWithPath: args[0])))
            trials = try JSONDecoder().decode([VisualAgentReplayTrial].self,
                                               from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        } else {
            throw ReplayEvaluationError.invalidArguments
        }
        let report = try VisualAgentReplayBenchmark().score(cases: cases, trials: trials)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let json = String(data: data, encoding: .utf8) else { fatalError("Unexpected non-UTF8 JSON") }
        print(json)
    }
}

private enum ReplayEvaluationError: Error { case invalidArguments }
