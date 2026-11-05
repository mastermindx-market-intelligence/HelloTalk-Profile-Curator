#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Executable on macOS or Linux; a narrow test only, not a substitute for `swift test` on the Mac.
swiftc -swift-version 6 -o "${TMPDIR:-/tmp}/visual-agent-offline-test-$$" \
  "$root/Sources/ProfileCuratorCore/Domain/Geometry.swift" \
  "$root/Sources/ProfileCuratorCore/Safety/ActionSafety.swift" \
  "$root/Sources/ProfileCuratorCore/Navigation/VisualAgentNavigation.swift" \
  "$root/Sources/ProfileCuratorCore/Navigation/VisualAgentInference.swift" \
  "$root/scripts/visual-agent-offline-smoke.swift"
"${TMPDIR:-/tmp}/visual-agent-offline-test-$$"
rm -f "${TMPDIR:-/tmp}/visual-agent-offline-test-$$"
