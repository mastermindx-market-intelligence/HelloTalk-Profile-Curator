#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"
bundle_dir="$dist_dir/Profile Curator.app"
dmg_path="$dist_dir/Profile-Curator.dmg"
signing_identity="${PROFILE_CURATOR_SIGN_IDENTITY:--}"

cd "$project_dir"
swift build -c release --product ProfileCurator

staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
staged_bundle="$staging_dir/Profile Curator.app"
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$project_dir/.build/release/ProfileCurator" "$staged_bundle/Contents/MacOS/ProfileCurator"
cp "$project_dir/Packaging/Info.plist" "$staged_bundle/Contents/Info.plist"

if [[ "$signing_identity" == "-" ]]; then
  timestamp_option="--timestamp=none"
  requirements_options=(--requirements '=designated => identifier "local.profilecurator.app"')
else
  timestamp_option="--timestamp"
  requirements_options=()
fi
codesign --force --sign "$signing_identity" --options runtime "$timestamp_option" \
  "${requirements_options[@]}" \
  --entitlements "$project_dir/Packaging/ProfileCurator.entitlements" "$staged_bundle"
codesign --verify --deep --strict --verbose=2 "$staged_bundle"

mkdir -p "$dist_dir"
ditto "$staged_bundle" "$bundle_dir"
rm -f "$dmg_path"
hdiutil create -quiet -volname "Profile Curator" -srcfolder "$staged_bundle" -ov -format UDZO "$dmg_path"
codesign --force --sign "$signing_identity" "$timestamp_option" "$dmg_path"

if [[ -n "${PROFILE_CURATOR_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg_path" --keychain-profile "$PROFILE_CURATOR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$bundle_dir"
  xcrun stapler staple "$dmg_path"
fi

echo "$bundle_dir"
echo "$dmg_path"
