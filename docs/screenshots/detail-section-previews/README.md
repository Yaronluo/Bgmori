# 详情列表的预览与继续查看入口

2026-10-29，适用 iPhone 17 / iOS 27.0 与当前 arm64 Mac。

- 章节默认显示 3 条；角色、关联条目、人物/角色的参与作品默认显示一整行；制作人员默认显示两行，列数随可用宽度调整。
- 预览下方统一显示“查看其余 N …”，点开显示全部；展开后可在标题处或列表底部收起。内容没有超出预览数量时不显示展开入口。
- 制作人员不再固定截取前 12 条。同一人的不同职务合并展示，人数按实际人物计算；参与作品也按作品 ID 合并不同职务，避免重复卡片。
- 关联条目采用网格，封面约束在各自列内，横向图片不会挤占相邻列；标题保留两行。
- 切换条目恢复预览，当前页面刷新保留展开状态，各板块独立控制，展开动画遵循“减少动态效果”。

验证使用真实条目 `subject:8` 和人物 `person:17491`，以访客模式完成 iPhone 17 / iOS 27.0 与当前 arm64 Mac 的浅深色检查，覆盖底部入口位置、剩余数量文案、整行预览、展开更多内容、顶部收起和各板块独立状态。制作人员与作品的多职务合并测试在两端通过；未执行需要登录的收藏或进度写入。

最终结果：iPhone 记录位于 `build/detail-previews-acceptance/ios.xcresult`，Mac 记录位于 `build/detail-previews-mac-final/mac.xcresult`，两端均为 `TEST SUCCEEDED`。Mac 已更新 `/Applications/Bgmori.app`，iPhone 安装由构建脚本校验二进制哈希与构建号。

| 板块 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 角色 | [截图](ios-characters-light.png) | [截图](ios-characters-dark.png) | [截图](mac-characters-light.png) | [截图](mac-characters-dark.png) |
| 制作人员 | [截图](ios-staff-light.png) | [截图](ios-staff-dark.png) | [截图](mac-staff-light.png) | [截图](mac-staff-dark.png) |
| 关联条目 | [截图](ios-relations-light.png) | [截图](ios-relations-dark.png) | [截图](mac-relations-light.png) | [截图](mac-relations-dark.png) |
| 参与作品 | [截图](ios-works-light.png) | [截图](ios-works-dark.png) | [截图](mac-works-light.png) | [截图](mac-works-dark.png) |

复现：

```bash
bash scripts/test-related-subjects.sh
BGMORI_UI_RESULT_DIR="$PWD/build/detail-previews-acceptance" \
  bash scripts/test-shell-ui.sh all \
    testSubjectSectionPreviewsLightAndDark testPersonWorksPreviewLightAndDark
```

章节入口单独的截图见 [章节列表的继续查看入口](../episode-footer/README.md)。
