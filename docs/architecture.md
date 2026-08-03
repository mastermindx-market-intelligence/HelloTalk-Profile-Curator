# Architecture

## Operating principle

The app is a deterministic local macOS controller. Vision/OCR output, calibrated normalized geometry, explicit state transitions, and visible postconditions govern every proposed action. Unknown states pause the run; they do not trigger exploratory clicks.

The build has two planes:

- **Observation plane** — window discovery, macOS window capture, OCR, face detection, hashes, parser output, and Inspector overlays.
- **Action plane** — safety validation, dry-run previews, bounded gestures, postcondition checks, recovery, and emergency stop.

The action plane remains disabled until the observation plane is validated against supervised fixtures and the real mirrored UI.

## Discovery strategy

The observed 2026-08-03 UI makes the in-profile **Suggested for You** horizontal gallery the primary inventory engine. It exposes a broader, recently-active pool and tends to preserve gender similarity from a female seed profile. That similarity is only a routing hint: every opened profile still requires an explicit female badge and age 18–21 verification.

Custom Search is a seed/fallback path, not the main traversal loop. Its results are restricted to currently active users, its rows omit exact age/gender, and selecting the Female filter opened a paid subscription offer during supervised testing. The safe loop is therefore:

```text
Acquire female age-18–21 seed through age-filtered Custom Search or Connect
  -> verify opened profile age and female badge
  -> scan About Me for target MBTI
  -> seek Suggested for You at profile bottom
  -> traverse horizontal gallery as primary inventory
  -> re-verify every opened profile
  -> return to a seed feed only when the gallery is absent or exhausted
```

## Module map

```text
ProfileCuratorApp
├── PermissionOnboarding
├── InspectorWorkspace
└── SessionControls

ProfileCuratorCore
├── Domain
│   ├── normalized geometry
│   ├── OCR and face observations
│   └── profile and score records
├── Capture
│   ├── MirroringWindowLocator (read-only in phase 1)
│   └── WindowCaptureService (single frame and read-only temporal burst)
├── Vision
│   ├── VisionFixtureAnalyzer
│   ├── MBTIParser
│   ├── ProfileHeaderParser and GenderBadgeClassifier
│   ├── RecommendationAgeParser
│   └── RotatingLocationBadgeParser and LocationNormalizer
├── Safety
│   ├── exclusion zones
│   ├── action validation
│   └── emergency-stop policy
├── Navigation
│   ├── explicit state model
│   ├── gallery-first discovery policy
│   └── postconditions/recovery (phase 2)
└── Persistence
    └── GRDB-backed local repository
```

## Coordinate contract

All stored and planned rectangles use normalized `0...1` coordinates with a top-left origin. Vision's bottom-left normalized boxes are converted at the framework boundary. Absolute desktop coordinates are never persisted. A planned point is converted to screen coordinates only immediately before execution and only after revalidating the target window frame.

## Safety gates

An input action may eventually execute only if all gates pass:

1. the mirrored window identity and frame are current;
2. observation confidence is above the state's threshold;
3. the state explicitly allows the action kind;
4. the point is inside a calibrated safe region;
5. the point is outside every active exclusion rectangle;
6. emergency stop is clear and session limits are not exceeded;
7. dry-run mode is off;
8. the previous action reached its visible postcondition.

The runtime records the observation, plan, validation result, action, and postcondition as separate events.

Rotating labels are temporal observations. The map pill alternates between a city/country/local-time label and a nearby-user count every 1–2 seconds, so location capture uses five frames at 700 ms spacing. Only the city phase enters location normalization; nearby counts remain separate metadata.

## Local data boundary

The default data root is `~/Library/Application Support/ProfileCurator/`. Real screenshots, media, database files, diagnostics, and local configuration are ignored by Git. Network analysis is optional and limited to a user-configured Ollama endpoint reachable over the user's private Tailscale network. Collection continues to a local queue if that endpoint is unavailable.

## Identity and image boundaries

Profiles deduplicate only by normalized username. Media deduplicates only by perceptual hash plus size similarity. No facial embeddings, cross-account identity inference, or face recognition are part of the design.

## Packaging path

Swift Package Manager is used while the offline harness and core modules evolve. Before direct distribution, the executable will be wrapped in an Xcode macOS application target with entitlements, Hardened Runtime, Developer ID signing, notarization, stapling, and DMG packaging.
