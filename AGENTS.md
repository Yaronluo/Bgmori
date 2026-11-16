# AGENTS.md

> 给 AI 编码代理（Codex、Claude Code、Cursor、Copilot、Gemini CLI、DeepSeek Harness 等）的项目说明书。
> 人类开发说明见 [`README.md`](README.md)，贡献流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
>
> **本文件是唯一的规范源。** `CLAUDE.md`、`GEMINI.md`、`.github/copilot-instructions.md`、`.cursor/rules/bgmori.mdc` 只是入口，遇到冲突以本文件为准。

## 0. 给代理的硬性约定

- 先把本文件读完，再读要改的功能文件；不要凭文件名猜实现。
- 先看现状、再改代码；一次只做一件事，保持 diff 小。
- 改完必须实际构建两端；改 UI 要截图，改 API/HTML 要用真实数据验证。
- **除非用户明确说“提交/推送/发版”，否则不要 `git commit`、`git push`、开 PR。**
- 不要为了“让编译过”删功能、吞错误、跳过测试或把测试改成永远通过；修根因。
- 不要伪造构建结果、网络结果、登录结果或截图。做不到就说明边界。
- 不要从其他 Bangumi 客户端仓库复制实现、文案或地址清单。只依据 Bangumi 官方 API、官网页面和本仓库代码实现。
- 默认用中文回复用户；代码、命令、变量名保持英文。

## 1. 项目是什么

**Bgmori** 是 Bangumi 的非官方第三方客户端，原生 SwiftUI，同时支持 iPhone 与 Mac。

- 当前版本：`1.0.0 (1)`；不是 App Store 版本，iPhone 需要自签 IPA。
- 部署目标：**iOS 27 / macOS 27**，不要擅自下探。
- 工具链：Xcode 27.1+、Swift 6、Go 1.27+、XcodeGen 2.46+。
- UI、缓存、HTML 解析全部原生实现；没有第三方 Swift 库。
- 为实现 ECH 国内直连，内嵌 **Go 标准库静态连接层**。没有外部 Go 模块，也不需要额外服务器。
- 社交页面（吐槽、小组、日志、时光机）是匿名 HTML 只读；不支持发帖、回帖、点赞、维基编辑。
- 设计基调：Apple 风格 + Liquid Glass；系统导航栏、Sheet、工具栏材质优先。

**非目标：** App Store 上架、账号体系、社交写操作、Widget/App Intents/Handoff、多窗口专门优化、Intel Mac 支持。

## 2. 参考环境

| 项目 | 要求 |
| --- | --- |
| macOS | 27 |
| Xcode | 27.1 或更新 |
| Swift | 6.0 |
| Go | 1.27+（只用于 ECH 静态库） |
| XcodeGen | 2.46+ |
| iPhone 模拟器 | iPhone 17 · iOS 27.0 |
| Mac | Apple Silicon（arm64） |

验收基准是 **标准版 iPhone 17（iOS 27.0 模拟器）** 与 **Apple Silicon Mac（My Mac）**。不需要扩展其他机型矩阵，也不要下载额外模拟器运行时。

构建缓存固定在当前 checkout 的 `build/` 下；不要用全局 `~/Library/Developer/Xcode/DerivedData` 反复创建项目构建目录。

## 3. 五分钟跑起来

```bash
git clone https://github.com/Yaronluo/Bgmori.git
cd Bgmori

# 生成工程（脚本也会自动生成；首次手动打开时需要）
xcodegen generate --spec project.yml --project .

open Bgmori.xcodeproj
```

选择 `Bgmori` scheme；iOS 选 `iPhone 17 (iOS 27.0)`，Mac 选 `My Mac`。真机需要在 Signing & Capabilities 选择自己的 Team。

日常构建与安装：

```bash
# iPhone 17 模拟器：构建 → 安装 → 启动 → 可选截图
bash scripts/build-install-ios.sh --route subject:8 --screenshot build/tmp/shot.png

# Mac：构建 → 校验签名 → 替换 /Applications/Bgmori.app → 打开
bash scripts/build-install-macos.sh
```

手动构建：

