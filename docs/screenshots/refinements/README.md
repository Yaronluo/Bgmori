# 界面精简与日志修复

2026-10-26，验收设备：iPhone 17 / iOS 27.0 模拟器、当前 Mac / arm64。

- 分类、搜索和章节类型使用文字选项与短下划线；收藏状态和主题设置使用菜单。
- 网格封面随列宽铺满；标题与信息间距收紧；评分位于封面下方，无黑色底。
- 页面底部的 Bangumi 链接移至工具栏菜单，解析失败仍可打开 Safari。
- 发现页和我的页面的日志入口统一使用路由导航，详情与返回共享同一条导航路径。
- 日志正文按嵌套容器边界提取，避免截断；统一换行，去除多余段间空白。
- 搜索栏、范围切换、最近搜索和推荐关键词重新排版，移除推荐描述与空历史提示。
- 分类、搜索、吐槽在滚动到底部时自动翻页；分页失败可重试，保留已加载内容。
- 删除首页、我的、放送、登录、设置和空状态中的装饰文案及重复说明。

验证结果：

- iPhone 17 / iOS 27.0 和 Mac / arm64 Debug 构建均通过。
- iPhone 界面测试 3 项通过：日志列表到详情及返回、分类浅深色与自动翻页、搜索与结果。
- Mac 界面测试 2 项通过：日志详情、分类与搜索的浅深色显示。
- `bash scripts/test-categories.sh` 与 `bash scripts/test-navigation.sh` 均通过。
- `bash scripts/test-social.sh --live` 通过嵌套正文、容器边界、异常 HTML、段落间距检查，并成功读取真实列表前三篇日志正文。

截图：

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 分类 | [查看](iphone-categories-light.png) | [查看](iphone-categories-dark.png) | [查看](mac-categories-light.png) | [查看](mac-categories-dark.png) |
| 搜索 | [查看](iphone-search-light.png) | [查看](iphone-search-dark.png) | [查看](mac-search-light.png) | [查看](mac-search-dark.png) |
| 搜索结果 | [查看](iphone-search-results-light.png) | [查看](iphone-search-results-dark.png) | [查看](mac-results-light.png) | [查看](mac-results-dark.png) |
| 日志详情 | [查看](iphone-blog-detail-light.png) | [查看](iphone-blog-detail-dark.png) | [查看](mac-blog-detail.png) | — |

[自动翻页后的分类页](iphone-categories-auto-page.png) · [日志列表](iphone-blogs-light.png) · [从详情返回列表](iphone-blogs-return.png)
