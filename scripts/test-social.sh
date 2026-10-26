#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-social.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Bgmori/Core/Models/Models.swift \
  Bgmori/Core/Models/CategoryModels.swift \
  Bgmori/Core/Social/HTMLSupport.swift \
  Bgmori/Core/Social/SocialModels.swift \
  Bgmori/Core/Social/SocialService.swift \
  Bgmori/Core/API/APIClient.swift \
  Bgmori/Core/API/APIClient+Endpoints.swift \
  Bgmori/Core/API/APIError.swift \
  Bgmori/Core/API/RateLimiter.swift \
  Bgmori/Core/Storage/DiskCache.swift \
  tests/SocialTests.swift -o "$test_dir/social"
"$test_dir/social" "$@"
