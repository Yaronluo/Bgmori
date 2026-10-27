# AGENTS.md

本文件是给 AI 编码代理（Claude Code、Codex、Cursor、Copilot、DeepSeek Harness 等）看的项目说明书。人类开发说明见 `README.md`。

## 项目是什么

**Bgmori**：Bangumi 的非官方第三方客户端，原生 SwiftUI，同时支持 iPhone 与 Mac。

- 部署目标：iOS 27 / macOS 27（不要擅自下探）
- 构建工具：Xcode 27.1 / Swift 6
- UI、缓存和 HTML 解析保持原生实现；为实现用户要求的国内 ECH 直连，增加 **Go 标准库静态连接层**（2026-10-27）。无外部 Go 模块、不需要额外服务器；构建需要 Go 1.27+，Xcode 会执行 `scripts/build-ech-library.sh`。不要再将项目描述为零运行时依赖。
- 工程文件由 **XcodeGen** 生成：改工程设置请改 `project.yml`，然后运行 `xcodegen generate`，不要手改 `project.pbxproj`
- 设计基调：Apple 风格 + Liquid Glass，优先使用系统导航栏/Sheet/工具栏材质

## 当前适配与验收范围

用户指定的当前范围（2026-10-25）：

- **iPhone：只需满足标准版 iPhone 17，使用 iOS 27.0 模拟器。** 默认只保留、启动和验证这一台 iPhone 模拟器。
- **Mac：只需满足用户当前这台 Mac。** 当前设备为 Mac14,2、Apple M2、24 GB 内存，运行 macOS 27.0.1；构建与运行选择 `My Mac`（arm64）。
- 后续开发、布局验收、性能检查和截图均以上述范围为准；未经用户另行要求，不扩展机型矩阵，不创建其他 iPhone 模拟器或下载新运行时。
- 本约束是当前验收范围，不改变 iOS 27 / macOS 27 deployment target、Bundle ID 或已有功能。历史设计文档中的其他测试机型不代表当前要求。

## 常用命令

```bash
# 生成 Xcode 工程（修改 project.yml 或增删源文件后）
xcodegen generate --spec project.yml --project .

# iOS 模拟器构建
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO build

# macOS 构建
xcodebuild -project Bgmori.xcodeproj -scheme Bgmori \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

模拟器调试（构建 → 安装 → 启动 → 截图，在要测试的 checkout 里执行）：

```bash
bash scripts/build-install-ios.sh --route subject:8 --screenshot /tmp/bgmori.png
```

脚本把 DerivedData 固定为当前 checkout 的 `build/DerivedData-ios`，构建后校验模拟器里安装的二进制哈希与构建号都和本次构建一致，再启动。**不要**用 `find ~/Library/Developer/Xcode/DerivedData/Bgmori-*/… | head -1` 找安装包（原因见「已知坑」）。

`BGMORI_ROUTE` 是 Debug 专用路由，支持 `home`、`categories`、`categories:类型ID`（1 书籍 / 2 动画 / 3 音乐 / 4 游戏 / 6 三次元）、`calendar`、`library`、`search:关键词`、`subject:ID`、`tag:名称`、`episode:ID`、`comments:ID`、`blog:ID`、`group:name`、`topic:ID`、`timeline:用户名`、`index:ID`、`settings`、`login`。发布构建中不存在。

## 目录

```
Bgmori/App/          入口、Root Shell、路由、AppModel
Bgmori/Core/API/     APIClient、端点、限流、错误
Bgmori/Core/Auth/    官网账号登录、临时会话、Keychain
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
- 登录仅保留邮箱、密码、图片验证码；不再提供 OAuth 配置或手动 Token 入口。密码不保存，生成的个人令牌放在 Keychain。
- `Info.plist` 中的 `BGMApiClientSecret` 保持空字符串；发布前如要内置，必须改用 Worker 代理。
- 社交页面继续匿名 HTML 只读，禁止给社交请求加 Cookie、发帖或点赞。用户于 2026-10-27 明确授权账号密码登录：仅隔离的登录会话可临时使用 Cookie 获取验证码、登录及管理本应用生成的个人令牌，不得扩展到社交写操作。
- 日志里不要打印完整 URL 查询参数中的 code/token。

## 验证要求

改完代码至少做：

