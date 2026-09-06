#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/jimu-replay.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
swiftc -swift-version 6 "$ROOT/Sources/ProfileCuratorCore/Jimu/JimuReplay.swift" "$ROOT/scripts/jimu/main.swift" -o "$BUILD/jimu-replay"
"$BUILD/jimu-replay" "$@"
