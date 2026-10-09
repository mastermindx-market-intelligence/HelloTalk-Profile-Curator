# Visual-agent navigation, offline-first W0

## Scope and custody

An additive, **dry-run** visual navigation module branched from `main` base `f098aad41cbb995ed3e5a9c5ccab7c2160c42f0e`. It does not replace `InspectorViewModel` or `SafeInputExecutor`, turn on inputs, open HelloTalk, collect profiles, transmit images, store observations, or alter any Jimu W0/W1-owned file. This repo is public: keep private preferences, screenshots, keys, names and profiles out of Git.

The old engine has fixed screen/phase switches, bounded loops, and rules-based unknown-state recovery. The new adapter is intended to propose **one navigation action per screenshot**, with a model-agnostic typed contract and a safety gate enforced independently from model output.

## Contract

The model receives a screenshot, a constrained objective, a frame identifier, coarse screen classification, and **candidate element IDs produced by an existing trusted observation system**. OCR/profile text is not duplicated into the prompt. It returns strict JSON:

```json
{
  "schema_version": "visual-agent.v1",
  "frame_id": "synthetic-frame-a",
  "action": "tap_element",
  "element_id": "tab-about",
  "confidence": 0.94,
  "expectation": { "kind": "screen_kind", "value": "profilePersonalInfo" },
  "rationale": "Open the observed About Me navigation tab"
}
```

Actions: `tap_element`, `scroll_up`, `scroll_down`, `wait`, `pause`. No model-generated coordinates, drag commands, social actions, device commands or free-form tool names are permitted. A tap resolves to an existing known `PlannedActionKind` and a trusted, normalized candidate rectangle. Low confidence, missing/stale frame IDs, unsafe element roles, forbidden labels, excluded regions, missing independent postconditions, unresolved actions and repeated identical failed actions fail closed. Screenshot hashes alone cannot verify tap success. The session requests a fresh plan only after the previous issued action is observed; a failed semantic verification may trigger a distinct bounded replan, never an identical blind retry. Two consecutive failed postconditions demand human inspection. Reset is explicit.

**Important:** `VisualAgentSafetyGate.review` returns a proposal, **not authority to execute it**. The production host must recapture and validate current window/frame, permissions, excluded zones, active pauses, postconditions and user consent through the existing `SafeInputExecutor` before any input. Never treat the model's confidence as a permission override. This W0 module intentionally does not wire an input executor.

## Model providers

- `OllamaVisualAgent` reuses the existing `VLMClientProtocol` and model configuration. The existing Windows Ollama/Tailscale boundary is private-network, not zero-external-device; image transmission is disabled by default and additionally requires an admitted screenshot policy.
- `MiniMaxVisualAgent` encodes an OpenAI-compatible vision request to MiniMax M3. **Cloud image transmission is disabled by default**, and the provider can only use the fixed HTTPS endpoint `api.minimax.io/v1/chat/completions`. An explicit `allowOffDeviceImages` decision is insufficient by itself: permission to transmit *particular* screenshot data and HelloTalk/platform source rights must still be established before calling it. No keys or images belong in source control.
- Neither adapter was tested against a real service in this W0 slice. Do not assume provider JSON quality or actual GUI accuracy from compilation.

## Minimal offline integration plan for local Codex Sol

1. Reconcile the existing Jimu W1 branch, unsaved Mac writer and current source custody before touching overlapping app/Package/DB paths. This W0 branch changes only new Navigation files, one new test, and this document.
2. Build an `ObservationSnapshot` -> `VisualAgentFrame` adapter (an initial OCR-tab-only adapter is included) using the **current** OCR/anchor geometry and calibrated exclusion zones. Never mint actionable navigation elements from model-suggested rectangles or unsafe labels. Reuse existing surface/identity verification; when unavailable, return `pause`.
3. Add a visible **AI Navigation Preview** to Inspector; view the proposed element, objective, reason, source frame, expected postcondition, and rejection. Defaults to offline replay, no input.
4. Run `swift test` on the Mac and the offline test suite. Exercise malformed/stale/model-hallucinated/forbidden/occluded/social cases. Keep real screenshots outside Git.
5. Separately verify physical iPhone Mirroring input transport; no AI can repair gestures the OS never delivers. Do not wire autonomous actions or personal-data collection without the platform/consent rights gate, independent safety review and supervised real-device verification.

## Product acceptance (not yet met)

- Offline: 100% rejection of forbidden control proposals and all stale/missing-source proposals in test fixtures; no emitted input; meaningful semantic verification.
- Model: screenshot replay demonstrates higher destination accuracy and lower avoidable pause rate than fixed-state baseline at comparable safety; report denominator, latency, per-step cost, and recovery success. Never use success anecdotes as proof.
- Real device: explicit platform authorization and supervised, action-by-action tests; zero undesired social actions; robust pauses on ambiguous UI, window swaps and stale screenshots.

Current state: **BUILT_NOT_PROVEN** as isolated implementation until target Mac build plus fixture replay; **NOT_BUILT** for application integration and live AI-led navigation.
