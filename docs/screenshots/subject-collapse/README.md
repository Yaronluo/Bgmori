# 条目详情的章节与角色预览

2026-10-28，适用 iPhone 17 / iOS 27.0 与当前 arm64 Mac。

- 章节（音乐条目为曲目）默认显示前 3 条，角色默认显示一整行（随可用宽度调整列数）。点击标题行的“展开全部”显示其余内容，再次点击收起后仍保留预览。
- 不超过预览数量时直接显示全部，不出现展开按钮；章节分类、总数和登录后的观看计数与进度条继续显示。
- 两块独立控制。切换作品恢复预览；当前页面刷新不会重置展开状态。
- 预览与展开状态均保留章节详情、进度操作、角色网格与角色详情入口。
- 动画遵循系统“减少动态效果”。

验证使用真实条目 `subject:8`，访客模式，不使用账号凭证。两端浅深色 UI 检查覆盖默认显示 3 条章节与一行角色、展开更多内容、收起后恢复预览，以及两块状态相互独立。访客测试未执行需要登录的观看进度写入。

复现：

```bash
BGMORI_UI_RESULT_DIR="$PWD/build/subject-collapse-check" \
  bash scripts/test-shell-ui.sh all testSubjectSectionPreviewsLightAndDark
```

截图按 `ios` / `mac`、`sections-preview` / `episodes-expanded` / `characters-expanded`、`light` / `dark` 命名。
