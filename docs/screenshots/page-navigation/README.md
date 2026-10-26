# 页面导航精简

- 发现：每日放送、浏览分类改为无底板的轻量入口。Mac 与内容标题同行，iPhone 位于精选内容上方，随内容滚动。精选卡片的点击区域限制在卡片边界内，避免遮挡入口。
- 分类：类型改为文字与短下划线，移除宽胶囊。Mac 与下方网格对齐，保留独立筛选、年份和排序；iPhone 将类型与筛选按钮合为一行，年份与排序移入筛选面板，可一起重置。
- 每日放送：周历只显示星期与日期，作品数量留在当日摘要与无障碍标签中。去掉玻璃外框及阴影，Mac 周历最大宽度为 420 pt；手机仍保留七天等宽触控区。
- iPhone 的分类和每日放送改用紧凑导航标题，减少顶部空白。

验证：iPhone 17 / iOS 27.0 模拟器、当前 Mac / arm64；检查两种外观、发现入口跳转、类型切换、星期切换与回到今天、分类条件及重置。未改动登录配置。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 发现 | [截图](iphone-home-light.png) | [截图](iphone-home-dark.png) | [截图](mac-home-light.png) | [截图](mac-home-dark.png) |
| 分类 | [截图](iphone-categories-light.png) | [截图](iphone-categories-dark.png) | [截图](mac-categories-light.png) | [截图](mac-categories-dark.png) |
| 每日放送 | [截图](iphone-calendar-light.png) | [截图](iphone-calendar-dark.png) | [截图](mac-calendar-light.png) | [截图](mac-calendar-dark.png) |

手机分类面板：[浅色](iphone-filters-light.png) · [深色](iphone-filters-dark.png)。
