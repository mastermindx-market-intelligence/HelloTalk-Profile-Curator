# Risk register

| Risk | Failure mode | Current mitigation | Release gate |
|---|---|---|---|
| Social control activation | A broad or stale click lands on Say Hi, Follow, Like, Gift, or messaging UI | Input executor is not exposed in the production UI; normalized dynamic exclusion zones; one unresolved postcondition blocks the next event | 500-action stress run emits zero events inside exclusions; supervised activation remains required |
| Minor or wrong gender collected | Card OCR is wrong or stale | Re-verify age 18–21 and female indicator on the opened profile; reject missing/ambiguous values | Representative real fixtures plus supervised live checks |
| UI drift | Coordinates no longer match HelloTalk or iPhone Mirroring | OCR/visual anchors first, calibrated zones only as fallback, postconditions, resize rejection, pause on unknown state | Remaining ad, popup, and slow-load supervised fixtures |
| Wrong window | Capture or events target another app | Identify owning bundle/title/window ID; capture only selected window; revalidate frame before action | Disconnect/minimize/occlusion tests |
| Private images enter Git | Real fixtures or collected media are committed | Ignore `fixtures/private/`, media, diagnostics, database, and local config | Pre-commit privacy check and clean repository audit |
| Over-collection | More than 20 distinct candidates or 10 retained files | Persist counters and hashes transactionally after each item | Boundary and crash-resume tests |
| Duplicate people inferred by face | Cross-account identity is guessed | Username-only profile identity; perceptual hashes only for media | Code audit: no embedding/recognition APIs |
| Subjective model output overstated | Visual/lifestyle scores are shown as facts | Label as model estimates, retain evidence/confidence/prompt version, actual wealth always unknown | Dashboard copy and schema review |
| VLM unavailable or compromised | Collection blocks or data leaves intended network | Local offline queue; allowlist configured base URL; timeouts; user test connection | Offline/retry and endpoint-validation tests |
| Permission confusion | App appears broken after Screen Recording/Accessibility changes | Guided status UI, restart instructions, no action attempts without permission | Fresh-user onboarding test |
| Crash or restart | Duplicate or corrupted work | Transaction per profile/media, idempotent username/hash merge, atomic navigation checkpoint | Forced-quit and reboot supervised recovery test remains |
| User loses control | Automation continues unexpectedly | Always-visible Stop, keyboard stop, optional mouse-movement stop, action/profile caps | Emergency-stop latency test |
