# W0 offline evidence replay

This slice supplies a real Swift consumer of the accepted `ProfileObservation` contract. It validates declared evidence references and age evidence, then emits an inert inspection report. It does not collect profiles, perform model inference, persist the W1 history database, navigate a device or send an action.

## Run

Requires Swift 6.1 or newer. No external dependency is needed for this focused command.

```sh
sh scripts/jimu-replay.sh fixtures/jimu/synthetic/profile.json fixtures/jimu/synthetic/policy.example.json
sh scripts/test-jimu-replay.sh
```

The example is a synthetic age-29 text fixture with a neutral example policy, not the owner's preferences. The frame hash identifies synthetic fixture-description bytes, not a captured photograph. No pixels, actual account or native platform capability are established by this fixture.

The report has `age_eligibility=ELIGIBLE_FOR_REVIEW`, `candidate_eligibility=NOT_EVALUATED`, `engagement_state=DISABLED_OFFLINE`, `enabled_actions=[]`, and `native_capability_state=UNVERIFIED`. Age eligibility is not complete candidate eligibility or permission to act.

Omitting the local policy returns `NO_ENGAGEMENT` with `policy_not_configured`. Supply personal configuration from outside the checkout; never commit it. Real-profile imports require an independently admitted offline rights-scope identifier in that local configuration. A JSON rights claim does not itself establish permission; operators must verify its basis.

## Validation boundary

The Swift core checks exact object keys, supported schema, required identifiers, timestamps, hash shape, explicit null semantics, unique field IDs, declared source references, supported source kinds, confidence range and consistent displayed-age evidence. PRESENT and unknown/null states are not interchangeable. It recomputes age eligibility rather than trusting an upstream adult claim. Synthetic imports cannot pretend to be a live platform.

The core validates references within the submitted document; it does not authenticate source envelopes, open/verify image bytes, prove current recipient identity, establish capture rights or validate live freshness. The raw observation envelope producer/consumer, immutable persistence and native user interface are separate remaining waves. Input JSON is bounded to 2 MiB; errors omit profile contents.

## Verification and limitations

Executed on Linux x86_64 with Swift 6.2.1: 30 XCTest cases, zero failures after implementation. The initial unimplemented core failed the tests. A mutation adding RIGHT to `enabled_actions` caused test failures; restoring the original source restored green. The command-line consumer was compiled and run with and without a policy.

`test-jimu-replay.sh` creates a temporary, dependency-free verification harness containing exactly the production core file and its tests; it is not a second persistent application. Full existing `swift test`, SwiftUI/GRDB integration, native Mac UI proof and installed-device tests were NOT run here. They remain required before accepting the next app-integrated delivery. Do not call this W1 complete or Jimu PROVEN_LIVE.

## Exact next capability

Import an authorized offline observation into the existing `curator.sqlite`; inspect field evidence in the native app; append a correction without changing the original observation; restart and recover both versions. Add isolated visual-only, full-profile and action-context feedback records without model-score contamination. Preserve existing HelloTalk behavior. Return exact source/CI/test/UI evidence and stop before live input.
