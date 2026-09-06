# Jimu native offline inspector — W1 text-evidence slice

This is an implementation in the existing macOS application, not a second app/database or a live Jimu integration. The accepted Architecture v1.0 and separate private Preference Policy v1 remain controlling.

## Run and use

On the supported Mac toolchain:

```sh
swift run ProfileCurator --jimu-offline
```

The ordinary application also offers **Window → Jimu Offline Inspector**. The offline launch flag does not enter the legacy acceptance-autostart path.

Use **Local policy…** to load a JimuReplayPolicy JSON file, then **Import…** to open a ProfileObservation JSON file. The repository's `fixtures/jimu/synthetic/` examples are neutral test data, not the owner's actual preferences. Real profiles require independently admitted offline scope; a fixture's own assertion does not grant that scope. Native action/capture permission remains separate and unverified.

Select an observation to inspect its fields, missingness, source references and original text. **Correct** populates the correction editor. Text fields accept ordinary text; other values use JSON. Give a reason, then append the correction. Restart the app and select the same observation: original and corrected versions remain available. The current inspection policy is saved locally beside `curator.sqlite`; prior import/feedback policies remain in their immutable records.

The local profile-evidence buttons record manual approve/reject labels. Comparing two observations supports left/right/tie/neither. The separate action-context row records only the action the owner would consider, with its context. It never swipes, sends, spends or purchases. Historical feedback can be superseded without editing earlier choices.

## Exact scope

- Reuses ProfileRepository, its existing DatabaseQueue, existing GRDB migrator and existing `curator.sqlite`.
- Adds immutable `profile_observations`, append-only `observation_corrections`, and `preference_feedback`.
- Preserves exact imported bytes; identical imports are idempotent and same-ID/different-byte imports conflict.
- Binds feedback to original-byte SHA-256, the shown correction IDs and the complete current replay-policy value, not just its label.
- Manual age correction cannot create platform adult evidence or enable preference labeling.
- Refuses stale presentations and incompatible label scopes before committing a label.
- Explicit observation deletion cascades dependent correction/comparison feedback; the existing Delete All includes these tables. This is logical data deletion, not forensic erasure of backups/storage media.

## Important limitation: text evidence is not visual calibration

This slice does not import/authenticate source-frame bytes or display isolated photo crops. Every feedback basis is marked `TEXT_EVIDENCE_ONLY_V1` and `modelScoresVisible=false`. **Visual-only feedback is refused**, not approximated from profile text. A later training consumer must filter by compatible presentation kind and scope; it must not mix these text-only records into visual training.

Profile references are inspectable declarations, not authenticated sensor-envelope/asset receipts. Overall candidate eligibility and native platform capability remain unverified. No model, embedding, trained ranking head, device adapter, Note generator or executor is added.

## Verification

```sh
swift test --jobs 2 --skip JimuInspector
JIMU_UI_PROOF_DIR=/tmp/jimu-native-proof swift test --jobs 2 --filter JimuInspector
swift build --product ProfileCurator --jobs 2
```

The dedicated W1 workflow runs on the exact source branch with read-only repository permissions. The native tests use actual GRDB persistence and the real SwiftUI view/view-model. They reopen the database, preserve earlier label bases, and render synthetic evidence/history at controlled window sizes. This is native consumer/render proof, not an external UI click-through, owner-device installation or live Jimu acceptance. Optional legacy private fixtures remain optional and are reported as skipped when absent.

## Continuation

The next W1 capability is local source-asset binding plus isolated visual presentation and scope-correct visual labels, preserving these immutable records and the same database. Shared raw-envelope/asset conformance with W2, independent review and owner-Mac proof remain separate acceptance work. W0 native rights/device gaps must not stall this offline path. No live engagement is authorized by this implementation.
