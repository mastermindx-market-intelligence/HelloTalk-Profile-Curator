# Fixture library

Real profile screenshots belong only in `fixtures/private/`, which is ignored by Git. Before adding a fixture, redact unrelated notifications or account details that are not needed for the test.

Use these subfolders:

```text
fixtures/private/
├── profile_top/
├── personal_info/
├── suggestions/
├── moments_feed/
├── moment_photo_viewer/
├── pfp_viewer/
├── popups/
└── ads/
```

For each fixture, add a sibling JSON manifest when practical:

```json
{
  "expectedAnchors": ["Personal Info", "Suggested for You"],
  "expectedMBTI": "INFJ",
  "expectedAge": 21,
  "expectedScreenKind": "profilePersonalInfo",
  "expectedVisibleTargetAges": [21],
  "expectedVisibleTargetKeys": ["visible_card_name"],
  "expectedLocationCity": "Shenyang",
  "expectedNearbyCount": 576,
  "notes": "Long hobbies section; requires several vertical scrolls"
}
```

For an animated label, store each phase as a separate ignored image/manifest. Location-city and nearby-count expectations are deliberately separate so a transient count can never satisfy location validation.

Synthetic or fully anonymized regression fixtures may later be committed under `fixtures/synthetic/`.

Private manifests are replayed automatically by `PrivateFixtureReplayTests` when present. The test skips cleanly on machines that do not have the ignored private fixture library.

Visible target keys are normalized card names. Ages are optional because some rendered recommendation cards omit the age badge.
