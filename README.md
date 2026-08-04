# HelloTalk Profile Curator

Private, local-first macOS tooling for supervised inspection of an iPhone Mirroring window. The project is intentionally being built in this order:

1. offline screenshot replay and parsing;
2. read-only Inspector and calibration;
3. dry-run navigation previews with explicit exclusion zones;
4. supervised, postcondition-checked navigation;
5. collection, review, and optional local-network analysis.

The app must never send messages, follow, like, gift, press **Say Hi**, or invoke an iPhone screenshot action. It only accepts adult female profiles with an explicitly displayed age of 18–21 and never uses face recognition or face embeddings.

## Current slice

The current local build includes an Inspector, persistence layer, review dashboard, deterministic runtime core, and an optional offline-first analysis boundary. It can:

- load a screenshot fixture from disk;
- run Apple Vision OCR and face capture-quality detection;
- draw normalized OCR and face boxes;
- extract exact target MBTI values;
- recover observed profile/card age badges without treating username suffixes as ages;
- classify pink versus blue gender-badge evidence locally and fail closed when ambiguous;
- normalize the configured priority locations;
- locate the iPhone Mirroring window read-only;
- capture one macOS-rendered frame from the selected mirroring window for Inspector replay;
- capture a five-frame burst to resolve the rotating location/nearby badge without conflating its two states;
- classify known screens, fail closed immediately, and latch the session after two consecutive unknown observations;
- record observations, proposals, safety decisions, transitions, and postconditions to a local JSONL audit log;
- traverse fresh recommendation inventory through bounded, deduplicated visible-card profile hops;
- derive dry-run photo targets from visible card-name geometry, associate optional age badges, and dynamically exclude OCR-detected Say Hi, Follow, Gift, Like, chat, download, and ad controls;
- automatically arm a username-change postcondition for every graph-hop proposal and count a node only after the next captured frame verifies a different profile;
- use discrete vertical scroll events while keeping touch-drag and horizontal carousel gestures disabled by default;
- latch an emergency stop and enforce conservative duration, proposal, and profile-visit limits;
- show Screen Recording and Accessibility permission status;
- preview intended action and never-click regions without executing input;
- draw and save normalized calibration regions over a fixture or captured frame.
- accumulate eligibility evidence across captured frames for one verified username and checkpoint only female, age-18–21 primary/secondary target profiles;
- merge profiles by normalized username in SQLite and store Mac-rendered frames with perceptual-hash deduplication;
- enforce 20-scanned/10-retained media planning and mandatory secondary no-face rejection;
- resume deterministic navigation from an atomic local checkpoint and pause on window resize, timeouts, unknown screens, or unresolved postconditions;
- browse a local review grid with primary, secondary, high-priority, shortlist, contacted, and rejected sections;
- apply database-backed search, age, city, score, confidence, usable-face, status/group, sorting, and 20/50/100-row pagination;
- edit notes/status, inspect retained media, export CSV/JSON, delete profile media, or delete all collected data;
- configure and test an optional Ollama/Qwen endpoint over Tailscale, with fixed JSON prompts, timeouts, bounded retry, and a persistent offline queue.
- recognize PFP/Moment viewers, crop the photo region above known UI controls, ignore perceptual duplicates, enforce 20/10 counters, finalize the no-face rule, and enqueue only media-backed analysis jobs.
- treat static posts, videos, and Live Photos uniformly as visible still-image sources: capture one stabilized Mac-rendered frame, store it as PNG, and never download or retain motion media.
- traverse Moment galleries through a supervised, calibrated 3×3 thumbnail grid after a discrete vertical scroll, then use a long downward dismiss gesture; broken in-viewer horizontal swipes remain disabled.

The production UI still defaults to dry-run and does not expose an unattended live-input switch. The core input executor exists behind explicit safety gates and a postcondition lock, but activation remains a supervised release gate. The experimental orange gallery path remains disabled after supervised mirroring validation showed that horizontal drag/scroll does not move the carousel.

The live VLM default is `qwen3.5:9b`: a 6.6 GB multimodal Ollama build running fully on the Windows RTX 5070 Ti 16 GB. Ollama remains bound to Windows localhost and is exposed only through a private Tailscale TCP Serve route; the Mac stores that tailnet endpoint in its ignored local configuration. Larger 27B-class packages exceed comfortable all-GPU operation on this card. Analysis requests disable the model's optional reasoning trace and require non-streaming JSON, keeping stored results compact and deterministic.

Dry-run audit logs are written locally under `~/Library/Application Support/ProfileCurator/navigation-logs/`. They contain state and safety metadata, not screenshot pixels.

## Run

```bash
swift run ProfileCurator
```

Or open `Package.swift` in Xcode and run the `ProfileCurator` executable.

For a locally discoverable development app bundle:

```bash
chmod +x scripts/build-debug-app.sh
scripts/build-debug-app.sh
open "dist/Profile Curator.app"
```

For a Hardened Runtime app plus DMG (ad-hoc signed unless a Developer ID identity is supplied):

```bash
chmod +x scripts/package-dmg.sh
scripts/package-dmg.sh
```

Set `PROFILE_CURATOR_SIGN_IDENTITY` to a Developer ID Application identity and `PROFILE_CURATOR_NOTARY_PROFILE` to a configured `notarytool` keychain profile for signed, notarized, stapled output.

## Test

```bash
swift test
```

## Private fixtures

Put real screenshots under `fixtures/private/`. That directory is ignored by Git. See [fixtures/README.md](fixtures/README.md) for the fixture taxonomy.

The source build specification was supplied at:

```text
/Users/chriswong/Downloads/hellotalk_profile_curator_codex_build_spec.md
```
