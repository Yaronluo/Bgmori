#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-web-login.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
sources=(Bgmori/Core/Models/Models.swift Bgmori/Core/API/MirrorRouting.swift Bgmori/Core/API/ECHTransport.swift
 Bgmori/Core/API/APIClient.swift Bgmori/Core/API/APIError.swift Bgmori/Core/API/RateLimiter.swift
 Bgmori/Core/Storage/DiskCache.swift Bgmori/Core/Auth/BangumiWebLogin.swift tests/WebLoginTests.swift)
for platform in macosx iphonesimulator; do
 if [[ "$platform" == macosx ]]; then target=arm64-apple-macos27.0; else target=arm64-apple-ios27.0-simulator; fi
 flags=(-parse-as-library)
 if [[ "${1:-}" == --live ]]; then
  bash scripts/build-ech-library.sh "$platform"
  flags+=(-D BGMORI_ECH -import-objc-header Bgmori/Core/API/ECHBridge.h -L "build/ech/$platform" -lBgmoriECH -framework Security -framework CoreFoundation -lresolv)
 fi
 xcrun swiftc -swift-version 6 -parse-as-library -sdk "$(xcrun --sdk "$platform" --show-sdk-path)" -target "$target" \
  "${flags[@]}" "${sources[@]}" -o "$test_dir/$platform"
 if [[ "$platform" == macosx ]]; then "$test_dir/$platform" "$@"; else xcrun simctl spawn 'iPhone 17' "$test_dir/$platform" "$@"; fi
done
