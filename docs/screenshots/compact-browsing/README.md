# 紧凑浏览与分页连续加载

2026-10-29，范围为 iPhone 17 / iOS 27.0 模拟器及当前 arm64 Mac。

- 分页不再用会随偏移变化而取消的视图任务启动网络请求；加载完成后重新判断下一页。页脚依据滚动区域内的实际位置触发，等待期间始终显示进度指示器。
- 标签页移除“已加载多少部作品”；同时清理搜索页重复的分类和热门提示。保留有实际含义的收藏总数、评分、状态、简介和错误提示。
- 收藏网格统一两行标题、单行状态/个人评分/观看进度和一行短评，移除进度条、重复星级和独立菜单行。未评分不再占文字位置；完整短评仍保留在列表和收藏编辑中。
- 探索分类改为横向图标文字导航，灵感改为细分隔线列表。社区和工具入口使用行式布局，Mac 两列、iPhone 一列；不再使用大块卡片。
- “我的收藏”改为粉色图标文字和轻量箭头，移除实色胶囊；旁边设置按钮也移除圆底。
- 年份弹窗缩为 Mac 150×248、iPhone 180×292，普通字号下年份行高分别为 26 和 38 点。

验证：

```bash
bash scripts/test-categories.sh
bash scripts/test-collection-presentation.sh
BGMORI_UI_RESULT_DIR=/tmp/bgmori-final-compact-ui-results bash scripts/test-shell-ui.sh all testStationaryPaginationDoesNotStall testCompactLayoutsLightAndDark testTagPaginationLightAndDark testCategoryPaginationLightAndDark
BGMORI_UI_RESULT_DIR=/tmp/bgmori-mac-compact-toolbar-results bash scripts/test-shell-ui.sh mac testCompactLayoutsLightAndDark
bash scripts/build-install-ios.sh --route search
bash scripts/build-install-macos.sh
```

静止分页测试在不发送任何滚动手势的情况下连续完成三页，特意延迟“页码已变化、保存尚未结束”的阶段。真实分类与标签页面检查继续加载；浅深色检查包括行式入口、网格对齐和年份间距。Mac 的静态文本通过 accessibility value 读取，iPhone 通过 label 读取。

收藏网格采用固定预览数据，包含未评分、在看、有评分及长短评情形；预览中的封面菜单按钮禁用。iPhone 年份截图使用同一个正式组件的隔离预览，Mac 直接点击正式分类页的年份入口。未提交真实账号密码，未改动用户收藏，也未验证真实账号同步。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 搜索入口 | [截图](iphone-compact-search-light.png) | [截图](iphone-compact-search-dark.png) | [截图](mac-compact-search-light.png) | [截图](mac-compact-search-dark.png) |
| 收藏网格预览 | [截图](iphone-compact-library-grid-light.png) | [截图](iphone-compact-library-grid-dark.png) | [截图](mac-compact-library-grid-light.png) | [截图](mac-compact-library-grid-dark.png) |
| 社区入口 | [截图](iphone-compact-profile-light.png) | [截图](iphone-compact-profile-dark.png) | [截图](mac-compact-profile-light.png) | [截图](mac-compact-profile-dark.png) |
| 年份弹窗预览 | [截图](iphone-compact-years-light.png) | [截图](iphone-compact-years-dark.png) | [截图](mac-compact-years-light.png) | [截图](mac-compact-years-dark.png) |
