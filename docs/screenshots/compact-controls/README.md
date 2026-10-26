# 紧凑玻璃控件

发现、我的和收藏状态栏的后续调整见[紧凑快捷栏](../compact-shortcuts/README.md)。

2026-10-26，针对分类、星期切换和搜索操作区重新排版。液态玻璃保留在浮动操作层，取消整块大面板及大面积粉色选中背景。

- 分类：类型切换使用独立窄玻璃条；题材、年份和排序改为轻量菜单。iPhone 分两行，Mac 优先单行，小窗口自动换行，删除重复的类型标签。
- 星期栏：Mac 宽度最多 620 pt，星期和作品数排成一行；iPhone 使用紧凑两行按钮。选中项用中性底色与字重区分。
- 搜索：输入框使用 44 pt 高玻璃胶囊；范围按钮按文字宽度排列。Mac 横排，iPhone 放到输入框下一行，移除原先大容器和长分隔线。
- 分类、搜索的 Mac 页面标题由窗口工具栏承载，去除内容区重复标题；低透明度辅助功能回退保留。

验证范围：iPhone 17 / iOS 27.0 模拟器和当前 Mac / arm64。两端 Debug 构建通过。4 项 iPhone 界面测试与 2 项 Mac 界面测试通过，覆盖类型切换、滚动后的操作、题材/年份菜单、搜索范围和筛选弹层、星期切换。最终菜单配色调整后再次验证了 iPhone 菜单及 Mac 页面。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 分类 | [查看](iphone-categories-light.png) | [查看](iphone-categories-dark.png) | [查看](mac-categories-light.png) | [查看](mac-categories-dark.png) |
| 每日放送 | [查看](iphone-calendar-light.png) | [查看](iphone-calendar-dark.png) | [查看](mac-calendar-light.png) | [查看](mac-calendar-dark.png) |
| 搜索 | [查看](iphone-search-light.png) | [查看](iphone-search-dark.png) | [查看](mac-search-light.png) | [查看](mac-search-dark.png) |
| 搜索结果 | [查看](iphone-search-results-light.png) | [查看](iphone-search-results-dark.png) | [查看](mac-results-light.png) | [查看](mac-results-dark.png) |

[分类筛选后](iphone-category-filters.png) · [分类滚动后浅色](iphone-pinned-categories-light.png) · [分类滚动后深色](iphone-pinned-categories-dark.png) · [搜索筛选浅色](iphone-search-filter-sheet-light.png) · [搜索筛选深色](iphone-search-filter-sheet-dark.png)