```bash
# iOS 模拟器
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath build/DerivedData-ios \
  CODE_SIGNING_ALLOWED=NO build

# macOS
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData-mac \
  CODE_SIGNING_ALLOWED=NO build
```

`Bgmori.xcodeproj` 由 XcodeGen 生成且不入库。新 checkout 没有它是正常的；`scripts/check-project-sync.sh` 会按需重新生成，两个安装脚本已经内置。

### Debug 路由

`BGMORI_ROUTE` 仅在 Debug 构建生效：

```text
home
categories
categories:2        # 1 书籍 / 2 动画 / 3 音乐 / 4 游戏 / 6 三次元
calendar
library
search:关键词
subject:8
tag:治愈
episode:1027
comments:8
blog:382206
group:pixiv
topic:5155
timeline:sai
index:1
settings
login
notify
```

`notify` 页面可加 `BGMORI_PREVIEW_NOTICES=1` 注入截图用固定条目。发布构建中不存在这些入口。

## 4. 目录地图

```text
Bgmori/
├─ App/
│  ├─ BgmoriApp.swift           @main、窗口与 Settings 场景
│  ├─ AppModel.swift            全局状态：登录、收藏、通知、Toast、启动
│  ├─ AppModel+Reminders.swift  追番提醒的前台刷新与调度
│  ├─ AppRouter.swift           五个栏目的路由栈、深链与放送定位
│  ├─ RootView.swift            iPhone Tab Shell / Mac NavigationSplitView
│  └─ DebugLayoutPreview.swift  Debug 布局/截图夹具
├─ Core/
│  ├─ API/
│  │  ├─ APIClient.swift        请求管线、User-Agent、限流、缓存、错误
│  │  ├─ APIClient+Endpoints.swift  所有端点与缓存辅助
│  │  ├─ MirrorRouting.swift    线路选择、代理、ECH 分派
│  │  ├─ ECHTransport.swift     Swift ↔ Go C ABI
│  │  └─ RateLimiter.swift
│  ├─ Auth/
│  │  ├─ AuthManager.swift      登录状态、个人令牌
│  │  ├─ BangumiWebSession.swift 官网会话、验证码、取消收藏网页请求
│  │  └─ Keychain.swift          Keychain 封装
│  ├─ Models/                   Bangumi DTO（Models.swift、Notice.swift）
│  ├─ Settings/AppSettings.swift 外观与内容设置、UserDefaults
│  ├─ Social/                   HTML 只读解析（吐槽/小组/日志/时光机）
│  └─ Storage/
│     ├─ LibraryStore.swift     收藏全量对账、乐观更新
│     ├─ ImageLoader.swift      磁盘/内存图片缓存
│     ├─ NotificationManager.swift
│     └─ AiringReminderPlan.swift
├─ Design/
│  ├─ Theme.swift               颜色、字体、玻璃材质、桌面布局
│  └─ Components.swift          卡片、分区、筛选、Toast、FlowLayout
├─ Features/
│  ├─ Home/                     发现、轮播、封面卡片
│  ├─ Calendar/                 每日放送
│  ├─ Categories/               分类、筛选、分页
│  ├─ Library/                  收藏库
│  ├─ Search/                   搜索、标签结果
│  ├─ Subject/                  条目详情、收藏编辑
│  ├─ Episode/ Person/          章节、角色
│  ├─ Profile/                  我的、好友、人物收藏、评分
│  ├─ Social/                   小组、日志、时光机、目录
│  ├─ Settings/                 设置、提醒
│  └─ Auth/LoginView.swift
├─ Resources/                   Assets、Info.plist、GoRuntime-LICENSE.txt
└─ Native/ECH/                  Go 标准库 ECH 连接层

scripts/                        构建、安装、回归与存储维护脚本
tests/                          Swift 测试源（由脚本编译运行）
docs/                           设计记录与验收截图
```

常用入口：

- 新增页面：`Features/<模块>/`，路由在 `AppRouter`，壳层在 `RootView`。
- 新增接口：`Core/Models/Models.swift` + `Core/API/APIClient+Endpoints.swift`。
- 改收藏逻辑：`Core/Storage/LibraryStore.swift`。
- 改网络/线路：`Core/API/MirrorRouting.swift` + `ECHTransport.swift`。
- 改视觉：`Design/Theme.swift` + `Design/Components.swift`。
- 改设置：`Core/Settings/AppSettings.swift` + `Features/Settings/SettingsView.swift`。

