# Liquid Glass 操作层

此页保留首轮截图。分类、星期栏和搜索区的最新布局见[紧凑玻璃控件](../compact-controls/README.md)。

2026-10-26；验收范围为 iPhone 17 / iOS 27.0 模拟器和当前 Mac / arm64。

- 发现页的每日放送、浏览分类，以及我的页面的收藏、设置入口使用悬浮玻璃操作栏。
- 分类的类型、题材、年份、排序合并为一个玻璃筛选区；搜索输入与搜索范围合并为一个玻璃操作区。滚动后保持可用，内容从材质下方经过。
- 每日放送的星期切换、收藏库的状态切换使用玻璃悬浮栏。
- 自定义底部导航使用可交互的原生玻璃，保留选中项动画和辅助功能标签。
- 登录、空状态主操作和 Mac 条目收藏、进度操作使用系统玻璃按钮；详情导航栏恢复系统材质及自动配色。
- 同一浮动栏只应用一次玻璃效果；栏内选中项使用半透明语义色。开启减少透明度时，共用玻璃组件改用不透明表面；封面、正文、信息列表维持清晰的内容层。

验证：

- 两端 Debug 构建通过；未修改部署目标、工程配置或第三方依赖。
- iPhone 界面测试 4 项通过：快捷入口和设置弹层、分类切换及滚动后的筛选操作、搜索范围与筛选弹层、条目详情浅深色。
- Mac 界面测试 3 项通过：分类与搜索浅深色、收藏状态切换、放送星期切换与浅深色。
- 分类滚动后的测试通过实际点击并确认选中状态变化验收。系统对玻璃栏按钮的 `isHittable` 会报告 false，但点击及状态更新正常。
- 截图来自上述界面测试。登录态收藏库在 Mac 验证，iPhone 使用游客模式；未执行收藏保存等账号写入操作。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 分类 | [查看](iphone-categories-light.png) | [查看](iphone-categories-dark.png) | [查看](mac-categories-light.png) | [查看](mac-categories-dark.png) |
| 分类滚动后的玻璃 | [查看](iphone-pinned-categories-light.png) | [查看](iphone-pinned-categories-dark.png) | — | — |
| 搜索结果 | [查看](iphone-search-results-light.png) | [查看](iphone-search-results-dark.png) | [查看](mac-results-light.png) | [查看](mac-results-dark.png) |
| 搜索筛选弹层 | [查看](iphone-search-filter-sheet-light.png) | [查看](iphone-search-filter-sheet-dark.png) | — | — |
| 搜索空页 | — | — | [查看](mac-search-light.png) | [查看](mac-search-dark.png) |
| 条目详情 | [查看](iphone-subject-light.png) | [查看](iphone-subject-dark.png) | — | — |
| 每日放送 | [查看](iphone-calendar-navigation.png) | — | [查看](mac-calendar-light.png) | [查看](mac-calendar-dark.png) |

[发现快捷栏](iphone-home-light.png) · [我的快捷栏](iphone-profile-light.png) · [设置弹层](iphone-settings-sheet.png) · [Mac 收藏筛选](mac-library-filter.png)
