#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-cache.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/Models/CategoryModels.swift
  Bgmori/Core/Social/HTMLSupport.swift Bgmori/Core/API/MirrorRouting.swift Bgmori/Core/API/APIClient.swift
  Bgmori/Core/API/APIClient+Endpoints.swift Bgmori/Core/API/APIError.swift
  Bgmori/Core/API/RateLimiter.swift Bgmori/Core/Storage/DiskCache.swift
  Bgmori/Core/Storage/LibrarySnapshotStore.swift Bgmori/Core/Storage/LibraryStore.swift
  tests/CacheBehaviorTests.swift)
xcrun swiftc -swift-version 6 -parse-as-library "${sources[@]}" -o "$test_dir/cache-mac"
"$test_dir/cache-mac" "$@"
xcrun swiftc -swift-version 6 -parse-as-library \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios27.0-simulator \
  "${sources[@]}" -o "$test_dir/cache-ios"
xcrun simctl spawn 'iPhone 17' "$test_dir/cache-ios" "$@"
