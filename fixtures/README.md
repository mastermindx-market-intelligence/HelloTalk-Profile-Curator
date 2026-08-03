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
  "notes": "Long hobbies section; requires several vertical scrolls"
}
```

Synthetic or fully anonymized regression fixtures may later be committed under `fixtures/synthetic/`.
