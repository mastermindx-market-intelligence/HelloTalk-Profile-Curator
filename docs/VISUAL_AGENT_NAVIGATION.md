# Visual-agent navigation — Subagent Fabric preview integration

## Operating boundary

This is an additive **offline, no-input navigation preview** in draft PR #7. It adds a local native Inspector panel **in source only**; the new panel does not run HelloTalk, click profiles, collect images, transmit screenshots or initiate any provider or Fabric operation. The installed app has not been updated or proven on a Mac. The pre-existing legacy automatic collector remains unchanged and separate. The current HelloTalk Profile Curator repository is PUBLIC. Never commit real screenshots, profile data, personal preferences, account metadata or credentials.

Source branch: `feat/visual-agent-offline-20261008`; initial base `f098aad41cbb995ed3e5a9c5ccab7c2160c42f0e`. The Jimu W0/W1 branches and local unsaved owner work are separate and must not be overwritten. This slice changes new navigation/core files, a new `VisualAgentOfflineInspector.swift` panel, **one insertion** in `ContentView.swift`, offline tests, a test script, this document, and a new standalone macOS CI workflow. Neither Jimu W1's published changed paths nor its dirty local checkout was modified.

The user confirmed that local Windows/Ollama Qwen has been retired and that Qwen/MiniMax access belongs to the existing Subagent Fabric plan. The previous `OllamaVisualAgent` and direct `MiniMaxVisualAgent(apiKey:)` implementations in this PR have therefore been **removed**, not silently repointed to subscription plan keys.

## Fabric reality and routing ownership

Consult Mastermind's current protected source (observed `master` `732cf7be88e7159b4995a8885fbd381cd1484e3e`), particularly:

- `config/subscription_provider_profiles.v1.json`: Alibaba Token Plan Personal `qwen3.8-flash` (`routine`/`fast`/`subagent`) and `qwen3.8-max` (`hard`); MiniMax Token Plan `MiniMax-M3`. Neither is an automatically enrolled, application-backend inference route.
- `config/subscription_harness_bindings.v1.json`: provider-plan bindings to supported Codex/Claude harnesses are individually `SPEC_ONLY` or `BUILT_NOT_PROVEN`, and have separate provider realm, capacity, canary and usage-policy gates.
- `control_plane/attempt_inference_endpoint.py`: the loopback inference endpoint is **attempt-owned** and can only be constructed inside a separately admitted Worker Attempt with its existing supervisor and sealed route. It is NOT a standing inference server for arbitrary Swift processes.
- `docs/OPENCODE_GO_FABRIC_INTEGRATION_HANDOFF_2026-09-14.md`: OpenCode Go uses existing harness/provider-home/offer/usage owners, not a free pool of direct API keys. The production native worker route requires independent admission and proof.

OpenCode Go's public catalog currently includes Qwen3.8 Flash/Max and MiniMax M3, but a catalog entry is not proof the intended account/model/vision feature is enabled or qualified by Mastermind Fabric. Provider and plan choice belong to **Model Router + Capacity + Shared Provider Control**, not this application. A requested `qwen` or `minimax` preference is not a provider, account, model, API endpoint, claim, routing receipt or authorization.

Public policy anchors (review again at native integration):

- Alibaba Token Plan Personal: https://docs.modelstudio.console.alibabacloud.com/en/model-studio/token-plan-personal-overview — interactive coding/agent tools, no custom application backends or unattended automation scripts.
- MiniMax Token Plan: https://platform.minimax.io/subscribe/token-plan — individual interactive developer use; pay-as-you-go recommended for production.
- OpenCode Go current models: https://docs.opencode.ai/docs/go/ — model inventory and usage limits, not the target account's entitlement or approved backend rights.

Accordingly, a **continuously running GUI navigator cannot simply use these plan keys**. A legitimate production inference path requires a separately supported/authorized application API or equivalent reviewed entitlement, model/input suitability, personal-data and platform authorization, and explicit accounting. Do not fake an admitted Worker Attempt, mount an attempt-private loopback endpoint outside that attempt, borrow subscriber credentials, or build a second Fabric/router/queue/daemon.

## What this slice implements