## 5. 数据流

```text
SwiftUI View
    │ 用户操作 / 读取状态
    ▼
AppModel / LibraryStore / 各 Feature Store   (@MainActor, @Observable)
    │
    ├─ APIClient ── URLSession + RateLimiter + DiskCache
    ├─ SocialService ── 匿名 HTML 解析
    ├─ ImageLoader ── 内存/磁盘图片缓存
    └─ Keychain ── 令牌与官网会话
```

规则：

- View 不直接发 `URLSession` 请求，不直接读写 Keychain，不直接解析 HTML。
- 新增读取请求优先走 `APIClient` 的缓存与限流；不要绕过。
- 收藏写入走 `LibraryStore` 的乐观更新 + 失败回滚，不要在 View 里拼接 PATCH。
- 跨页面状态放 `AppModel` 或对应 Store；不要把业务状态塞进 `@State` 只在单页里复制。
- `AppRouter` 只负责导航与路由参数，不负责网络。

## 6. 常见任务配方

### 新增一个页面

1. 在 `Bgmori/Features/<模块>/` 新建 `XxxView.swift`。
2. 需要导航时在 `AppRouter.Route` 加 case，并在 `RootView.swift` 的 `RouteView` switch 里映射。
3. 需要新栏目时同时更新 `AppSection`、`phoneTabs`、Mac 侧栏和 `RootView`。
4. 页面必须有加载态、空状态、错误重试；网络失败要有回退或 Safari 入口。
5. 用 `SectionHeader`、`SectionCard`、`EmptyStateView`、`LoginPromptView` 等现有组件，不要复制一套。
6. 两端构建；iPhone 17 浅/深色截图；Mac 检查窗口布局。

### 新增一个 API 端点

1. DTO 放 `Core/Models/Models.swift`，遵循 `Decodable, Sendable`；字段用可选值兜底。
2. 在 `APIClient+Endpoints.swift` 加方法；读取用 `requestData`/`decode`，需要缓存时用 `cachedValue` 或对应 `cachedXxx`。
3. 写请求要明确是否带鉴权、是否允许重试、是否走 ECH；不要把凭证发往镜像。
4. 在 `tests/` 加解码/缓存测试；用真实路由或脚本跑一次线上数据。
5. 如果官方 API 没有该能力，不要伪造接口；使用匿名 HTML 只读并保留 Safari 回退。

### 新增一个设置项

1. `Core/Settings/AppSettings.swift` 加属性、`didSet { save() }`、`init` 读取、`save()` 写入。
2. 在 `Features/Settings/SettingsView.swift` 加分组与控件；使用 `@Bindable` 或 `model.settings`。
3. 设置变化需要立即影响其他页面时，在 `AppModel` 观察或在视图读取同一 settings 实例。
4. 需要跨启动保持的复杂结构用 Codable + UserDefaults data；不要新建第二套配置系统。

### 改 UI / Liquid Glass

- 颜色只用 `Color.bgm*` 语义色；不要写死白底、黑字或浅色渐变。
- 系统导航栏、工具栏、Sheet 材质优先；自定义玻璃只用于浮动控制层。
- 同屏自定义玻璃不超过 2 组；禁止玻璃叠玻璃。
- iPhone 与 Mac 分别检查；Mac 用 `bgmDesktopContent` 控制阅读宽度。
- 检查浅色/深色、Dynamic Type、VoiceOver 标签、Reduce Transparency、Reduce Motion。
- 顶部搜索/筛选、放送周历、吐槽筛选、进度操作可以保留玻璃层级；正文和次要操作保持轻量。

### 改 HTML 解析

- 解析器在 `Core/Social/`；选择器要容错，失败返回空结果并让调用方显示 Safari 回退。
- 不要给社交请求加 Cookie；不要发帖、回帖、点赞。
- 用 `tests/SocialTests.swift` 的 fixture 覆盖结构变化；再用 `bash scripts/test-social.sh --live` 跑真实日志。

