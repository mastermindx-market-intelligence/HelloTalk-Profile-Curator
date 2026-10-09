#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary="/tmp/visual-agent-replay-test-$$"
trap 'rm -f "$binary"' EXIT HUP INT TERM
swiftc -swift-version 6 -o "$binary" \
  "$root/Sources/ProfileCuratorCore/Domain/Geometry.swift" \
  "$root/Sources/ProfileCuratorCore/Safety/ActionSafety.swift" \
  "$root/Sources/ProfileCuratorCore/Navigation/VisualAgentNavigation.swift" \
  "$root/Sources/ProfileCuratorCore/Navigation/VisualAgentInference.swift" \
  "$root/Sources/ProfileCuratorCore/Navigation/VisualAgentReplayBenchmark.swift" \
  "$root/scripts/visual-agent-replay-evaluate.swift"
"$binary" --self-test
"$binary" "$root/fixtures/synthetic/visual-agent-replay-cases.json" \
  "$root/fixtures/synthetic/visual-agent-replay-trials.json"