1. `VisualAgentNavigation.swift` defines the source-frame-bound `visual-agent.v1` proposal, semantic postconditions, one-action safety review, and bounded replay/recovery (no IO).
2. `VisualAgentFrameAdapter.swift` adapts trusted local OCR tab anchors and exclusion geometry into stable candidate element IDs (still offline).
3. `VisualAgentInference.swift` now defines `VisualAgentFabricPreviewRequest`, `VisualAgentFabricPreviewTransport` and `VisualAgentFabricPreviewPlanner`. The **transport is intentionally unimplemented** and must be supplied by a pre-existing *admitted foreground Fabric worker*. The program includes no direct Ollama/MiniMax/Alibaba/Go HTTP client, API key, environment credential loader or hardcoded model/account selector.
4. Model preference is exactly `qwen` or `minimax`; it never chooses which provider plan pays. The default preview denies image transfer. Even with explicit opt-in, this route is *authorized only for synthetic offline fixtures* and checks PNG byte size/signature before handing bytes to the injected transport. **The PNG signature cannot prove image provenance or consent**: the caller/owner must independently prove the fixture is synthetic and source-authorized. This opt-in alone does not create provider admission or rights. Real-screen data has no authorized mode here.
5. Returned provider/model labels are **non-authoritative reporting fields**. Frames must match, model JSON must decode, and the independent existing `VisualAgentSafetyGate` still rejects hallucinated/forbidden elements. Successful review is a **preview**, never a live input permission.
6. `VisualAgentOfflineInspector.swift` is embedded in the existing Inspector sidebar by `ContentView.swift`. It takes the local current `NSImage`, hashes its **PNG-encoded image bytes** using SHA-256, converts existing OCR-derived `About Me`/`Moments` anchors into safe candidate IDs, displays the text-only prompt, and reviews **pasted JSON** against the current frame and current exclusion rectangles. It has no network/model/input implementation. Loading or capturing a real frame locally is NOT permission to transfer its bytes to any model. A changed frame or exclusion set refuses the prior proposal.
7. The adapter and gate allow tab proposals only on recognized profile screens and refuse overlays/interstitials/unknown screens, including where OCR falsely sees a plausible tab. A failed action is deduplicated by semantic intent, not raw screenshot digest; animations cannot reopen the same failed action. Scroll verification consumes the **existing rotating-badge-filtered stable OCR/layout fingerprint** rather than counting a changing clock or nearby-user badge as progress.
8. `.github/workflows/visual-agent-native-validation.yml` runs the native macOS build and tests. A green early run at `af299451` verified native compile/tests of the first Inspector UI. The latest candidate also generates a purely fictional 420x932 PNG via `scripts/generate-visual-agent-synthetic-fixture.swift` and checks the **real Apple Vision OCR -> screen detector -> safe tab adapter** using `VisualAgentNativeImageTests.swift`. Its new CI outcome must be consumed separately.

The expected model JSON remains one proposed action:

```json
{
  "schema_version": "visual-agent.v1",
  "frame_id": "synthetic-frame-a",
  "action": "tap_element",
  "element_id": "tab-about",
  "confidence": 0.94,
  "expectation": { "kind": "screen_kind", "value": "profilePersonalInfo" },
  "rationale": "Open the observed navigation tab"
}
```

Allowed actions: `tap_element`, `scroll_up`, `scroll_down`, `wait`, `pause`. Social controls, payment, account changes and model-generated coordinates are forbidden. A changed screenshot alone never proves a successful tap. After a failed semantic postcondition, an identical action must not blindly retry; repeated failure pauses for a human.

## Offline verification and local Codex Sol continuation

Run `sh scripts/test-visual-agent-core.sh` for the isolated compiler/smoke proof. A Swift 6.2.1 Linux isolated run of the updated source reached **20 XCTest passes, zero failures**, plus the offline smoke; exact published Git blob identities must be matched to the tested files at handoff. This is NOT a full native app build, visual UI proof, Fabric model call, or real-device test. The new GitHub macOS CI workflow is the independent native build/test route, and Codex should consume its exact outcome before merge.

The next bounded local Codex Sol vertical is **native Inspector acceptance and Fabric-admitted synthetic fixture replay**:

1. Reconcile the active Jimu W1 writer, dirty working tree, and this PR's exact head before any native checkout, branch change or shared-file write. Do not duplicate the existing W1 worker or reset its local files.
2. Test the current draft branch with Swift on macOS and fix native compile failures without changing existing collector behavior.
3. Generate a neutral screenshot with `swift scripts/generate-visual-agent-synthetic-fixture.swift /tmp/visual-agent-demo.png`. Verify its actual Vision OCR and navigation tabs through CI/native tests. In one already-authorized *interactive* Fabric worker session, evaluate that fictional image with current eligible Qwen and MiniMax routes, recording actual provider/served model, request/response receipt, latency, safety verdict and failure mode. Check the provider's real image-input/harness policy before sending an image. Do not use real profiles, credentials in logs, or unapproved cross-device screenshots.
4. Validate the existing read-only **AI Navigation Preview** panel in a running macOS app, using only an explicitly synthetic or authorized local screenshot: check the displayed frame digest and candidates, paste one accepted mock proposal and one unsafe mock proposal, inspect refusals and stale-frame behavior, and capture one evidence screenshot with no personal information. Native UI existence in source is not real UI proof.
5. Separately adjudicate any legitimate production inference entitlement, HelloTalk platform/content rights, iPhone Mirroring input compatibility, data minimization and consent before considering unattended/live navigation. Provider subscription activation is NOT implied by this source work.

## Acceptance boundary

Source implementation: `BUILT_NOT_PROVEN` until a complete native app test. The new native Inspector UI is **implemented in source but not installed or visually verified**. The synthetic model transport seam is `PARTIAL`; the actual Fabric-hosted executor and true inference have **not** run here. Native interactive fixture replay: `NOT_BUILT` until the admitted worker proves it. Live AI-driven app automation: `NOT_BUILT` and held behind rights, provider, source-custody and real-device gates. Keep draft PR open; do not merge or advertise autonomous HelloTalk operation from source or isolated smoke alone.
