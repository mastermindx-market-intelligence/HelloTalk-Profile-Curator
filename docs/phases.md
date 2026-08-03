# Phased build docket

## Phase 1 — offline harness and Inspector foundation

- [x] Repository and Swift package structure
- [x] Architecture and risk register
- [x] Exact MBTI parser and requested location normalization
- [x] Apple Vision OCR and face box/quality analyzer
- [x] Screenshot fixture loader and overlay model
- [x] Read-only iPhone Mirroring window discovery
- [x] Permission status surface
- [x] Normalized action/exclusion preview model
- [x] Add supervised private fixture screenshots (ignored locally; never committed)
- [x] Tune parsers against short/long real profiles
- [ ] Associate recommendation ages with real card rectangles

Exit evidence: unit tests plus successful replay of the supervised fixture set.

## Phase 2 — safe live navigation dry run

- [x] Capture only the selected iPhone Mirroring window with ScreenCaptureKit (single-frame, read-only)
- [x] Add a read-only five-frame burst for the rotating location/nearby badge
- [x] Calibration editor for normalized safe and excluded regions (awaiting supervised real-UI calibration)
- [x] Deterministic OCR/geometry content fingerprint and frame-change postcondition
- [ ] Mirroring-window resize detection
- [x] Fail-closed carousel gesture preview, disabled after supervised mirroring validation failed
- [x] Discrete vertical scroll path verified; touch-drag gestures disabled as nonfunctional
- [x] Bounded, deduplicated visible-card graph traversal policy and ledger
- [x] Age-anchored visible-card photo proposals with dynamic social/ad-control exclusions
- [x] State/postcondition event log with local JSONL audit trail
- [x] Latched emergency stop and conservative session caps
- [x] Supervised UI observations in `docs/ui-observations.md`
- [x] Establish gallery-first discovery policy with Custom Search/Connect as seed fallbacks

Exit evidence: profile-to-Personal-Info-to-Suggestions traversal in dry-run/step mode with no social control activated.

Remaining implementation gate: associate missing-age cards with photo/name geometry and connect accepted dry-run proposals to the identity-change state transition.

## Phase 3 — primary collection MVP

- [ ] Female and age 18–21 opened-profile verification
- [ ] INFJ/INTJ collection only
- [ ] Profile-top and enlarged-PFP macOS capture
- [ ] GRDB persistence, checkpointing, and username merge
- [ ] Basic local review grid

## Phase 4 — Moments and no-face policy

- [ ] Moment photo viewer/gallery navigation
- [ ] 20 scanned / 10 retained hard limits
- [ ] Perceptual-hash deduplication
- [ ] No-face tombstone and media purge
- [ ] Crash/restart resume

## Phase 5 — optional Qwen analysis

- [ ] Tailscale/Ollama endpoint validation and health check
- [ ] Structured JSON tasks with versioned prompts
- [ ] Offline queue, timeout, bounded retry
- [ ] Evidence/confidence persistence and display

## Phase 6 — secondary group and ranking

- [ ] Secondary MBTI routing and mandatory no-face policy
- [ ] Location tiers and editable score weights
- [ ] High-priority secondary rules

## Phase 7 — dashboard hardening

- [ ] Database-backed filters, sorting, and pagination
- [ ] Detail gallery, evidence links, notes, and review shortcuts
- [ ] CSV/JSON export and data deletion tools

## Phase 8 — packaging and hardening

- [ ] Xcode application target and entitlements
- [ ] Developer ID, Hardened Runtime, notarized/stapled DMG
- [ ] Long-session, UI-drift, disconnect, permission, and recovery tests
