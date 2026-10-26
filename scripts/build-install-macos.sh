#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

installed_app=/Applications/Bgmori.app
task_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-install.XXXXXX")
stage_dir=""
backup_app=""
cleanup() {
  if [[ ! -d "$installed_app" && -n "$backup_app" && -d "$backup_app" ]]; then
    /usr/bin/ditto "$backup_app" "$installed_app"
  fi
  [[ -z "$stage_dir" ]] || rm -rf "$stage_dir"
  rm -rf "$task_dir"
}
trap cleanup EXIT

build_args=(-project Bgmori.xcodeproj -scheme Bgmori -configuration Debug
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
if ! xcodebuild "${build_args[@]}" build > "$task_dir/build.log" 2>&1; then
  tail -80 "$task_dir/build.log"
  exit 1
fi
xcodebuild "${build_args[@]}" -showBuildSettings -json > "$task_dir/settings.json"
built_app=$(/usr/bin/plutil -extract 0.buildSettings.TARGET_BUILD_DIR raw "$task_dir/settings.json")/Bgmori.app
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")" == com.yaron.bgmori ]]
codesign --verify --deep --strict "$built_app"

stage_dir=$(mktemp -d /Applications/.bgmori-install.XXXXXX)
/usr/bin/ditto "$built_app" "$stage_dir/Bgmori.app"
codesign --verify --deep --strict "$stage_dir/Bgmori.app"

/usr/bin/osascript -e 'if application "/Applications/Bgmori.app" is running then tell application "/Applications/Bgmori.app" to quit'
for ((attempt=0; attempt<30; attempt++)); do
  if ! pgrep -f '^/Applications/Bgmori[.]app/Contents/MacOS/Bgmori( |$)' > /dev/null; then break; fi
  sleep 0.2
done
if pgrep -f '^/Applications/Bgmori[.]app/Contents/MacOS/Bgmori( |$)' > /dev/null; then
  echo "Bgmori 尚未退出，安装已停止。"
  exit 1
fi

if [[ -d "$installed_app" ]]; then
  backup_root="$HOME/Library/Application Support/Bgmori/BuildBackups"
  mkdir -p "$backup_root"
  backup_dir=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
  backup_app="$backup_dir/Bgmori.app"
  mv "$installed_app" "$backup_app"
fi
mv "$stage_dir/Bgmori.app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
diff -qr "$built_app" "$installed_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_app"
open "$installed_app"
echo "已构建、安装并打开：$installed_app"
[[ -z "$backup_app" ]] || echo "旧应用备份：$backup_app"
