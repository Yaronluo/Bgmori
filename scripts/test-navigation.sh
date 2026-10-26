#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-navigation.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/API/MirrorRouting.swift Bgmori/App/AppRouter.swift tests/NavigationTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/navigation-mac"
"$test_dir/navigation-mac"
xcrun swiftc -swift-version 6 -parse-as-library \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator \
  "${sources[@]}" -o "$test_dir/navigation-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/navigation-ios"
