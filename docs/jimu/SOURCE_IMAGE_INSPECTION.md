# W1 local source-image inspection

The existing Jimu Offline Inspector can now attach the original local source frame to an imported observation, display it, and recover it after database/model restart. This is a bounded W1 increment, not isolated visual calibration or live platform integration.

## User journey

Import an independently admitted observation and load its local inspection policy. Select **Attach source image…** and choose the original PNG or JPEG. Its SHA-256 must match the observation's existing `frame_sha256`; the application never changes that declaration to fit the chosen file. The native view displays the verified bytes and dimensions. The original observation and earlier judgments remain unchanged.

Only currently eligible explicit-age evidence permits image binding/display. Unknown, conflicting, manually corrected, or ineligible age stays held. Rights-scope admission remains the existing offline policy boundary. A byte match does not authenticate capture origin, person identity, or platform permission.

## Storage and failure behavior

The existing `MediaStore` owns the files under `media/jimu-sources/<observation-digest>/`; the existing GRDB migrator adds the observation-linked `jimu_source_media` relation. There is no second database or inference service. Files use owner-only permissions. Stored metadata is immutable and source reads recheck the declared hash before display.

The bounded reader accepts regular local files only, refuses symbolic links, and limits input to 8 MiB. Decoding accepts one PNG/JPEG frame, normal orientation, dimensions at most 8192 per axis and 16 million pixels. Unsupported orientation/format requires a separately evidenced normalized observation; no silent transformation is applied.

Wrong hashes, changed files, missing files, stale presentations, unsupported images, and storage errors are explicit failures. Repeated identical binding is idempotent. A bound but unavailable image cannot silently become a different image or an empty successful capture.

File creation and SQLite commit are not a single atomic transaction. A file left by interruption before row insertion is not displayed or labeled; a deliberate repeat binding can reconcile only matching bytes at the same deterministic path. Observation deletion also removes its managed folder, including that known-observation orphan. Cleanup failure keeps the observation visible for reconciliation. Interruption after file removal but before row deletion yields a missing-image state, not a false success. This is logical deletion, not forensic erasure of backups or storage media.

## Learning boundary

A full source frame may contain biography, age, and interface text. It is **not** isolated photo-only evidence. Visual-only feedback remains refused. Once an image is bound, new profile/action feedback is also refused with `source_image_label_presentation_pending`, preventing it from being mislabeled as the older `TEXT_EVIDENCE_ONLY_V1` presentation. Earlier text-only judgments remain unchanged and inspectable. Unbound text observations retain their existing feedback workflow.

Next W1 capability: isolated photo presentation with image-bound, scope-correct absolute/pairwise labels. Do not train a visual preference model from the text-only corpus or treat the new source preview as calibration completion.
