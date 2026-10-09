#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
swift build >&2
binary_dir=$(swift build --show-bin-path)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/visual-agent-simulation.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
for scenario in profile moments moments-scrolled advertisement unknown; do
  name=$scenario
  if [ "$scenario" = advertisement ]; then name=ad; fi
  swift scripts/generate-visual-agent-synthetic-fixture.swift "$scratch/$name.png" "$scenario" >&2
done
swiftc -swift-version 6 -parse-as-library \
  -I "$binary_dir/Modules" \
  -I "$root/.build/checkouts/GRDB.swift/Sources/GRDBSQLite" \
  "$root/scripts/visual-agent-simulate.swift" \
  "$binary_dir/ProfileCuratorCore.build/"*.o \
  "$binary_dir/GRDB.build/"*.o \
  -lsqlite3 -o "$scratch/simulate"
"$scratch/simulate" "$scratch" "$root/fixtures/synthetic/visual-agent-simulation-decisions.json"
