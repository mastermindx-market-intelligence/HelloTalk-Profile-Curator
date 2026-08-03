# Architecture

## Operating principle

The app is a deterministic local macOS controller. Vision/OCR output, calibrated normalized geometry, explicit state transitions, and visible postconditions govern every proposed action. Unknown states pause the run; they do not trigger exploratory clicks.

The build has two planes:

- **Observation plane** — window discovery, macOS window capture, OCR, face detection, hashes, parser output, and Inspector overlays.
- **Action plane** — safety validation, dry-run previews, bounded gestures, postcondition checks, recovery, and emergency stop.

The action plane remains disabled until the observation plane is validated against supervised fixtures and the real mirrored UI.

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
│   └── WindowCaptureService (phase 2)
├── Vision
│   ├── VisionFixtureAnalyzer
│   ├── MBTIParser
│   └── LocationNormalizer
├── Safety
│   ├── exclusion zones
│   ├── action validation
│   └── emergency-stop policy
├── Navigation
│   ├── explicit state model
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

## Local data boundary

The default data root is `~/Library/Application Support/ProfileCurator/`. Real screenshots, media, database files, diagnostics, and local configuration are ignored by Git. Network analysis is optional and limited to a user-configured Ollama endpoint reachable over the user's private Tailscale network. Collection continues to a local queue if that endpoint is unavailable.

## Identity and image boundaries

Profiles deduplicate only by normalized username. Media deduplicates only by perceptual hash plus size similarity. No facial embeddings, cross-account identity inference, or face recognition are part of the design.

## Packaging path

Swift Package Manager is used while the offline harness and core modules evolve. Before direct distribution, the executable will be wrapped in an Xcode macOS application target with entitlements, Hardened Runtime, Developer ID signing, notarization, stapling, and DMG packaging.
