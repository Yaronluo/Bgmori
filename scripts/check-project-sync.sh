#!/bin/bash
# 确保 Bgmori.xcodeproj 存在且与 project.yml、磁盘源文件一致。
# 工程文件由 XcodeGen 生成、不入库（见 .gitignore）；缺失或过期时这里直接重新生成，
# 避免“新文件没进工程 → 编译成功但功能还是旧的”这种静默失败。
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"

project="Bgmori.xcodeproj/project.pbxproj"

sources_in_sync() {
  [[ -f "$project" ]] || return 1
  local tmp_dir
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-sync.XXXXXX")
  (cd Bgmori && find . -name '*.swift' -exec basename {} \; | sort -u) > "$tmp_dir/disk.txt"
  grep -oE '[A-Za-z0-9_+.-]+\.swift' "$project" | sort -u > "$tmp_dir/project.txt"
  local missing stale
  missing=$(comm -23 "$tmp_dir/disk.txt" "$tmp_dir/project.txt")
  stale=$(comm -13 "$tmp_dir/disk.txt" "$tmp_dir/project.txt" | grep -v '^sourcecode\.swift$' || true)
  rm -rf "$tmp_dir"
  [[ -z "$missing" && -z "$stale" ]]
}

needs_generate=0
[[ -f "$project" ]] || needs_generate=1
if [[ $needs_generate -eq 0 && project.yml -nt "$project" ]]; then needs_generate=1; fi
if [[ $needs_generate -eq 0 ]] && ! sources_in_sync; then needs_generate=1; fi

if [[ $needs_generate -eq 1 ]]; then
  if ! command -v xcodegen > /dev/null 2>&1; then
    echo "缺少 XcodeGen，请先安装：brew install xcodegen" >&2
    exit 1
  fi
  echo "生成 Xcode 工程：xcodegen generate --spec project.yml --project ."
  xcodegen generate --spec project.yml --project . > /dev/null
  if ! sources_in_sync; then
    echo "工程生成后仍与源码不一致，请检查 project.yml 的 sources 配置。" >&2
    exit 1
  fi
fi
