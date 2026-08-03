# Supervised UI observations

Status: **first supervised pass completed**. No Follow, Say Hi, Like, Gift, message, bookmark, or other social control was activated.

## Capture metadata

- macOS version: 26.5 (25F71)
- iPhone model / iOS version: not yet recorded
- HelloTalk version: not yet recorded
- iPhone Mirroring captured window: 420 × 932 logical pixels in the Computer Use screenshot
- inner rounded iPhone content: approximately x=8, y=42, width=400, height=870
- display scale: logical screenshot scale; ScreenCaptureKit pixel scale still to be measured
- date observed: 2026-08-03, user supervised

## Normalized safe regions

All coordinates use top-left origin and normalized `0...1` values relative to the complete 420 × 932 captured iPhone Mirroring window. These are fallback regions, not permission to act without visual anchors and postconditions.

| Region | x | y | width | height | Evidence / notes |
|---|---:|---:|---:|---:|---|
| Connect-card avatar | 0.057 | 0.258 | 0.160 | 0.077 | First visible Connect card; y varies by card |
| Profile avatar | 0.057 | 0.258 | 0.171 | 0.077 | Opened PFP viewer successfully |
| About Me tab | 0.057 | 0.547 | 0.293 | 0.038 | Returned from Moments successfully |
| Moments tab | 0.350 | 0.547 | 0.298 | 0.038 | Opened the Moment grid successfully |
| Recommendation card body | partially observed | | | | Horizontal Suggested for You cards appeared below Hometown on the age-18 INTP profile; exact safe body geometry remains uncalibrated |
| Carousel gesture zone | partially observed | | | | Horizontal inventory is confirmed; a repeatable automated gesture and its postcondition remain unverified |
| Back/close | 0.057 | 0.103 | 0.062 | 0.040 | Profile/PFP/Moment upper-left control |
| Profile-header anchor | 0.057 | 0.258 | 0.881 | 0.172 | Name, age/gender, handle, language, counts |

## Never-click regions

| Control | Normalized rectangle | Detection anchor | Notes |
|---|---|---|---|
| Say Hi | x=0.440, y=0.890, w=0.362, h=0.057 | Fixed profile bottom bar | Present on About Me and Moments |
| Follow | x=0.057, y=0.890, w=0.366, h=0.057 | Fixed profile bottom bar | Present on About Me and Moments |
| Gift | x=0.823, y=0.890, w=0.114, h=0.057 | Fixed profile bottom bar | Pink circular control |
| Connect wave/Say Hi | right side of every Connect card | Purple waving-hand button | Must be detected per card; y is not fixed |
| PFP Like | x=0.714, y=0.108, w=0.088, h=0.045 | Thumb icon | Viewer upper right |
| PFP Gift | x=0.845, y=0.108, w=0.093, h=0.045 | Gift icon | Viewer upper right |
| PFP extra actions | x=0.057, y=0.662, w=0.881, h=0.125 | AI Photo Gift / Avatar Effect | Treat both rows as excluded |
| Moment viewer actions | x=0.057, y=0.890, w=0.881, h=0.072 | Like, Comment, AI, Bookmark, More | Exclude entire bottom action row |
| Message composer | not present in inspected profile flow | | Chat list was deliberately not inspected |
| Ad controls | uncalibrated | | An ad appeared in Connect feed; no interaction |

## Interaction measurements