### 新增深链

1. `AppRouter.handle(url:)` 解析 `bgmori://` host。
2. 需要新 scheme 时改 `project.yml` 的 `CFBundleURLTypes`，不要手改 pbxproj。
3. 测试 `bgmori://subject/8`、`bgmori://episode/1027`、`bgmori://user/sai`。

### 改追番提醒

- 计划生成：`Core/Storage/AiringReminderPlan.swift`
- 通知投递：`Core/Storage/NotificationManager.swift`
- 前台刷新：`AppModel+Reminders.swift`
- 设置 UI：`Features/Settings/ReminderSettingsView.swift`
- 验证：`bash scripts/test-reminders.sh`；注意夜间免打扰、单作排除、账号/收藏变化后的撤销。

### 新增验收截图

- 长期保留的截图放 `docs/screenshots/<主题>/`，附 `README.md` 说明设备、外观、验证边界。
- 临时截图放 `build/tmp/`，检查后删除；不要长期堆在 `/tmp/bgmori*`。
- UI 测试报告只写 `build/ui-results/<名称>/`；`BGMORI_UI_RESULT_DIR` 必须是该目录下尚不存在的直接子目录。
- 更新 README 时只引用已提交的正式截图。

## 7. 网络与 ECH

- 所有 API 请求必须带 `APIClient.userAgent`；不要自己拼 URLSession。
- `URLRequest.assumesHTTP3Capable = false` 是刻意保留的：部分网络下 `bgm.tv` 的 QUIC/HTTP3 会卡住。
- 有系统代理时优先代理官方；无代理时优先 ECH；失败冷却与网络变化后重新评估。
- 凭证只发官方或明确配置的自定义服务，绝不发社区镜像。
- ECH 只使用项目内维护的 Cloudflare IPv4 入口和连接成功后学习到的入口；**不要重新引入外部地址清单或第三方仓库依赖**。
- 严格 ECH：直接连 Cloudflare IP、TLS 1.3、真实域名证书、物理接口绑定、`ECHAccepted`；失败直接报错，不降级为明文 SNI、普通连接或镜像。
- `.ech.invalid` 是应用内部线路标记，不能交给系统 DNS 或外部浏览器。
- 验证：`bash scripts/test-ech.sh --live` 必须同时看到握手接受、Cloudflare `sni=encrypted`、物理接口三项证据。HTTP 成功不等于 ECH 成功。

## 8. 安全、隐私与来源

- **绝不**把 OAuth Secret、Access Token、Refresh Token、Cookie、密码、验证码写进仓库、日志、截图或注释。
- 登录只保留邮箱、密码、图片验证码；密码不落盘；令牌与官网会话只存 Keychain。
- 官网会话 Cookie 仅用于取消条目收藏的网页请求，只发往 `bgm.tv` 或 ECH 线路；退出登录立即删除，不扩展到社交写操作。
- 社交页面保持匿名 HTML 只读；不要给社交请求加 Cookie。
- 日志不要打印完整 URL 查询参数中的 code/token，也不要打印响应体。
- 测试不要使用真实账号密码；真实网络验收最多读取登录页与验证码。
- `Info.plist` 的 `BGMApiClientSecret` 保持空字符串；需要内置密钥时先改 Worker 代理。
- **来源规则：** 不要复制其他客户端仓库的实现或地址清单；官方 API/网页文档可以引用，第三方库链接只能出现在历史规划中，不能成为运行时依赖。

## 9. 验证矩阵

改完代码至少跑对应项：

| 改动 | 必跑 |
| --- | --- |
| 任意 Swift 代码 | iPhone 17 模拟器 Debug 构建 + Mac Debug 构建 |
| UI / 布局 | 两端构建 + iPhone 浅/深色截图 + Mac 窗口检查 |
| Go / ECH | `(cd Native/ECH && go test -race ./...)` + `bash scripts/test-ech.sh`；网络相关加 `--live` |
| 收藏 / 缓存 | `bash scripts/test-cache.sh` |
| 分类 / 筛选 | `bash scripts/test-categories.sh --live` |
| 搜索 / 返回 / 日志 | `bash scripts/test-navigation.sh` |
| 完整壳层 / 浅深色 | `bash scripts/test-shell-ui.sh all` |
| 社交 HTML | `bash scripts/test-social.sh --live` |
| 镜像 / 线路 | `bash scripts/test-mirrors.sh --live` |
| 连接 / 代理 / DNS | `bash scripts/test-connections.sh --live` |
| 登录 / 取消收藏 | `bash scripts/test-web-login.sh --live` + `bash scripts/test-cache.sh` |
| 提醒 | `bash scripts/test-reminders.sh` |

