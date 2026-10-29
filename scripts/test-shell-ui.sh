#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-all}
case "$mode" in all|ios|mac) ;; *) echo 'Usage: test-shell-ui.sh [all|ios|mac] [testName ...]'; exit 2 ;; esac
python3 scripts/maintain-dev-storage.py --apply
mkdir -p build/tmp build/ui-results
result_root="$PWD/build/ui-results"
if [[ -n "${BGMORI_UI_RESULT_DIR:-}" ]]; then
  # Only newly created direct children of the managed root may be expired later.
  result_dir=$(python3 - "$result_root" "$BGMORI_UI_RESULT_DIR" <<'PY'
import sys
from pathlib import Path
root, path = map(lambda s: Path(s).absolute(), sys.argv[1:])
if path.parent != root or path.exists() or path.is_symlink() or root.resolve() != root:
    raise SystemExit('BGMORI_UI_RESULT_DIR must be a new direct child of build/ui-results/')
path.mkdir()
print(path)
PY
  )
else
  result_dir=$(mktemp -d "$result_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
fi
touch "$result_dir/.bgmori-ui-run"
echo "$$" > "$result_dir/.active"
test_dir=$(mktemp -d "$PWD/build/tmp/bgmori-shell-ui.XXXXXX")
touch "$test_dir/.bgmori-temporary"
echo "$$" > "$test_dir/.active"
cleanup() {
  status=$?
  rm -rf "$test_dir"
  rm -f "$result_dir/.active"
  python3 scripts/maintain-dev-storage.py --apply || { [[ $status -ne 0 ]] || status=1; }
  [[ ! -d "$result_dir" ]] || echo "UI 测试报告：${result_dir}（最多 3 次 / 1 GiB / 7 天）"
  exit "$status"
}
trap cleanup EXIT
# Build a snapshot in a temporary project; preserve the checkout's Xcode signing settings.
ditto Bgmori "$test_dir/Bgmori"
ditto Native "$test_dir/Native"
mkdir -p "$test_dir/scripts"
cp scripts/build-ech-library.sh "$test_dir/scripts/build-ech-library.sh"
cp tests/ShellUITests.swift "$test_dir/ShellUITests.swift"
ruby -ryaml -rjson -e '
  spec = YAML.load_file(ARGV[0])
  spec["name"] = "BgmoriShellVerification"
  target = spec["targets"]["Bgmori"]
  target.delete("info")
  spec["targets"]["ShellUITests"] = {
    "type" => "bundle.ui-testing", "platform" => "auto", "supportedDestinations" => ["iOS", "macOS"],
    "sources" => [{"path" => "ShellUITests.swift"}], "dependencies" => [{"target" => "Bgmori"}],
    "settings" => {"base" => {"PRODUCT_BUNDLE_IDENTIFIER" => "com.yaron.bgmori.ShellUITests",
      "GENERATE_INFOPLIST_FILE" => true, "CODE_SIGN_IDENTITY" => "-", "CODE_SIGN_STYLE" => "Automatic"}}
  }
  spec["schemes"]["Bgmori"]["test"]["targets"] = ["ShellUITests"]
  File.write(ARGV[1], JSON.pretty_generate(spec))
' project.yml "$test_dir/project.json"
xcodegen generate --spec "$test_dir/project.json" --project "$test_dir"
args=(-project "$test_dir/BgmoriShellVerification.xcodeproj" -scheme Bgmori -configuration Debug -parallel-testing-enabled NO)
for test_name in "${@:2}"; do
  args+=("-only-testing:ShellUITests/ShellUITests/$test_name")
done
if [[ "$mode" != mac ]]; then
  xcodebuild "${args[@]}" -resultBundlePath "$result_dir/ios.xcresult" -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath "$test_dir/ios" CODE_SIGNING_ALLOWED=NO test
fi
if [[ "$mode" != ios ]]; then
  xcodebuild "${args[@]}" -resultBundlePath "$result_dir/mac.xcresult" -destination 'platform=macOS,arch=arm64' -derivedDataPath "$test_dir/mac" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
fi
