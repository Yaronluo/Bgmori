# 账号按钮、收藏层级与窗口恢复

2026-10-29，iPhone 17 / iOS 27.0 与当前 arm64 Mac。

## 界面调整

- 「我的收藏」和「登录」共用轻量胶囊导航样式，取消加高的原生突出玻璃按钮和重复箭头。Mac 高 32 pt，iPhone 高 40 pt。
- 收藏搜索恢复为普通输入底色。Mac 高 34 pt、最大宽度 420 pt，放在内容区；分类与状态放在系统工具栏，明确区分导航和输入。iPhone 保留 44 pt 的输入触控区域，以材质和 12 pt 间距区分层级。
- Mac 分类类型与筛选、收藏类型与状态、搜索范围、周历、吐槽筛选统一使用 `ToolbarItem` 和 `sharedBackgroundVisibility(.visible)`，由系统工具栏提供液态玻璃，与收起侧栏按钮使用相同的承载方式。
- 移除 Mac 内容区的独立液态玻璃层与手动重建材质方案。内容区输入框使用普通底色，短暂提示使用标准材质；iPhone 的原生底栏和浮动控件保持原布局。

用户截图显示浅色页面的玻璃背景异常变暗，不能仅凭截图确认系统内部触发原因。本次改由系统工具栏管理玻璃背景及窗口活动状态，没有固定为浅色。

## 截图

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 账号按钮 | [查看](iphone-profile-light.png) | [查看](iphone-profile-dark.png) | [查看](mac-profile-light.png) | [查看](mac-profile-dark.png) |
| 收藏层级 | [查看](iphone-library-light.png) | [查看](iphone-library-dark.png) | [查看](mac-library-light.png) | [查看](mac-library-dark.png) |

账号截图使用游客的同一按钮组件，未登录真实账号或写入收藏。

## 验证

```bash
bash scripts/build-install-ios.sh --route home
bash scripts/build-install-macos.sh
bash scripts/test-shell-ui.sh all testSearchAndLibraryHeadersLightAndDark testGlassBrowsingControlsLightAndDark
bash scripts/test-glass-window-restore.sh
```

独立窗口恢复测试使用当前终端已有的辅助功能权限，避免 XCTest 进程的权限限制；它不请求或修改系统权限。检查浅深色下分类、收藏玻璃背景的亮度，反复切换 Finder 与应用，并通过系统辅助功能接口恢复同一个最小化窗口；同时检查收藏搜索文字没有丢失。该自动化覆盖窗口激活与恢复，不等同于自动拖拽台前调度缩略图。运行时台前调度处于开启状态。

实现参考：[Apple 工具栏控件位置](https://developer.apple.com/documentation/swiftui/toolbaritemplacement)与当前 SDK 的 `ToolbarContent.sharedBackgroundVisibility` 接口。

恢复后截图：[Mac 浅色分类](mac-categories-restored-light.png) · [Mac 深色分类](mac-categories-restored-dark.png)。独立检查中，同一窗口恢复前后材质亮度分别为：浅色分类 0.973 / 0.973、浅色收藏 0.977 / 0.977、深色分类 0.305 / 0.305、深色收藏 0.352 / 0.352；搜索文字检查通过。

结果：两端构建、浅深色界面检查通过；iPhone 分类、放送、吐槽、搜索与收藏四项回归通过；Mac 分类、放送、吐槽回归通过，搜索与收藏在补全工具栏辅助功能分组后单项复跑通过。搜索范围：[Mac 浅色](mac-search-light.png) · [Mac 深色](mac-search-dark.png)。