1. iPhone 17 / iOS 27.0 模拟器构建通过；
2. 当前这台 Mac（My Mac / arm64）构建通过；
3. 如果改了 UI，在 iPhone 17 模拟器上截图检查浅色/深色；Mac UI 在当前这台 Mac 上检查；
4. 如果改了 API/HTML 解析，用真实数据跑一次对应页面，并在解析失败时保留 Safari 回退。

## 已知坑

- ECH 线路使用 Go TLS 1.3，必须确认 `ECHAccepted`，并通过真实域名证书验证；禁止降级为明文 SNI 冒充 ECH。
- `.ech.invalid` 域名是应用内部线路标记，绝不能交给系统 DNS 或外部浏览器。严格 ECH 模式禁止退回普通连接或镜像。
- 国内直连验收使用 `bash scripts/test-ech.sh --live`，需要 Cloudflare `sni=encrypted`、连接库确认及物理网卡绑定三项证据。不要把 HTTP 成功或经过代理的连接当作国内直连证据。

- 用户于 2026-10-27 明确要求使用 iOS 系统原生底栏和内嵌横向胶囊选中态；当前采用原生 `TabView`，保留五个栏目。早期模拟器出现过图标重影，需检查当前浅深色截图；不要因此擅自改回自绘底栏、凸起圆泡或放大透镜。
- 部分网络环境下 `bgm.tv` 会走 QUIC/HTTP3 卡住；`URLRequest.assumesHTTP3Capable = false` 是刻意保留的。
- legacy `/calendar` 返回的图片是 `http://`，必须升级 https。
- 搜索 `nsfw` 不传等于包含 R18；审核/展示逻辑要显式过滤。
- 收藏的 `ep_status` 只对书籍有效；动画进度走章节接口。
- `updated_at` 不可靠，同步策略是全量对账，不要改成增量游标。
- HTML 选择器会随 Bangumi 改版失效；解析失败必须回退 Safari，不能崩。
- **别用 `find ~/Library/Developer/Xcode/DerivedData/Bgmori-*/… | head -1` 找安装包。** DerivedData 目录名由工程绝对路径决定，每个 checkout / worktree 各一份，而所有副本的 Bundle ID 都是 `com.yaron.bgmori`；`head -1` 常常命中主工作树（更早）的产物，结果就是「编了新代码、装进模拟器测的却是旧 App」，且启动后看不出来（版本号恒为 `1.0.0 (1)`）。统一走 `scripts/build-install-ios.sh`：DerivedData 固定在当前 checkout 的 `build/DerivedData-ios`，装完比对二进制哈希，启动的构建号会显示在设置页版本里。
- 新增/删除源文件后忘记 `xcodegen generate`，工程会静默跳过新文件：编译照样成功，功能却还是旧的。`scripts/check-project-sync.sh` 专门拦这种情况，`build-install-ios.sh` 已内置该检查。

## 提交

- 一个提交只做一件事；消息用 Conventional Commits，例如 `feat: add seasonal shelf`、`fix: handle nil episode airdate`。
- 提交前确认 `git status` 没有 `.DS_Store`、`xcuserdata`、密钥文件。
- 不要 force push `main`。

## 与 Codex 协作的额外约定

- Codex 会从仓库根目录读取本文件；启动时请把工作目录设为仓库根目录（有 `AGENTS.md` 的那一层）。
- **默认用中文回复用户**，代码、命令、变量名保持英文。
- 开始改代码前，先快速读 `README.md` 和本文件；必要时先跑一次基线构建，确认当前是绿的。
- **除非用户明确说“提交/推送”，否则不要 `git commit`、`git push`、开 PR。**
- 改完必须实际跑构建（iPhone 17 / iOS 27.0 模拟器 + 当前这台 Mac），并在回复里写清楚构建结果；UI 改动要附模拟器截图。
- 不要伪造线上登录结果、保存密码或把真实凭证用于测试。真实网络验收可以只获取登录页和验证码；完整账号登录需要用户本人在应用内输入，报告中应说明验证边界。
- 不要擅自升级 deployment target、引入 ECH 连接层之外的第三方依赖、改 Bundle ID / Team / URL Scheme。
- 不要为了“让编译过”而删掉功能、吞掉错误或把测试改成永远通过；要修根因。
- 若 HTML 解析失效，保留 Safari 回退，不要静默返回空列表。
