#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-ech-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/Models/Notice.swift Bgmori/Core/API/MirrorRouting.swift Bgmori/Core/API/ECHTransport.swift
 Bgmori/Core/API/APIClient.swift Bgmori/Core/API/APIError.swift Bgmori/Core/API/RateLimiter.swift
 Bgmori/Core/Storage/DiskCache.swift Bgmori/Core/Storage/ImageLoader.swift tests/ECHTests.swift)
for platform in macosx iphonesimulator; do
 bash scripts/build-ech-library.sh "$platform"
 if [[ "$platform" == macosx ]]; then target=arm64-apple-macos27.0; else target=arm64-apple-ios27.0-simulator; fi
 xcrun swiftc -swift-version 6 -D BGMORI_ECH -parse-as-library -import-objc-header Bgmori/Core/API/ECHBridge.h \
  -sdk "$(xcrun --sdk "$platform" --show-sdk-path)" -target "$target" "${sources[@]}" \
  -L "build/ech/$platform" -lBgmoriECH -framework Security -framework CoreFoundation -lresolv -o "$test_dir/$platform"
 if [[ "$platform" == macosx ]]; then "$test_dir/$platform" "$@"; else xcrun simctl spawn 'iPhone 17' "$test_dir/$platform" "$@"; fi
done
