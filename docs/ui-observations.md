# Supervised UI observations

Status: **not yet observed**. Populate this file only while the user is present and iPhone Mirroring is visible.

## Capture metadata

- macOS version:
- iPhone model / iOS version:
- HelloTalk version:
- iPhone Mirroring window content size:
- display scale:
- date observed:

## Normalized safe regions

All coordinates use top-left origin and normalized `0...1` values relative to the current mirrored content rect.

| Region | x | y | width | height | Evidence / notes |
|---|---:|---:|---:|---:|---|
| Avatar | | | | | |
| About Me tab | | | | | |
| Moments tab | | | | | |
| Recommendation card body | | | | | Must exclude Say Hi |
| Carousel gesture zone | | | | | |
| Back/close | | | | | |
| Profile-header anchor | | | | | |

## Never-click regions

| Control | Normalized rectangle | Detection anchor | Notes |
|---|---|---|---|
| Say Hi | | | |
| Follow | | | |
| Like | | | |
| Gift | | | |
| Message composer | | | |
| Ad controls | | | |

## Interaction measurements

- One moderate vertical wheel/drag:
- Verified top-jump mechanism:
- Open/close avatar flow:
- Open/close Moment viewer flow:
- Multi-photo swipe behavior:
- Return from Moments to About Me:
- Carousel horizontal drag behavior:
- Safe recommendation-card click target:
- Reliable profile-changed postcondition:
- Popup/ad recovery observations:

## Evidence index

Do not commit real screenshots. Reference ignored files under `fixtures/private/` by local relative path and record a short explanation here.
