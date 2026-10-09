#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
bundle=${1:?Supply a dedicated local acceptance .app output path}
case "$bundle" in *.app) ;; *) echo 'Output must end in .app' >&2; exit 2 ;; esac
if [ -e "$bundle" ]; then echo 'Output already exists; preserve it and choose a fresh acceptance path' >&2; exit 2; fi
swift build >&2
binary_dir=$(swift build --show-bin-path)
mkdir -p "$bundle/Contents/MacOS"
# Reuse every existing app view; substitute only the test launch entry point.
set -- "$root/scripts/visual-agent-preview-main.swift"
for source in "$root"/Sources/ProfileCuratorApp/*.swift; do
  case "$source" in */ProfileCuratorApp.swift) continue ;; esac
  set -- "$@" "$source"
done
swiftc -swift-version 6 -DDEBUG -parse-as-library \
  -I "$binary_dir/Modules" -I "$root/.build/checkouts/GRDB.swift/Sources/GRDBSQLite" \
  "$@" "$binary_dir/ProfileCuratorCore.build/"*.o "$binary_dir/GRDB.build/"*.o \
  -lsqlite3 -o "$bundle/Contents/MacOS/ProfileCuratorPreview"
bundle_suffix=$(printf '%s' "$bundle" | shasum -a 256 | cut -c 1-12)
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ProfileCuratorPreview</string>
<key>CFBundleIdentifier</key><string>org.mastermind.ProfileCurator.offlineAcceptance.$bundle_suffix</string>
<key>CFBundleName</key><string>ProfileCuratorOfflinePreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle" >&2
codesign --verify --deep --strict "$bundle"
printf '%s\n' "$bundle"
