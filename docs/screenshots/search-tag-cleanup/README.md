# 搜索与收藏顶部、标签分页及页面文案清理

本目录保留第一轮修复记录。后续已移除加载数量并收紧布局，当前界面以[紧凑浏览截图](../compact-browsing/README.md)为准。

2026-10-29，验收设备为 iPhone 17 / iOS 27.0 模拟器与当前 arm64 Mac。

- 搜索顶部改为独立布局，滚动区域裁切到控件下方；收藏搜索框纳入同一个顶部布局，避免导航栏搜索框与筛选区域相互覆盖。
- 标签列表滚动预取下一页；分页未完成时保留完整行，续页失败可重试，刷新失败保留已有作品。请求沿用 APIClient 的限流与缓存。
- 真实“校园”接口请求 24 条时实际返回 20 条，后续偏移按实际返回行数推进。两端 UI 测试均确认滚动能加载超过首批 20 部。
- 详情标签的数字为使用该标签标记本作的用户数，增加“人”单位并修正辅助功能描述。列表显示实际“已加载”作品数，避免把搜索接口的 total 当作准确的标签作品总数。字段含义见[官方定义](https://raw.githubusercontent.com/bangumi/api/master/open-api/v0.yaml)。
- 来源说明集中在设置的关于软件中，清理普通页面的来源提示和常驻网页按钮。正文链接、资料链接、分享与复制链接仍保留；加载或解析失败时的网页回退、移除收藏必须使用的网页操作仍保留。

验证命令：

```bash
bash scripts/test-categories.sh
BGMORI_UI_RESULT_DIR=/tmp/bgmori-header-tag-ui-results bash scripts/test-shell-ui.sh all testSearchAndLibraryHeadersLightAndDark testTagPaginationLightAndDark
bash scripts/build-install-ios.sh --route search
bash scripts/build-install-macos.sh
```

分页回归覆盖服务器限制单页条数、实际偏移、去重、内容过滤、完整行缓冲、失败重试、刷新保留和查询切换。UI 测试检查浅深色顶部排列、输入与滚动，以及真实标签页面继续加载。收藏截图使用已有的免登录筛选预览模式，仅验证控件布局和输入；未提交真实账号密码，也未验证个人收藏同步。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 搜索 | [截图](iphone-search-header-light.png) | [截图](iphone-search-header-dark.png) | [截图](mac-search-header-light.png) | [截图](mac-search-header-dark.png) |
| 收藏顶部预览 | [截图](iphone-library-header-light.png) | [截图](iphone-library-header-dark.png) | [截图](mac-library-header-light.png) | [截图](mac-library-header-dark.png) |
| 标签首批 | [截图](iphone-tag-first-page-light.png) | [截图](iphone-tag-first-page-dark.png) | [截图](mac-tag-first-page-light.png) | [截图](mac-tag-first-page-dark.png) |
| 标签续页 | [截图](iphone-tag-paginated-light.png) | [截图](iphone-tag-paginated-dark.png) | [截图](mac-tag-paginated-light.png) | [截图](mac-tag-paginated-dark.png) |
