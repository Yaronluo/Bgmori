#!/bin/bash
# 构建 → 安装 → 启动 iPhone 17 模拟器上的 Debug 版本，并校验装进去的就是本次构建。
#
# 为什么不从 ~/Library/Developer/Xcode/DerivedData 里找安装包：
# DerivedData 目录名取决于工程的绝对路径，每个 checkout / git worktree 都是独立的一份。
# 而所有 checkout 的 Bundle ID 都是 com.yaron.bgmori，用 `find ... | head -1` 猜路径时
# 经常命中主工作树（或更早一次）的产物，于是“编译了新代码、装进模拟器的却是旧 App”。
# 因此这里把 DerivedData 固定在当前 checkout 的 build/DerivedData-ios，构建完用哈希校验。
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"

device=${BGMORI_SIM_DEVICE:-"iPhone 17"}
route=""
screenshot=""
launch=1

usage() {
  cat <<'EOF'
用法: bash scripts/build-install-ios.sh [选项]
  --device <名称>     模拟器名称，默认 iPhone 17
  --route <路由>      启动时注入 BGMORI_ROUTE（如 subject:8、settings、login）
  --screenshot <路径> 启动后截图到指定文件
  --no-launch         只构建并安装，不启动
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) device=${2:?缺少设备名}; shift 2 ;;
    --route) route=${2:?缺少路由}; shift 2 ;;
    --screenshot) screenshot=${2:?缺少截图路径}; shift 2 ;;
    --no-launch) launch=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1"; usage; exit 2 ;;
  esac
done

python3 scripts/maintain-dev-storage.py --apply
bash scripts/check-project-sync.sh

derived="$repo_dir/build/DerivedData-ios"
log_dir="$repo_dir/build/logs"
mkdir -p "$log_dir" "$derived"
echo "$$" > "$derived/.active"
trap 'rm -f "$derived/.active"' EXIT
build_log="$log_dir/ios-build.log"
stamp=$(date +%Y%m%d%H%M)

echo "构建 iPhone 模拟器版本（构建号 ${stamp}，DerivedData：${derived}）…"
if ! xcodebuild -project Bgmori.xcodeproj -scheme Bgmori -configuration Debug \
  -destination "platform=iOS Simulator,name=$device,OS=27.0" \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION="$stamp" \
  build > "$build_log" 2>&1; then
  echo "构建失败，日志：$build_log"
  tail -60 "$build_log"
  exit 1
fi

app="$derived/Build/Products/Debug-iphonesimulator/Bgmori.app"
[[ -d "$app" ]] || { echo "构建产物不存在：$app"; exit 1; }

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
built_stamp=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")
[[ "$bundle_id" == com.yaron.bgmori ]] || { echo "Bundle ID 异常：$bundle_id"; exit 1; }
[[ "$built_stamp" == "$stamp" ]] || { echo "构建号异常：产物 $built_stamp ≠ 期望 $stamp"; exit 1; }

echo "启动模拟器 $device …"
xcrun simctl bootstatus "$device" -b > /dev/null

xcrun simctl terminate "$device" "$bundle_id" > /dev/null 2>&1 || true
xcrun simctl install "$device" "$app"

container=$(xcrun simctl get_app_container "$device" "$bundle_id" app)
payload=Bgmori.debug.dylib
[[ -f "$app/$payload" ]] || payload=Bgmori
built_hash=$(shasum -a 256 "$app/$payload" | cut -d ' ' -f 1)
installed_hash=$(shasum -a 256 "$container/$payload" | cut -d ' ' -f 1)
installed_stamp=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$container/Info.plist")
if [[ "$built_hash" != "$installed_hash" || "$installed_stamp" != "$stamp" ]]; then
  echo "安装包与本次构建不一致："
  echo "  构建：$app ($stamp, $built_hash)"
  echo "  安装：$container ($installed_stamp, $installed_hash)"
  exit 1
fi

if [[ $launch -eq 1 ]]; then
  if [[ -n "$route" ]]; then
    SIMCTL_CHILD_BGMORI_ROUTE="$route" xcrun simctl launch "$device" "$bundle_id" > /dev/null
  else
    xcrun simctl launch "$device" "$bundle_id" > /dev/null
  fi
  [[ -z "$screenshot" ]] || { mkdir -p "$(dirname "$screenshot")"; sleep 3; xcrun simctl io "$device" screenshot "$screenshot" > /dev/null; }
fi

commit=$(git -C "$repo_dir" rev-parse --short HEAD)
dirty=$(git -C "$repo_dir" status --porcelain | wc -l | tr -d ' ')

echo "已安装并在 $device 启动：$container"
echo "构建号 $stamp · commit $commit · 未提交改动 $dirty 处 · $payload 哈希 $built_hash"
[[ -z "$screenshot" ]] || echo "截图：$screenshot"
