# 首页与人物封面调整（2026-10-29）

- 发现页「正在看」和我的页「继续观看」默认只显示封面与标题。设置 → 内容 → 显示观看进度可恢复已看话数和进度条；已有章节记录保持不变，收藏编辑与章节操作仍可使用。
- 发现页在看卡片支持长按／右键「标记为看过」，只修改整部收藏状态；失败时恢复原状态并显示错误。
- 热播轮播使用前后整组副本，在滚动停止且目标页确定后复位。Mac 为无滚动阶段的滚轮事件补充分页对齐，避免停在两张作品之间。
- 热播区去掉封面边缘渐隐、模糊背景和标签胶囊；保留日期、评分、在看人数、话数、简介与标签。循环副本显示封面时不重新淡入。
- 角色、人物及其收藏列表优先取 API 的大图。人物收藏根据显示尺寸和屏幕像素密度解码，支持人物原图的 CDN 限宽与原图回退；无需清空图片缓存。

## 验证

- iPhone 17 / iOS 27.0 模拟器与当前 Mac / arm64 实际构建、安装。
- 两端浅深色连续左右滚动，分别跨过首尾边界两次以上；Mac 另检查不足整页的滚轮移动与复位后的完整卡片对齐。
- 使用 yaron 的公开角色与人物收藏读取真实数据，不需要账号密码。
- `bash scripts/test-images.sh --live`：两端图片缓存、并发合并、失败回退和显示稳定性检查通过；真实平沢唯、高橋李依、豊崎愛生图片的解码最长边分别从 251 / 134 / 117 像素提升到 600 像素。
- UI 回归使用 `testHomeCarouselLoopsLightAndDark`、`testPeoplePortraitsLightAndDark`，Mac 补充 `testHomeWheelSettlesAtLoopBoundary`。
- 未执行真实账号的收藏写入；「标记为看过」复用现有收藏状态更新、失败回滚逻辑。

## 截图

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 热播 | [查看](iphone-home-light.png) | [查看](iphone-home-dark.png) | [查看](mac-home-light.png) | [查看](mac-home-dark.png) |
| 人物收藏 | [查看](iphone-people-light.png) | [查看](iphone-people-dark.png) | [查看](mac-people-light.png) | [查看](mac-people-dark.png) |
