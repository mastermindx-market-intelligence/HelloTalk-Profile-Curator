# HelloTalk Profile Curator

Private, local-first macOS collector for a visible iPhone Mirroring window. The shipped app separates automatic collection from manual inspection and calibration:

1. offline screenshot replay and parsing;
2. read-only Inspector and calibration;
3. dry-run navigation previews with explicit exclusion zones;
4. automatic, postcondition-checked navigation;
5. collection, review, and optional local-network analysis.

The app must never send messages, follow, like, gift, press **Say Hi**, or invoke an iPhone screenshot action. It only accepts adult female profiles with an explicitly displayed age of 18–21 and never uses face recognition or face embeddings.

## Current slice

The current local build includes an Inspector, persistence layer, review dashboard, deterministic runtime core, and an optional offline-first analysis boundary. It can:

- start, pause, resume, and emergency-stop an automatic collection session from the app toolbar;
- automatically attach to iPhone Mirroring, traverse profile pages, verify eligibility, capture media, queue Qwen, and continue through visible similar-profile cards;

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
- preview intended actions and never-click regions while automatic input remains gated behind the explicit Start control;
- draw and save normalized calibration regions over a fixture or captured frame.
- accumulate eligibility evidence across captured frames for one verified username and checkpoint only female, age-18–21 primary/secondary target profiles;
- merge profiles by normalized username in SQLite and store Mac-rendered frames with perceptual-hash deduplication;
- enforce 20-scanned/10-retained media planning and mandatory secondary no-face rejection;
- resume deterministic navigation from an atomic local checkpoint and pause on window resize, timeouts, unknown screens, or unresolved postconditions;
- browse a local review grid with primary, secondary, high-priority, shortlist, contacted, and rejected sections;
- apply database-backed search, age, city, score, confidence, usable-face, status/group, sorting, and 20/50/100-row pagination;
- edit notes/status, inspect retained media, export CSV/JSON, delete profile media, or delete all collected data;
- configure and test an optional Ollama/Qwen endpoint over Tailscale, with fixed JSON prompts, timeouts, bounded retry, a persistent offline queue, and automatic queue resumption when collection starts.
- recognize PFP/Moment viewers, crop the photo region above known UI controls, ignore perceptual duplicates, enforce 20/10 counters, finalize the no-face rule, and enqueue only media-backed analysis jobs.
- treat static posts, videos, and Live Photos uniformly as visible still-image sources: capture one stabilized Mac-rendered frame, store it as PNG, and never download or retain motion media.
- traverse both three-column Moment galleries and dated vertical Moment timelines, avoid ad/social controls, capture still frames from photos, videos, and Live Photos, and use a letterbox-safe downward dismiss gesture; broken in-viewer horizontal swipes remain disabled.

The app defaults to an idle, no-input state. **Start Automatic** is the explicit live-input gate; every click, scroll, and viewer-dismiss gesture is geometry-checked, audited, and locked until a captured postcondition verifies the result. Unknown states, window changes, failed postconditions, and session limits pause safely. The experimental horizontal gallery path remains disabled after supervised mirroring validation showed that horizontal drag/scroll does not move the carousel, so discovery uses bounded visible-card profile hopping instead.

The live VLM default is `qwen3.5:9b`: a 6.6 GB multimodal Ollama build running fully on the Windows RTX 5070 Ti 16 GB. Ollama remains bound to Windows localhost and is exposed only through a private Tailscale TCP Serve route; the Mac stores that tailnet endpoint in its ignored local configuration. Larger 27B-class packages exceed comfortable all-GPU operation on this card. Analysis requests disable the model's optional reasoning trace and require non-streaming JSON, keeping stored results compact and deterministic.

Navigation audit logs are written locally under `~/Library/Application Support/ProfileCurator/navigation-logs/`. They contain state and safety metadata, not screenshot pixels.

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

Ad-hoc local builds embed a stable designated requirement for `local.profilecurator.app`, so macOS Screen Recording and Accessibility grants survive ordinary rebuilds. Switching between older builds signed without that requirement and current builds requires resetting and granting those two permissions once.

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
