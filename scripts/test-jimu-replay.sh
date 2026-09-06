#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/jimu-replay-tests.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
mkdir -p "$BUILD/Sources/ProfileCuratorCore" "$BUILD/Tests/ProfileCuratorCoreTests"
cp "$ROOT/Sources/ProfileCuratorCore/Jimu/JimuReplay.swift" "$BUILD/Sources/ProfileCuratorCore/"
cp "$ROOT/Tests/ProfileCuratorCoreTests/JimuReplayTests.swift" "$BUILD/Tests/ProfileCuratorCoreTests/"
cat > "$BUILD/Package.swift" <<'SWIFT'
// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "JimuFocusedVerification", targets: [
    .target(name: "ProfileCuratorCore"),
    .testTarget(name: "ProfileCuratorCoreTests", dependencies: ["ProfileCuratorCore"])
])
SWIFT
# Temporary verification harness only. No second persistent product/package/database.
# On macOS also run the existing complete application's `swift test` separately.
swift test --package-path "$BUILD" --jobs 2
