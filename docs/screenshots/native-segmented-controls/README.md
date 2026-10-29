# 原生分段切换与收藏页布局

收藏类型、分类类型和搜索范围改用 SwiftUI `Picker` 的 `.segmented` 样式，由系统处理选中态、按住拖动和交互期间的 Liquid Glass。原先的普通按钮和灰色选中胶囊只在外层添加玻璃材质，没有系统分段控件的交互。

收藏类型栏移除不限制高度且关闭裁切的横向 `ScrollView`，采用控件自身高度，独立排在统计和列表上方。下拉刷新仅挂在作品列表的纵向 `ScrollView` 上，避免刷新环境同时作用于顶部横向选择栏。

截图中的收藏内容使用已有 Debug 固定样本，不涉及真实账户登录、凭证或收藏写入。分类与搜索页仍使用真实公开数据。验收范围为 iPhone 17 / iOS 27.0 与当前 Mac / arm64。

系统控件在静止时和按住交互时外观不同。[iPhone 模拟器按住截图](iphone-library-pressed-dark.png)记录了动画中的玻璃选中态；静态截图不展示完整动态效果。系统辅助功能设置也会影响动画和透明度。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 收藏 | [查看](iphone-library-light.png) | [查看](iphone-library-dark.png) | [查看](mac-library-light.png) | [查看](mac-library-dark.png) |
| 分类 | [查看](iphone-categories-light.png) | [查看](iphone-categories-dark.png) | [查看](mac-categories-light.png) | [查看](mac-categories-dark.png) |
| 搜索 | [查看](iphone-search-light.png) | [查看](iphone-search-dark.png) | [查看](mac-search-light.png) | [查看](mac-search-dark.png) |

参考：[Apple：Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)。

验证结果：两端安装脚本构建通过。`testSearchAndLibraryHeadersLightAndDark`、`testGlassBrowsingControlsLightAndDark` 与 `testLibraryTypeSelectionAndScrollingLightAndDark` 均已分别在 iPhone 模拟器和 Mac 通过，检查浅深色、分类切换、收藏过滤与统计、滚动后顶部控件位置，以及 iPhone 按住拖动与下拉刷新后的布局。收藏同步本身仍调用原方法，未用真实账户测试同步或写入。

Mac 原生分段控件通过 `RadioButton` 与数值选中状态暴露给 UI 测试，静态文字通过 `value` 暴露；测试已按平台读取对应属性，保留实际选中结果、收藏数量和布局断言。
