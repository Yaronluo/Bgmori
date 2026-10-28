# 章节列表的继续查看入口

2026-10-29，将章节预览的展开入口从标题右侧移至第三条章节下方，以“查看其余 N 话”与向下箭头明确仍有后续章节；音乐条目显示“曲”。展开后在列表底部提供收起入口。

使用真实条目 `subject:8`，在 iPhone 17 / iOS 27.0 和当前 arm64 Mac 上通过浅深色 UI 检查，覆盖入口位置、剩余数量文案、展开、收起及角色区的独立展开状态。访客模式未执行需要登录的进度写入。

| 平台 | 浅色 | 深色 |
| --- | --- | --- |
| iPhone | [截图](ios-light.png) | [截图](ios-dark.png) |
| Mac | [截图](mac-light.png) | [截图](mac-dark.png) |

```bash
BGMORI_UI_RESULT_DIR="$PWD/build/episode-footer-check" \
  bash scripts/test-shell-ui.sh all testSubjectSectionPreviewsLightAndDark
```
