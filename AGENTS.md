# AGENTS.md

本文件是给 AI 编码代理（Claude Code、Codex、Cursor、Copilot、DeepSeek Harness 等）看的项目说明书。人类开发说明见 `README.md`。

## 项目是什么

**Bgmori**：Bangumi 的非官方第三方客户端，原生 SwiftUI，同时支持 iPhone 与 Mac。

- 部署目标：iOS 27 / macOS 27（不要擅自下探）
- 构建工具：Xcode 27.1 / Swift 6
- 第三方依赖：**0**。网络、图片缓存、HTML 解析均为原生实现
- 工程文件由 **XcodeGen** 生成：改工程设置请改 `project.yml`，然后运行 `xcodegen generate`，不要手改 `project.pbxproj`
- 设计基调：Apple 风格 + Liquid Glass，优先使用系统导航栏/Sheet/工具栏材质

## 常用命令

```bash
# 生成 Xcode 工程（修改 project.yml 或增删源文件后）
xcodegen generate --spec project.yml --project .

# iOS 模拟器构建
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO build

# macOS 构建
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

模拟器调试（可选）：

```bash
xcrun simctl boot "iPhone 18 Pro"
xcrun simctl install "iPhone 18 Pro" "$(find ~/Library/Developer/Xcode/DerivedData/Bgmori-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name Bgmori.app | head -1)"
SIMCTL_CHILD_BGMORI_ROUTE="subject:8" xcrun simctl launch "iPhone 18 Pro" com.yaron.bgmori
xcrun simctl io "iPhone 18 Pro" screenshot /tmp/bgmori.png
```

`BGMORI_ROUTE` 是 Debug 专用路由，支持 `home`、`calendar`、`library`、`search:关键词`、`subject:ID`、`episode:ID`、`comments:ID`、`blog:ID`、`group:name`、`topic:ID`、`timeline:用户名`、`index:ID`、`settings`、`login`。发布构建中不存在。

## 目录

```
Bgmori/App/          入口、Root Shell、路由、AppModel
Bgmori/Core/API/     APIClient、端点、限流、错误
Bgmori/Core/Auth/    OAuth、Keychain
Bgmori/Core/Models/  Bangumi DTO
Bgmori/Core/Social/  HTML 只读解析（吐槽/小组/日志/时光机）
Bgmori/Core/Storage/ 收藏状态、图片缓存、本地通知
Bgmori/Design/       Design Tokens、玻璃组件
Bgmori/Features/     各业务页面
docs/                方案与截图
```

## 代码约定

- 全部 UI 用 SwiftUI；平台差异用 `#if os(iOS)` / `#if os(macOS)`，不要为 Mac 引入 Catalyst。
- 数据流：`View → AppModel/LibraryStore → APIClient → 本地缓存`；不要在 View 里直接发请求。
- API 请求必须带项目自己的 User-Agent；新增请求要走 `APIClient` 的限流与缓存。
- Liquid Glass：系统控件优先；自定义玻璃只用于浮动控制层，同屏不超过 2 组，禁止玻璃叠玻璃。
- 颜色用 `Color.bgm*` 语义色，不要写死浅色背景，必须同时检查深色模式。
- 新页面要有空状态、加载态、错误态；错误要能重试或回退。
- 不要引入第三方库；确有需要先说明理由并评估构建影响。

## 安全与隐私

- **绝对不要**把 OAuth Client Secret、Access Token、Refresh Token、Cookie 写进仓库、日志、截图或注释。
- 私人配置放在 App 内「设置 → OAuth 应用」，或使用本地未入库的 `Secrets.xcconfig`。
- `Info.plist` 中的 `BGMApiClientSecret` 保持空字符串；发布前如要内置，必须改用 Worker 代理。
- 社交页面是匿名 HTML 只读，不要加 Cookie 登录、发帖、点赞等写操作。
- 日志里不要打印完整 URL 查询参数中的 code/token。

## 验证要求

改完代码至少做：

1. iOS 模拟器构建通过；
2. macOS 构建通过；
3. 如果改了 UI，启动模拟器截图检查浅色/深色；
4. 如果改了 API/HTML 解析，用真实数据跑一次对应页面，并在解析失败时保留 Safari 回退。

## 已知坑

- iOS 27 模拟器上系统原生 Liquid Glass Tab Bar 在截图里会出现图标重影；当前用自绘玻璃 Tab Bar 规避。不要改回系统 `Tab(role:)`，除非确认系统问题已修复。
- 部分网络环境下 `bgm.tv` 会走 QUIC/HTTP3 卡住；`URLRequest.assumesHTTP3Capable = false` 是刻意保留的。
- legacy `/calendar` 返回的图片是 `http://`，必须升级 https。
- 搜索 `nsfw` 不传等于包含 R18；审核/展示逻辑要显式过滤。
- 收藏的 `ep_status` 只对书籍有效；动画进度走章节接口。
- `updated_at` 不可靠，同步策略是全量对账，不要改成增量游标。
- HTML 选择器会随 Bangumi 改版失效；解析失败必须回退 Safari，不能崩。

## 提交

- 一个提交只做一件事；消息用 Conventional Commits，例如 `feat: add seasonal shelf`、`fix: handle nil episode airdate`。
- 提交前确认 `git status` 没有 `.DS_Store`、`xcuserdata`、密钥文件。
- 不要 force push `main`。
