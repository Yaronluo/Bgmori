#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/maintain-dev-storage.py --apply
mkdir -p build/ui-results
result_dir=$(mktemp -d "$PWD/build/ui-results/$(date +%Y%m%d-%H%M%S).glass-restore.XXXXXX")
touch "$result_dir/.bgmori-ui-run"
echo "$$" > "$result_dir/.active"
cleanup() {
  status=$?
  rm -f "$result_dir/.active"
  python3 scripts/maintain-dev-storage.py --apply || { [[ $status -ne 0 ]] || status=1; }
  echo "Window restoration report: $result_dir"
  exit "$status"
}
trap cleanup EXIT
swift tests/GlassWindowRestoreTests.swift "$result_dir"
