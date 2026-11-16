# README 截图

首页 README 使用的截图，拍摄于 2026-11-16。

| 文件 | 页面 | 设备 / 外观 |
| --- | --- | --- |
| `iphone-home-light.jpg` | 发现 | iPhone 17 模拟器 · iOS 27.0 · 浅色 |
| `iphone-subject-light.jpg` | 条目详情（Code Geass 反叛的鲁路修 R2） | iPhone 17 模拟器 · iOS 27.0 · 浅色 |
| `iphone-categories-light.jpg` | 分类 · 动画 | iPhone 17 模拟器 · iOS 27.0 · 浅色 |
| `iphone-home-dark.jpg` | 发现 | iPhone 17 模拟器 · iOS 27.0 · 深色 |
| `iphone-subject-dark.jpg` | 条目详情 | iPhone 17 模拟器 · iOS 27.0 · 深色 |
| `iphone-calendar-dark.jpg` | 每日放送 | iPhone 17 模拟器 · iOS 27.0 · 深色 |
| `mac-home-light.png` | 发现 | 当前 Mac（Apple M2）· macOS 27 · 浅色 |
| `ech-light.jpg` | 网络与连接 · 严格 ECH | iPhone 17 模拟器 · 严格 ECH 验证记录 |

## 拍摄方式

iPhone 截图使用调试构建的固定路由启动，状态栏时间固定为 9:41：

```bash
xcrun simctl status_bar <设备> override --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

xcrun simctl ui <设备> appearance light   # 或 dark
bash scripts/build-install-ios.sh --route home
```

Mac 截图使用 `screencapture -l <window id>` 只截取 Bgmori 窗口，保留系统阴影与透明边角，再缩放到 1840 像素宽。iPhone 截图转为 JPEG（质量 84），便于 README 快速加载。

截图使用未登录的游客状态（Mac 截图为作者本人的公开账号），不包含令牌、Cookie、自定义服务地址或其他敏感数据。条目封面与评分为 Bangumi 的真实公开数据，仅用于展示界面。

更早的功能验证截图仍保留在 `docs/screenshots/` 的其他目录中；每个目录的 `README.md` 说明了对应的验收范围。
