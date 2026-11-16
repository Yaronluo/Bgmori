# 分类页顶部筛选条改成与每日放送一致的玻璃条

## 问题

分类页顶部原来是「系统分段控件 + 圆形玻璃筛选按钮」两件浮在内容上的控件，中间和下方没有连续的面。列表滚动时卡片从两片玻璃之间穿过，标题、评分被横向切断：玻璃上方露一截，下方再被压住；再加一层渐隐遮罩，控件本身仍是两段，看着还是割裂。

每日放送页的周历条没有这个问题：七个日期在一个玻璃胶囊里，内容整条从玻璃下经过，被材质糊掉而不是被切开。

## 修复

iOS 分类页顶部改成同一种结构：

- 类型切换改用仓库自带的 `TextTabs(usesGlass: false)`，去掉系统分段控件那层独立玻璃。
- 类型标签和筛选按钮放进同一个容器，`.padding(4).bgmFloatingGlass(cornerRadius: 24, shadowRadius: 6)`，与 `CalendarView` 的周历条同一套参数。
- 整条成为一块玻璃，滚动内容从下面整体经过；没有玻璃叠玻璃，同屏自定义玻璃从 2 组降到 1 组。
- Mac 端不变：仍用工具栏里的原生分段控件与筛选菜单。

## 验证

- `bash scripts/test-shell-ui.sh ios testCategoryPaginationLightAndDark`：iPhone 17 / iOS 27.0，浅深色各滚动超过一页后截图，1 项测试 0 失败。
- `bash scripts/build-install-ios.sh --route categories`、`bash scripts/build-install-macos.sh`：两端构建、安装通过。
- 浅深色截图中筛选条内没有任何卡片文字透出，滚动内容在玻璃下被模糊，下沿不再出现半行标题。

| iPhone 浅色 | iPhone 深色 |
| --- | --- |
| ![滚动后的分类页](iphone-light.png) | ![滚动后的分类页](iphone-dark.png) |
