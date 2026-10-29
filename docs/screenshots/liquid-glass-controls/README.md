# 液态玻璃控件与使用边界

2026-10-29，验收范围为 iPhone 17 / iOS 27.0 模拟器与当前 Apple Silicon Mac。

本目录保留本轮早期控件方案的验收记录。当前账号按钮、收藏层级与 Mac 系统工具栏方案见[最终实现与窗口恢复检查](../glass-hierarchy-restore/README.md)。

## 保留玻璃的位置

- 系统原生 Tab Bar、导航栏、工具栏与 Sheet。
- 分类顶部的类型切换与筛选控件。
- 收藏与搜索顶部的输入区、类型与范围切换。
- 固定在内容上方的放送周历与吐槽筛选。吐槽的菜单共享一条紧凑玻璃栏，组内按钮保持普通样式。
- iPhone 详情底部的收藏和记录进度，通过 `GlassEffectContainer` 协调并排的原生按钮；Mac 详情的主要收藏操作和个人页的主要账号操作。
- 筛选弹窗的“完成”保留原生主要操作样式。

## 恢复轻量样式的位置

首页轮播圆点、板块“全部”等文字跳转、详情列表展开与收起、章节类型切换、收藏行的更多菜单、收藏状态次级菜单、错误重试、收藏进度加减、设置登录和退出、个人页的偏好设置。

正文、封面、信息卡与密集标签保持内容底板。玻璃用来区分导航和浮动操作，不统一套在内容和每个按钮上。自定义材质复用减少透明度的实色降级，系统按钮由系统处理辅助功能设置。

## 截图

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 分类 | [查看](iphone-categories-light.png) | [查看](iphone-categories-dark.png) | [查看](mac-categories-light.png) | [查看](mac-categories-dark.png) |
| 每日放送 | [查看](iphone-calendar-light.png) | [查看](iphone-calendar-dark.png) | [查看](mac-calendar-light.png) | [查看](mac-calendar-dark.png) |
| 条目详情 | [查看](iphone-subject-light.png) | [查看](iphone-subject-dark.png) | [查看](mac-subject-light.png) | [查看](mac-subject-dark.png) |
| 收藏控件 | [查看](iphone-library-light.png) | [查看](iphone-library-dark.png) | [查看](mac-library-light.png) | [查看](mac-library-dark.png) |

## 验证与边界

```bash
bash scripts/build-install-ios.sh --route categories
bash scripts/build-install-macos.sh
bash scripts/test-shell-ui.sh all testGlassBrowsingControlsLightAndDark testSearchAndLibraryHeadersLightAndDark testInfoLinksAndFiltersLightAndDark
```

交互回归覆盖五种分类切换、筛选弹窗完成、周历选中、登录引导、吐槽筛选重置，以及搜索与收藏输入。分类、放送、条目和吐槽读取真实匿名内容；收藏顶部使用 Debug 预览验证。没有输入账号密码或执行远程收藏写操作，减少透明度保留既有降级实现，本次未切换系统设置实测。

结果：两端安装构建通过，iPhone 三项回归通过。Mac 的筛选和输入回归通过；主要操作回归曾受其他前台窗口遮挡，测试在点击前主动激活应用后单项复跑通过（`bash scripts/test-shell-ui.sh mac testGlassBrowsingControlsLightAndDark`）。已人工检查两端浅深色截图。
