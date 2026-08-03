# HelloTalk Profile Curator

Private, local-first macOS tooling for supervised inspection of an iPhone Mirroring window. The project is intentionally being built in this order:

1. offline screenshot replay and parsing;
2. read-only Inspector and calibration;
3. dry-run navigation previews with explicit exclusion zones;
4. supervised, postcondition-checked navigation;
5. collection, review, and optional local-network analysis.

The app must never send messages, follow, like, gift, press **Say Hi**, or invoke an iPhone screenshot action. It only accepts adult female profiles with an explicitly displayed age of 18–21 and never uses face recognition or face embeddings.

## Current slice

The first slice is an offline Inspector. It can:

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
- show Screen Recording and Accessibility permission status;
- preview intended action and never-click regions without executing input;
- draw and save normalized calibration regions over a fixture or captured frame.

No live input events are generated in this phase.

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
