#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-infobox-links.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/Models/InfoboxLinks.swift tests/InfoboxLinkTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/links-mac"
"$test_dir/links-mac" "$@"
xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator "${sources[@]}" -o "$test_dir/links-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/links-ios" "$@"
