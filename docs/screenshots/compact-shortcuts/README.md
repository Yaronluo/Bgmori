# 紧凑快捷栏

2026-10-26，继续收紧发现页和我的页面的玻璃快捷操作栏，并处理收藏状态栏的同类拉伸问题。

- 发现页的每日放送、浏览分类按文字与图标的实际宽度排列，取消均分整行与中间分隔线。
- 我的页面的收藏、设置入口采用相同布局；两处快捷栏都靠左对齐。
- 保留原生液态玻璃，使用更轻的阴影与中性文字。Mac 按钮最小高度 36 pt，iPhone 44 pt。
- 收藏状态栏宽度限制为 448 pt（含内边距），小屏保持横向滚动；选中项改用中性底色。

验证范围为 iPhone 17 / iOS 27.0 模拟器与当前 Mac / arm64。两端 Debug 构建通过；界面检查覆盖浅色、深色，以及放送、分类、收藏、设置入口。Mac 额外检查登录后的收藏状态切换；iPhone 使用游客模式。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 发现 | [查看](iphone-home-light.png) | [查看](iphone-home-dark.png) | [查看](mac-home-light.png) | [查看](mac-home-dark.png) |
| 我的 | [查看](iphone-profile-light.png) | [查看](iphone-profile-dark.png) | [查看](mac-profile-light.png) | [查看](mac-profile-dark.png) |
| 收藏状态 | — | — | [查看](mac-library-light.png) | [查看](mac-library-dark.png) |
