#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-related-subjects.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift tests/RelatedSubjectTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/related-subjects-mac"
"$test_dir/related-subjects-mac"
xcrun swiftc -swift-version 6 -parse-as-library \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator "${sources[@]}" -o "$test_dir/related-subjects-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/related-subjects-ios"
