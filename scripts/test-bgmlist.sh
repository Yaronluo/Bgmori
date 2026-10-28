#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-bgmlist.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/API/MirrorRouting.swift
  Bgmori/Core/API/APIClient.swift Bgmori/Core/API/APIError.swift
  Bgmori/Core/API/RateLimiter.swift Bgmori/Core/Storage/DiskCache.swift tests/BgmlistTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/bgmlist-mac"
"$test_dir/bgmlist-mac" "$@"
xcrun swiftc -swift-version 6 -parse-as-library \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator "${sources[@]}" -o "$test_dir/bgmlist-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/bgmlist-ios" "$@"
