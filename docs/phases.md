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
- [x] Associate visible card names, optional ages, and photo-safe rectangles

Exit evidence: unit tests plus successful replay of the supervised fixture set.

## Phase 2 — safe live navigation dry run

- [x] Capture only the selected iPhone Mirroring window with ScreenCaptureKit (single-frame, read-only)
- [x] Add a read-only five-frame burst for the rotating location/nearby badge
- [x] Calibration editor for normalized safe and excluded regions (awaiting supervised real-UI calibration)
- [x] Deterministic OCR/geometry content fingerprint and frame-change postcondition
- [x] Mirroring-window resize detection and new-session recalibration gate
- [x] Fail-closed carousel gesture preview, disabled after supervised mirroring validation failed
- [x] Discrete vertical scroll path verified; touch-drag gestures disabled as nonfunctional
- [x] Bounded, deduplicated visible-card graph traversal policy and ledger
- [x] Age-anchored visible-card photo proposals with dynamic social/ad-control exclusions
- [x] State/postcondition event log with local JSONL audit trail
- [x] Latched emergency stop and conservative session caps
- [x] Supervised UI observations in `docs/ui-observations.md`
- [x] Establish gallery-first discovery policy with Custom Search/Connect as seed fallbacks

Exit evidence: profile-to-Personal-Info-to-Suggestions traversal in dry-run/step mode with no social control activated.

The visible-card proposal path now associates missing-age cards by name geometry and automatically verifies identity changes before committing graph traversal state.

## Phase 3 — primary collection MVP

- [x] Female and age 18–21 opened-profile verification
- [x] INFJ/INTJ and separately routed secondary eligibility
- [x] Mac-rendered profile checkpoint capture with local media identity
- [x] GRDB persistence, checkpointing, and username merge
- [x] Basic local review grid

Remaining supervised gate: validate calibrated PFP open/crop/close actions before exposing them in the runtime UI.

## Phase 4 — Moments and no-face policy

- [ ] Automated Moment photo viewer/gallery navigation (recognition, safe crop, manual checkpointing, limits, and finalization are implemented; action geometry requires the next supervised UI session)
- [x] 20 scanned / 10 retained hard limits
- [x] Perceptual-hash deduplication
- [x] No-face tombstone finalization and media purge
- [x] Crash/restart resume checkpoint

## Phase 5 — optional Qwen analysis

- [x] Tailscale/Ollama endpoint validation and health check
- [x] Structured JSON tasks with versioned prompts
- [x] Offline queue, timeout, bounded retry
- [x] Evidence/confidence persistence schema and dashboard score display

Deferred by user: supply the Windows MagicDNS/Tailscale URL and choose the upgraded Qwen model.

## Phase 6 — secondary group and ranking

- [x] Secondary MBTI routing and mandatory no-face policy
- [x] Location tiers and configurable score-weight model
- [x] High-priority secondary rules

## Phase 7 — dashboard hardening

- [x] Database-backed filters, sorting, and pagination
- [x] Detail gallery, score breakdown, notes, and review shortcuts
- [x] CSV/JSON export and data deletion tools
- [ ] Per-image Qwen evidence links (populates after live endpoint wiring)

## Phase 8 — packaging and hardening

- [x] Native app bundle metadata and entitlements
- [x] Hardened Runtime app/DMG packaging and optional notarization script
- [x] Unknown-state, resize, persistence, offline-retry, and 500-action exclusion stress tests
- [ ] Developer ID signing/notarization credentials and final supervised long-session regression
