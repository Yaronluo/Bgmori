#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
platform=${1:-${PLATFORM_NAME:-macosx}}
case "$platform" in macosx|iphonesimulator|iphoneos) ;; *) echo "Unsupported ECH platform: $platform"; exit 1 ;; esac
if command -v go >/dev/null 2>&1; then go_bin=$(command -v go); elif [[ -x /opt/homebrew/bin/go ]]; then go_bin=/opt/homebrew/bin/go; else echo 'ECH build requires Go 1.27 or newer.'; exit 1; fi
output_dir="$repo_dir/build/ech/$platform"
mkdir -p "$output_dir"
version=$($go_bin version)
input_hash=$(cat "$repo_dir/Native/ECH/main.go" "$repo_dir/Native/ECH/go.mod" "$0" | shasum -a 256 | cut -d ' ' -f 1)
stamp="$input_hash|$version|$(xcrun --sdk "$platform" --show-sdk-version)"
if [[ -f "$output_dir/stamp" && -f "$output_dir/libBgmoriECH.a" && "$(cat "$output_dir/stamp")" == "$stamp" ]]; then exit 0; fi
sdk_path=$(xcrun --sdk "$platform" --show-sdk-path)
clang_path=$(xcrun --find clang)
case "$platform" in
 macosx) go_os=darwin; target=arm64-apple-macos27.0 ;;
 iphonesimulator) go_os=ios; target=arm64-apple-ios27.0-simulator ;;
 iphoneos) go_os=ios; target=arm64-apple-ios27.0 ;;
esac
cat > "$output_dir/clang-wrapper.sh" <<EOF
#!/bin/bash
exec "$clang_path" -target "$target" -isysroot "$sdk_path" "\$@"
EOF
chmod +x "$output_dir/clang-wrapper.sh"
cd "$repo_dir/Native/ECH"
GOTOOLCHAIN=local CGO_ENABLED=1 GOOS="$go_os" GOARCH=arm64 CC="$output_dir/clang-wrapper.sh" \
 "$go_bin" build -trimpath -buildvcs=false -buildmode=c-archive -ldflags='-s -w' -o "$output_dir/libBgmoriECH.a" .
printf '%s' "$stamp" > "$output_dir/stamp"
echo "Built ECH static library: $platform"
