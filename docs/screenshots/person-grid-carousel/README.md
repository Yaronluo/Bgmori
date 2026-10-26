# 人物作品网格与发现轮播修复

2026-10-27，在 iPhone 17 / iOS 27.0 模拟器和当前 Mac / arm64 上验证。

- 人物和角色的「参与作品」复用标准封面卡片，图片在网格列宽内布局，标题预留两行。列间距 16 pt、行间距 20 pt；Mac 内容区限制宽度。
- 发现页进入详情、切换栏目或被登录/设置覆盖时暂停轮播。返回后保留所选作品，并重新等待完整的 6 秒再轮播。
- iPhone 与 Mac Debug 构建通过。两端浅色/深色 UI 检查通过，作品卡片等宽且相邻间距符合预期。
- 两端浅色/深色均实际点击第二张热播卡片，进入详情停留 13 秒后返回，确认仍选中第二张；随后确认自动轮播恢复。
- Mac 已更新 `/Applications/Bgmori.app`，旧版本由安装脚本备份。

| 平台 | 浅色 | 深色 |
| --- | --- | --- |
| iPhone 17 | [截图](iphone-related-light.png) | [截图](iphone-related-dark.png) |
| 当前 Mac | [截图](mac-related-light.png) | [截图](mac-related-dark.png) |
