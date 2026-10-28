#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-all}
case "$mode" in all|ios|mac) ;; *) echo 'Usage: test-shell-ui.sh [all|ios|mac] [testName ...]'; exit 2 ;; esac
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-shell-ui.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
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
result_args=()
if [[ -n "${BGMORI_UI_RESULT_DIR:-}" ]]; then mkdir -p "$BGMORI_UI_RESULT_DIR"; fi
if [[ "$mode" != mac ]]; then
  if [[ -n "${BGMORI_UI_RESULT_DIR:-}" ]]; then result_args=(-resultBundlePath "$BGMORI_UI_RESULT_DIR/ios.xcresult"); fi
  xcodebuild "${args[@]}" "${result_args[@]}" -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath "$test_dir/ios" CODE_SIGNING_ALLOWED=NO test
fi
if [[ "$mode" != ios ]]; then
  if [[ -n "${BGMORI_UI_RESULT_DIR:-}" ]]; then result_args=(-resultBundlePath "$BGMORI_UI_RESULT_DIR/mac.xcresult"); fi
  xcodebuild "${args[@]}" "${result_args[@]}" -destination 'platform=macOS,arch=arm64' -derivedDataPath "$test_dir/mac" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
fi
