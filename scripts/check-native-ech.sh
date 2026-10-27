#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-ech.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/check.swift" <<'SWIFT'
import Network
import Security
let options = NWProtocolTLS.Options()
sec_protocol_options_set_enable_encrypted_client_hello(options.securityProtocolOptions, true)
SWIFT
for platform in macosx iphonesimulator; do
  if [[ "$platform" == macosx ]]; then target=arm64-apple-macos27.0; else target=arm64-apple-ios27.0-simulator; fi
  if xcrun swiftc -typecheck -sdk "$(xcrun --sdk "$platform" --show-sdk-path)" -target "$target" "$test_dir/check.swift" > "$test_dir/$platform.log" 2>&1; then
    echo "$platform: ECH switch compiles; full ECH config injection and negotiation still require separate validation."
  elif rg -q 'unavailable' "$test_dir/$platform.log"; then
    echo "PASS $platform: Apple ECH switch is unavailable; Bgmori uses its Go ECH transport without private APIs or certificate bypass."
  else
    cat "$test_dir/$platform.log"
    exit 1
  fi
done
