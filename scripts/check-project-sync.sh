#!/bin/bash
# 校验 Xcode 工程与磁盘源码一致，避免“文件没加进工程 → 编译通过但功能还是旧的”。
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
project="$repo_dir/Bgmori.xcodeproj/project.pbxproj"

[[ -f "$project" ]] || { echo "缺少 $project，请先运行 xcodegen generate --spec project.yml --project ."; exit 1; }

# 刚 clone / worktree checkout 出来时所有文件时间戳几乎相同，不能只看 mtime。
# 真正的信号是：project.yml 有未提交改动，却没有对应的工程文件改动。
spec_dirty=$(git -C "$repo_dir" status --porcelain -- project.yml)
project_dirty=$(git -C "$repo_dir" status --porcelain -- Bgmori.xcodeproj/project.pbxproj)
if [[ -n "$spec_dirty" && -z "$project_dirty" ]]; then
  echo "project.yml 有未提交改动，但工程文件没有重新生成：请先运行 xcodegen generate --spec project.yml --project ."
  exit 1
fi
if [[ -n "$spec_dirty" && "$repo_dir/project.yml" -nt "$project" ]]; then
  echo "project.yml 比 project.pbxproj 新：请先运行 xcodegen generate --spec project.yml --project ."
  exit 1
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/bgmori-sync.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

(cd "$repo_dir/Bgmori" && find . -name '*.swift' -exec basename {} \; | sort -u) > "$tmp_dir/disk.txt"
grep -oE '[A-Za-z0-9_+.-]+\.swift' "$project" | sort -u > "$tmp_dir/project.txt"

missing=$(comm -23 "$tmp_dir/disk.txt" "$tmp_dir/project.txt" || true)
stale=$(comm -13 "$tmp_dir/disk.txt" "$tmp_dir/project.txt" | grep -v '^sourcecode\.swift$' || true)

if [[ -n "$missing" ]]; then
  echo "以下 Swift 文件在磁盘上，但没有被工程引用（会被静默跳过编译）："
  echo "$missing"
  echo "请运行 xcodegen generate --spec project.yml --project ."
  exit 1
fi

if [[ -n "$stale" ]]; then
  echo "工程引用了磁盘上不存在的 Swift 文件："
  echo "$stale"
  echo "请运行 xcodegen generate --spec project.yml --project ."
  exit 1
fi