存储维护：

```bash
python3 scripts/maintain-dev-storage.py          # 预览
python3 scripts/maintain-dev-storage.py --apply  # 永久回收过期开发产物
```

**完成定义：** 两端构建通过；相关脚本通过；UI 改动有截图；文档/截图索引已更新；没有密钥；没有无关 diff；在回复里写清实际跑过的命令与结果。

## 10. 已知坑

- **不要用** `find ~/Library/Developer/Xcode/DerivedData/Bgmori-* | head -1` 找安装包。DerivedData 路径取决于工程绝对路径，多个 checkout 的 Bundle ID 都是 `com.yaron.bgmori`，很容易装到旧构建。统一走 `scripts/build-install-ios.sh`，它会比对哈希与构建号。
- `Bgmori.xcodeproj` 不入库；手动 `xcodebuild` 前先跑 `bash scripts/check-project-sync.sh`。
- legacy `/calendar` 的封面是 `http://`，必须升级 HTTPS。
- 搜索 `nsfw` 不传等于包含 R18；展示逻辑要显式过滤。
- 收藏的 `ep_status` 只对书籍有效；动画进度走章节接口。
- `updated_at` 不可靠，同步是全量对账，不要改成增量游标。
- 官方 API v0 没有删除条目收藏；应用内取消收藏用官网会话调用 `/subject/{id}/erase_collect?gh=...`，之后必须用 `GET /v0/users/-/collections/{id}` 复核。
- HTML 选择器会随 Bangumi 改版失效；解析失败必须回退 Safari，不要静默返回空列表。
- 部分网络下 HTTP/3 会卡住；不要移掉 `assumesHTTP3Capable = false`。
- ECH 不能降级为普通 SNI 或镜像；验收必须看 `sni=encrypted` 与物理接口。
- 不要为了“看起来更原生”改回自绘底栏、凸起圆泡或放大透镜；当前是系统五栏 Tab Bar。

## 11. 提交、发布与文档

- 提交用 Conventional Commits，一个提交只做一件事。
- 提交前检查 `git status` 没有 `.DS_Store`、`xcuserdata`、密钥、`build/`。
- 不要 force push `main`；不要擅自改 Bundle ID、Team、URL Scheme、deployment target。
- 发布版本：`MARKETING_VERSION` 在 `project.yml`；Release 构建 Mac 为 ad-hoc 签名 zip，iOS 为未签名 IPA，iPhone 必须自签。
- 发布后更新 `README.md` 的下载表与 `SECURITY.md` 的漏洞报告方式。
- 设计记录：`docs/DESIGN-REFRESH.md`、`docs/MACOS-DESIGN.md`；`docs/PLAN.md` 是历史方案，实际实现以 README/AGENTS 为准，不要按 PLAN 引入 GRDB/Nuke/SwiftSoup。
- 截图索引：`docs/screenshots/readme/README.md`。

## 12. 给不同代理的备注

- **Codex / Claude Code / Cursor：** 从仓库根目录启动；先读本文件，再读对应功能文件。
- **Copilot：** 读 `.github/copilot-instructions.md`；完整规则仍在本文件。
- **Gemini CLI：** 读 `GEMINI.md`；完整规则仍在本文件。
- **上下文预算：** 不要一次读取 `docs/screenshots/` 的几百 MB 图片；先读目录下 `README.md`，只打开必要截图。
- **搜索：** 优先用 `rg`/`search_files` 找符号，再 `read_file` 精确阅读；不要整文件粘贴到对话。
- **不确定时：** 先问用户，或先跑基线构建；不要猜 API 形状、页面结构或设计意图。
