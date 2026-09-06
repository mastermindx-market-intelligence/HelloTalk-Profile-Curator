# W1 photo-only calibration

The existing native inspector now supports an offline calibration journey: attach a matching source image, confirm a photo-only region, judge that crop alone or in a pair, revise a judgment, and recover the original image/label history after reopening the database. This is manual preference labeling, not learned ranking or platform action.

## Use

Load an admitted observation and local policy, then attach the matching source PNG/JPEG. Under **Prepare a photo-only region**, drag over the image or enter X/Y/Width/Height in top-left source pixels. Confirm the region excludes profile text, captions and controls, then choose **Save photo region**. A changed region requires a fresh confirmation and appends a crop revision.

Use **Calibrate → Photo-only approve / reject** or **Photo-only pairwise comparison**. The calibration view replaces the inspector: it renders only the prepared crop(s), neutral A/B labels, progress and controls. Biography, profile identifiers, geography, model scores and scarce-action budgets are not rendered there. The current deck is a randomized, bounded set of prepared observations among the latest 200 observations; it is not active learning or a model-selected curriculum.

Single-photo choices are Approve/Reject. Pairwise choices are Prefer A/Prefer B/Tie/Neither. Keyboard shortcuts are 1–2 or 1–4 respectively. Space skips an unanswered item without making a label, or advances after a saved judgment. **Revise judgment** appends a superseding label. Escape or **Stop / Exit** clears the calibration presentation and returns to the inspector. Exhaustion or an unavailable image does not reveal the profile automatically.

The inspector history shows separate visual-only labels, exact crop/source/pixel references and their supersession history. **Revise photo judgment** opens a fresh presentation; previous records remain unchanged. Reopen the application/database and select the observation to review stored history; an active in-memory calibration sequence itself is not resumed automatically.

## Meaning of photo-only

`HUMAN_CONFIRMED_PHOTO_ONLY_V1` means the native view displays a human-confirmed region without surrounding profile UI. Confirmation is not automated semantic proof that no text appears inside the selected pixels. Known profile exposure in the current model session is recorded; otherwise earlier exposure remains unknown. The system does not claim to erase the user's memory or to establish identity, age, rights or capture origin through pixels.

Explicit age and local rights-scope checks are required before preparing or recording photo evidence. Manual age edits cannot establish eligibility. A source hash match proves local byte correspondence, not platform permission.

## Persistence and correction

The existing GRDB migrator adds `jimu_photo_crops`; source files remain in the existing MediaStore. Crop pixels are derived in memory, not copied to a second image corpus. Crops retain source SHA-256, pixel rectangle, RGBA8/sRGB raster digest, isolation method and prior-crop reference. Feedback remains in `preference_feedback` with an optional photo basis; old text-only records continue decoding with no photo basis.

Each judgment binds observation bytes, correction IDs, the complete policy, crop/source/pixel identities, rendering version and prior-context exposure. Submission checks the complete serialized basis, not just a caller-supplied revision string. A repeated identical submission is idempotent; a changed choice under the same submission identity conflicts. Revisions get a new presentation and supersede the earlier label. Ordered pairwise choices preserve both sides and require distinct observations in the same platform/account namespace.

Missing/corrupt source files, outdated crops or evidence, changed policies, invalid rectangles and incompatible choices fail before saving a judgment. Deleting an observation removes its managed source bytes and cascades crops and dependent pairwise labels. Logical deletion is not a claim of forensic backup erasure.

## Scope separation and remaining work

Text-only full-profile/action-context labeling still works for observations without bound source images. Those old labels never become visual labels. Image-bound full-profile and scarce-action labeling remain held until a complete combined-image/text presentation basis exists; this increment enables only the dedicated visual-only route. No Note, Instant, swipe, purchase, model call, training job or device capture is performed.

Current proof uses real native views, the application model and the existing database/media APIs with synthetic fixtures. It verifies database/model recreation, not an external mouse/keyboard walkthrough or separate full app-process relaunch. Human semantic crop confirmation and installed-app interaction still need supervised evidence. Independent review and W2 source-envelope conformance remain separate.

## Reproduce

```sh
swift test --jobs 1
JIMU_UI_PROOF_DIR=/tmp/jimu-photo-proof swift test --jobs 1 --filter 'JimuPhoto|JimuInspectorNativeViewTests'
swift build --product ProfileCurator --jobs 1
```

The next bounded W1 capability is an image-plus-text presentation for full-profile and separately contextual action labels, preserving the visual-only basis. W4 model training must consume compatible label scopes/presentation kinds, account for exposure and avoid treating historical downstream actions as visual preference labels.
