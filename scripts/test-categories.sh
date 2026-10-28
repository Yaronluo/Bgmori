#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-categories.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Bgmori/Core/Models/Models.swift \
  Bgmori/Core/Models/CategoryModels.swift \
  Bgmori/Core/Social/HTMLSupport.swift \
  Bgmori/Core/API/MirrorRouting.swift Bgmori/Core/API/APIClient.swift \
  Bgmori/Core/API/APIClient+Endpoints.swift \
  Bgmori/Core/API/APIError.swift \
  Bgmori/Core/API/RateLimiter.swift \
  Bgmori/Core/Storage/DiskCache.swift \
  Bgmori/Core/Storage/CategoryStore.swift Bgmori/Core/Storage/TagResultsStore.swift \
  Bgmori/App/AppRouter.swift \
  tests/CategoryTests.swift -o "$test_dir/categories"
"$test_dir/categories" "$@"
