#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
bundle_dir="$project_dir/dist/Profile Curator.app"

cd "$project_dir"
swift build --product ProfileCurator

mkdir -p "$bundle_dir/Contents/MacOS"
mkdir -p "$bundle_dir/Contents/Resources"
cp "$project_dir/.build/debug/ProfileCurator" "$bundle_dir/Contents/MacOS/ProfileCurator"
cp "$project_dir/Packaging/Info.plist" "$bundle_dir/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$bundle_dir"
echo "$bundle_dir"
