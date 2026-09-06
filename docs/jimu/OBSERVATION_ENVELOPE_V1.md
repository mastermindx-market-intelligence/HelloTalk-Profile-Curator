# Common observation envelope v1 — agreed adapter boundary

This is the implementation-facing freeze of Architecture v1.0 section 03, not a new runtime or architecture. Both the interim macOS observer and the Android proof must use this sensor envelope; both feed the same derived `ProfileObservation` contract. Implementers may not rename, omit or reinterpret fields independently.

```text
observation_id; schema_version = "1.0.0";
platform = jimu | hellotalk | synthetic;
account_id; device_id; session_id; lease_epoch; device_boot_id;
adapter_manifest_id; app_package_or_bundle; installed_app_version; OS_build;
capture_started_at_utc; capture_finished_at_utc; source_monotonic_ms;
frame_sha256; local_asset_id; frame_sequence;
viewport {width_px,height_px,insets,rotation,scale,coordinate_origin};
tree {state: AVAILABLE|UNAVAILABLE|PARTIAL,captured_at,tree_hash,nodes_ref};
screen {kind,confidence,supporting_anchor_ids,layout_manifest_id};
input_activity_since_capture; capture_restrictions; privacy_scope_id.
```

`platform` identifies the application namespace, consistent with `ProfileObservation`; adapter manifest identifies iOS mirroring versus Android transport. IDs are opaque local IDs, never credentials or public asset URLs. UTC fields describe capture intervals. Monotonic time has meaning only within the exact device boot epoch; do not compare it with the host's clock. The capture interval must be ordered; mismatched account, boot, session or lease is not a coherent observation.

Viewport uses pixel dimensions, explicit scale/insets/rotation and top-left coordinate origin. Missing UI tree is represented as UNAVAILABLE with nullable capture/hash/reference fields; PARTIAL is not AVAILABLE. No text is invented from unavailable sensors. A frame/tree pair crossing card change, animation or geometry change must be marked unsuitable for action even if both captures individually succeeded. Unknown screen or protected capture is an explicit limitation, not permission to try a bypass.

`source_envelope_ids` in a ProfileObservation references these envelope IDs. Its per-field `source_observation_ids` references the same declared envelope IDs; source regions/anchors live in the envelope's evidence rather than unversioned extra ProfileObservation properties. Semantic validation must check the actual linked envelopes/assets, not only declared reference strings.

The published ProfileObservation JSON schema is the accepted illustrative schema; the W0 Swift decoder adds semantic reference and missingness checks. W0's synthetic CLI does not yet consume/authenticate full raw envelopes. Therefore raw-envelope conformance remains BUILT_NOT_PROVEN only after a producer and consumer actually exist, and is currently SPEC_ONLY.

## W2 build and acceptance boundaries

W2 build may start against this agreed v1 boundary in parallel with W1; it does not wait for completion of the native inspector. W1 and W2 must consume one exact-version synthetic envelope/ProfileObservation fixture and checksum manifest. Passing both consumer and producer conformance tests is an acceptance gate, not a circular prerequisite for starting either implementation. Fixture-only Android work may run on the team's own synthetic test application. Installed target-app/package/version/account/device/rights evidence is required separately for actual Jimu observation/navigation proof. No PASS, RIGHT, Note, Instant or purchase is authorized by this contract or by W2.

W1 owns canonical persistence and field projections. W2 owns Android sensing and its contract tests, not an alternate database or policy model. Incompatible evidence requires a bounded contract correction with explicit versioning, not a parallel schema. Return conformance results and concrete missing device facts; do not hold the offline inspector behind unavailable physical hardware.
