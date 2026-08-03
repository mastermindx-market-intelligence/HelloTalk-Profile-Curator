# Risk register

| Risk | Failure mode | Current mitigation | Release gate |
|---|---|---|---|
| Social control activation | A broad or stale click lands on Say Hi, Follow, Like, Gift, or messaging UI | No input driver in phase 1; normalized exclusion zones; action preview; one action at a time | 500-action fixture/replay stress run with zero excluded intersections |
| Minor or wrong gender collected | Card OCR is wrong or stale | Re-verify age 18–21 and female indicator on the opened profile; reject missing/ambiguous values | Representative real fixtures plus supervised live checks |
| UI drift | Coordinates no longer match HelloTalk or iPhone Mirroring | OCR/visual anchors first, calibrated zones only as fallback, postconditions, pause on unknown state | Resize, ad, popup, and slow-load regression suite |
| Wrong window | Capture or events target another app | Identify owning bundle/title/window ID; capture only selected window; revalidate frame before action | Disconnect/minimize/occlusion tests |
| Private images enter Git | Real fixtures or collected media are committed | Ignore `fixtures/private/`, media, diagnostics, database, and local config | Pre-commit privacy check and clean repository audit |
| Over-collection | More than 20 distinct candidates or 10 retained files | Persist counters and hashes transactionally after each item | Boundary and crash-resume tests |
| Duplicate people inferred by face | Cross-account identity is guessed | Username-only profile identity; perceptual hashes only for media | Code audit: no embedding/recognition APIs |
| Subjective model output overstated | Visual/lifestyle scores are shown as facts | Label as model estimates, retain evidence/confidence/prompt version, actual wealth always unknown | Dashboard copy and schema review |
| VLM unavailable or compromised | Collection blocks or data leaves intended network | Local offline queue; allowlist configured base URL; timeouts; user test connection | Offline/retry and endpoint-validation tests |
| Permission confusion | App appears broken after Screen Recording/Accessibility changes | Guided status UI, restart instructions, no action attempts without permission | Fresh-user onboarding test |
| Crash or restart | Duplicate or corrupted work | Transaction per profile/media, idempotent merge, checkpoint after each retained asset | Forced-quit and reboot recovery tests |
| User loses control | Automation continues unexpectedly | Always-visible Stop, keyboard stop, optional mouse-movement stop, action/profile caps | Emergency-stop latency test |
