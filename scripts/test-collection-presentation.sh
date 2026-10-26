#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-collection-presentation.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift tests/CollectionPresentationTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/collection-mac"
"$test_dir/collection-mac"
xcrun --sdk iphonesimulator swiftc -swift-version 6 -parse-as-library \
  -target arm64-apple-ios27.0-simulator "${sources[@]}" -o "$test_dir/collection-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/collection-ios"