- One standard window-targeted downward scroll: exposes the next profile block; three scrolls reached a stable bottom on the observed short profile.
- Verified top-jump mechanism: tap the iOS time/status-bar area at full-window point approximately (0.145, 0.075); returned from the bottom to map/header top.
- Open/close avatar flow: tap profile avatar; viewer has `×` upper left, Like/Gift upper right, and two excluded action rows below the image. Visible `×` closed reliably.
- Second PFP validation on an age-26 routing-only profile confirmed photo pixels at approximately y=0.19...0.62 of the complete Mirroring window; AI Photo Gift begins around y=0.66. The crop must start below the black header rather than at the window top.
- Open/close Moment viewer flow: tap a photo thumbnail; `×` appears upper left while chrome is visible. When chrome hides, tap the black background once, wait briefly for `×`, then close within its roughly three-second visibility window.
- A single-image `LIVE` Moment without a `1/N` counter was observed. The viewer is identifiable from LIVE plus bottom Like/AI chrome, and the photo band occupied approximately y=0.22...0.79. The Moments feed itself exposed `Moments 11`, `96 Like`, and `3 Comment` anchors above the first safe image tile.
- Video and Live Photo posts use the same still-frame path as static posts: wait for a stable visible frame, capture it through the Mac mirroring window, crop and perceptually deduplicate it, then persist PNG only. Never download or store the underlying video/Live Photo asset.
- Multi-photo swipe behavior: unresolved. Both Computer Use horizontal scroll directions left the first pagination dot active and hid viewer chrome. Do not automate until a supervised gesture is confirmed.
- Return from Moments to About Me: direct About Me tab click succeeded.
- Carousel horizontal inventory: cards are visible, but horizontal motion is unavailable in the current iPhone Mirroring session. Manual click-drag produced no movement; a Computer Use horizontal scroll shifted the entire profile sheet instead of the row and was immediately reversed. Keep horizontal gestures disabled.
- Vertical input distinction: manual touch-style drag also does not move the profile, while discrete keyboard/scroll events work reliably. Use only discrete vertical scroll events.
- Verified traversal fallback: safely clicking Mia's visible profile photo changed identity from the current profile to `@e_mia760`; Mia's profile exposed a fresh Suggested for You row containing Camilla (female 27) and Tonia (female 22). Both were rejected for collection. This validates visible-card graph traversal without carousel motion.
- Safe recommendation-card click target: avatar center on the far left of a Connect row opened the profile and remained far from the purple wave/Say Hi control.
- Reliable profile-changed postcondition: the profile side sheet first appeared, then the full profile exposed name, handle, age/gender badge, map, and tabs.
- Popup/ad recovery observations: a Wise ad row appeared in Connect; it was not clicked. Ads must be skipped as whole-card exclusion regions.
- Important UI drift: one observed profile bottom stabilized after School with no Suggested for You row, while another exposed the gallery below Hometown. Navigation must support returning to a seed feed when the gallery is absent.
- Discovery priority correction from the user: Custom Search shows only currently active users and is materially smaller. Use it to acquire a seed, then prefer the in-profile horizontal Suggested for You gallery for broader recently-active inventory.
- Similarity behavior: a gallery reached from a female profile usually shows female profiles, but this is a prior only; verify the badge on every opened profile.
- Custom Search age filter: 18–21 can be applied and produces a dedicated feed, but result rows omit exact age and gender.
- Custom Search Female filter: selecting Female opened a subscription purchase modal; it was closed without purchase. Runtime must not depend on this filter.
- Real target path: an age-18 female INTP profile required scrolling through a long hobbies section before Personal Info. Its enlarged PFP produced a clear face candidate.
- Suggested for You on that target: appeared below Hometown after several scrolls; two visible cards both showed female badges, and the first showed age 22. The fixed current-profile Follow/Say Hi/Gift bar remained over the lower screen.
- Map badge animation: the same pill alternates every 1–2 seconds between `Shenyang, China 6:58pm` and `576 People Nearby`. Location extraction must sample multiple frames, ignore People Nearby counts, and retain the city/country/time phase.

## Evidence index

Do not commit real screenshots. Reference ignored files under `fixtures/private/` by local relative path and record a short explanation here.

- `moments_feed/age25_profile_moments.png` — non-eligible age-25 profile used only to map Moments layout.
- `personal_info/age25_infp_personal_info.png` — Personal Info and exact INFP tile.
- `suggestions/profile_bottom_no_suggestions.png` — stable profile bottom demonstrating the missing recommendation row.
- `pfp_viewer/single_pfp_viewer_with_actions.png` — enlarged PFP plus Like/Gift/AI exclusions.
- `moment_photo_viewer/multi_image_1_of_6.png` — six-photo viewer with action row and first dot active.
- `personal_info/age18_intp_long_hobbies.png` — age-18 female secondary target with long hobbies before exact INTP.
- `pfp_viewer/age18_intp_clear_stylized_face.png` — clear but stylized PFP face for the secondary no-face path.
- `suggestions/age18_intp_horizontal_gallery.png` — broader in-profile similar-user inventory with female/age badges.
- `profile_top/rotating_badge_shenyang.png` and `rotating_badge_people_nearby.png` — paired temporal-location fixtures supplied by the user.
