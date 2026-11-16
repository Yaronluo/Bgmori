# Bgmori — iPhone / Mac Bangumi 客户端执行方案

> 当前验收范围以根目录 `AGENTS.md` 为准：仅标准版 iPhone 17（iOS 27.0 模拟器）与用户当前这台 Mac；下文保留的多机型测试矩阵是历史规划。
> 实现说明（2026-10）：最终版本按“最新系统 + 私人使用”落地为 iOS 27 / macOS 27，采用零第三方依赖（原生 URLSession/JSON 缓存、正则 HTML 适配、系统原生 Tab Bar）。本文件保留最初的技术论证与排期，实际实现详见根目录 README；下文出现的 GRDB / Nuke / SwiftSoup 均为历史选型。

> 版本：v1.0 · 2026-10-25  
> 目标：做一款原生、克制、真正有 Liquid Glass 质感的 Bangumi 第三方客户端；先吃透官方 API，再用可降级的网页适配层补齐内容。  
> 假设：单人开发、已有 Apple Developer 账号、以 App Store 发行为目标。

---

## 0. 结论先行

| 项目 | 决策 | 理由 |
| --- | --- | --- |
| 最低系统 | **iOS 26.0 / macOS 26.0** | Liquid Glass 的公开 API 从 26 开始；下探 18 会显著增加设计与测试成本 |
| 工程形态 | **单 Universal App：iPhone + iPad + Mac** | 一套 SwiftUI 代码，Mac 用原生 `NavigationSplitView`，不做 Catalyst |
| 语言/并发 | **Swift 6 + 严格并发 + Observation** | 长期可维护；网络/数据库/同步全部 actor 化 |
| 持久化 | **GRDB / SQLite + FTS5** | 收藏同步、复杂筛选、全文搜索、Widget 只读访问都比 SwiftData 稳 |
| 图片 | **Nuke** | 磁盘缓存、降采样、预取、内存控制成熟 |
| 网页解析 | **SwiftSoup**，仅匿名只读 | 评论/小组/日志/时光机没有官方 API；不做 Cookie 登录 |
| 后端 | **v1.0 无必需后端** | 隐私、成本、延迟最优；OAuth secret 先内置，发布前可选 Cloudflare Worker |
| 范围 | 官方 API 核心全量 + 吐槽只读；重社交内容放 v1.1 | “完全接入”在官方 API 下只能到约 70%，必须分层 |
| 排期 | **全职 15 周（含缓冲）**；业余 24–28 周 | 第 7 周出 MVP，第 13 周进 TestFlight |
| 发行 | App Store（先全球，后中国区）+ TestFlight | Universal Purchase；中国区需 App 备案/ICP |
| 变现 | 免费；后续可选打赏 | 用免费 API 收费需 Bangumi 许可，不建议早期碰 |

### 三个必须先接受的事实

1. **液态玻璃不是“画”出来的。** 系统导航栏、Tab Bar、工具栏、Sheet、Menu 在 iOS 26 上会自动玻璃化；自定义玻璃只应该出现在“浮在内容上的控制层”。满屏毛玻璃卡片既不像 Apple，也会掉帧。
2. **“完全接入 Bangumi”官方 API 做不到 100%。** 评论、小组、日志、提醒、好友动态、维基编辑都没有公开写接口；能匿名只读的用 HTML 适配，不能的只能跳 Safari。
3. **App Store 的三颗雷：商标、UGC、R18。** 必须自有品牌 + “非官方”声明；必须有举报/屏蔽；审核版必须强制关闭 NSFW。

---

## 1. 产品定义

### 1.1 一句话定位

> 给 ACGN 收藏者的原生 Bangumi 客户端：**看得快、记得住、改得动。**

- 看得快：首页/放送/搜索/详情都在 2 次点击内完成。
- 记得住：收藏、评分、标签、进度、吐槽本地即时可见，离线也能改。
- 改得动：进度一键 +1、批量标记、长按菜单、键盘快捷键。

### 1.2 目标用户

| 用户 | 核心诉求 | 对应设计 |
| --- | --- | --- |
| 重度收藏者（500+） | 快速筛选、批量改进度、找旧番 | 收藏库多条件筛选、FTS5 本地搜索、网格/列表切换 |
| 新番追更者 | 今天看什么、看到第几话 | 每日放送、继续观看、进度环、本地通知 |
| Mac 用户 | 大屏整理、多窗口、键盘 | 三栏布局、多窗口、⌘ 快捷键、右键菜单 |
| 轻度游客 | 不登录先逛 | Guest Mode，收藏时再引导登录 |

### 1.3 非目标（明确不做）

- 不做站内社交发布：发吐槽、回帖、发日志、发小组话题。
- 不做资源播放/下载/字幕。
- 不自建账号体系、不做云同步（Bangumi 就是账号与数据源）。
- 不做 R18 内容分发（审核版）。
- 不做“网页套壳”：核心页面必须原生。

### 1.4 关键用户旅程

1. **首次使用**：打开 → 游客浏览今日放送 → 点收藏 → 登录 → 回到原页面继续 → 设置偏好。
2. **追番**：首页“继续观看” → 条目详情 → 点第 N 话圆圈 → 自动写回 → 首页进度更新。
3. **找番**：搜索/排行榜 → 筛选（类型/年份/标签/评分） → 详情 → 收藏 + 评分 + 短评。
4. **Mac 整理**：侧边栏收藏 → 列表筛选“在看” → 双击开新窗口 → 键盘改评分/进度。

---

## 2. “完全接入”的现实边界

把能力分成四层，产品、排期、审核都按这个来：

| 层级 | 含义 | 技术手段 | 用户体验 |
| --- | --- | --- | --- |
| **A** | 官方 API 可读写 | `api.bgm.tv/v0` | 原生、离线、乐观更新 |
| **B** | 官方 API 只读 | `api.bgm.tv/v0` + legacy | 原生展示 |
| **C** | 网页匿名只读 | `bgm.tv` HTML + SwiftSoup | 原生列表，样式统一，失败回退 Safari |
| **D** | 必须登录 Cookie / 私有 API | 不做 | “在 Safari 中打开” |

### 2.1 覆盖率矩阵

| 能力 | 官方 API | 层级 | 方案 | 版本 |
| --- | --- | --- | --- | --- |
| 条目、章节、角色、人物、关联、制作人员 | ✅ v0 | A/B | 原生 | v1.0 |
| 搜索（条目/角色/人物）、排行榜、分类/年份浏览 | ✅ v0 | A/B | 原生 + 筛选面板 | v1.0 |
| 每日放送 | ⚠️ legacy `/calendar` | B | 原生；URL/字段归一化 | v1.0 |
| 收藏（想看/看过/在看/搁置/抛弃）、评分、标签、私密、短评 | ✅ v0 | A | 乐观更新 + Outbox | v1.0 |
| 章节进度（动画/三次元） | ✅ v0 | A | 单集/批量 PATCH | v1.0 |
| 书籍卷/话进度 | ✅ v0 | A | `ep_status` / `vol_status` | v1.0 |
| 用户公开资料、公开收藏 | ✅ v0 | B | 原生 | v1.0 |
| 目录（Index）读取/收藏/编辑 | ✅ v0 | A/B | 原生（按 ID 进入） | v1.1 |
| 编辑历史（Revisions） | ✅ v0 | B | 只读列表/对比 | v1.1 |
| 条目吐槽、章节吐槽 | ❌ | C | HTML 解析，只读 | v1.0 / v1.1 |
| 小组、讨论版 | ❌ | C | HTML 解析，只读 | v1.1 |
| 日志（Blog） | ❌ | C | HTML 解析，只读 | v1.1 |
| 用户时光机（公开） | ❌ | C | HTML 解析，只读 | v1.1 |
| 官方提醒/通知 | ❌ | D | 不做；仅提供本地新番提醒 | — |
| 本地新番提醒 | — | 本地 | `UNUserNotificationCenter` + 放送缓存 | v1.0 |
| 好友/关注/动态 | ❌ | D | Safari | 不做 |
| 发吐槽/回帖/发日志/发话题 | ❌ | D | Safari | 不做 |
| 维基编辑 | ❌ | D | Safari | 不做 |
| R18 | ⚠️ `nsfw` 字段 | — | 审核版强制过滤 | v1.0 |

**结论**：v1.0 把核心 A/B 层做到 100%，C 层只做“条目吐槽”（对追番决策价值最高）；目录、编辑历史、章节吐槽、小组/日志/时光机放 v1.1。这样既不虚承诺，也不会把工期拖进无底洞。

---

## 3. 平台与技术基线

| 项 | 选择 | 说明 |
| --- | --- | --- |
| IDE / SDK | Xcode 27.1，iOS 27 SDK | 当前机器已具备；部署目标 iOS 26.0 |
| 语言 | Swift 6.4，Swift 6 language mode | 严格并发；DTO `Sendable` |
| UI | SwiftUI 为主，AppKit/UIKit 少量互操作 | 窗口、菜单、触感、Web 登录 |
| 架构 | Feature + Repository + Store（`@Observable`） | 不引入重型框架 |
| 依赖 | GRDB、Nuke、SwiftSoup | 仅 3 个核心第三方库 |
| 包管理 | 本地 SPM 包 + App target | 强制分层，测试独立 |
| 配置 | `.xcconfig` + Info.plist 注入 | Secrets 不入库 |
| 最低 Mac | macOS 26.0 | Liquid Glass + 原生 SwiftUI |

### 为什么不是其他方案

- **Catalyst**：Mac 上的窗口、菜单、工具栏、键盘体验始终“像 iPad App”，且 Liquid Glass 的 Mac 表现在 Catalyst 上不自然。
- **React Native / Flutter**：玻璃质感、ProMotion、WidgetKit、App Intents、Handoff 全部要桥接；审稿风险更高。
- **SwiftData**：迁移、复杂查询、FTS5、Widget 只读连接都不如 GRDB 可控；本项目本质是“带同步的本地缓存”，SQLite 更合适。
- **自建后端**：MVP 不需要；只会增加隐私、成本和故障点。等要做推送/远程配置时再加 Worker。

---

## 4. 信息架构与导航

### 4.1 平台外壳

| 平台 | 外壳 | 说明 |
| --- | --- | --- |
| iPhone | `TabView` 5 个 Tab：首页 / 放送 / 收藏 / 搜索 / 我的 | 搜索用 `Tab(role: .search)`；`.tabBarMinimizeBehavior(.onScrollDown)` |
| iPad | `NavigationSplitView` 可折叠侧边栏 | 横屏三栏，竖屏两栏 |
| Mac | 原生 `NavigationSplitView`：侧边栏 + 内容 + 详情 | 工具栏搜索、菜单栏命令、多窗口 |

共享 `FeatureRoot` 视图；外壳只负责导航与窗口，不复制业务 UI。

### 4.2 屏幕地图

| 模块 | 页面 | 关键内容 |
| --- | --- | --- |
| 首页 | Home | 继续观看、今日放送、本季新番、排行榜、收藏概览 |
| 放送 | Calendar | 周一–周日切换、在看过滤、进度、提醒 |
| 收藏 | Library | 5 种状态、类型/排序筛选、网格/列表、搜索 |
| 搜索 | Search | 条目/角色/人物 scope、筛选、历史、标签推荐 |
| 条目 | Subject Detail | 封面 Hero、评分、标签、信息、章节、角色、制作、关联、吐槽 |
| 章节 | Episode Detail | 播出信息、进度、吐槽、上一话/下一话 |
| 人物 | Character / Person | 头像、简介、CV/作品、关联条目、收藏 |
| 我的 | Profile | 头像、签名、收藏统计、设置入口、网页主页 |
| 设置 | Settings | 外观、内容、通知、缓存、账号、关于 |
| 扩展 | Index / Blog / Group / Timeline | v1.1 只读适配 |

### 4.3 导航与状态

- 类型化路由：`enum Route: Hashable, Codable { case subject(Int), episode(Int), character(Int), person(Int), user(String), index(Int), web(URL) }`。
- 每个 Tab 独立 `NavigationStack(path: $router.path[.home])`；Mac 用 `selection` + `detail`。
- 深链：`bgmori://subject/8`、`bgmori://episode/1027`、`bgmori://user/sai`、`bgmori://search?q=...`。
- 状态恢复：`@SceneStorage` 存 Codable 路由数组；Mac 窗口恢复选中项。
- 跨设备：Handoff 传递 `NSUserActivity`（v1.0）。

---

## 5. Liquid Glass 设计系统

### 5.1 五条原则

1. **内容优先**：玻璃只属于控制层；封面、文字、列表用实色/材质底。
2. **系统优先**：能用系统 Tab Bar、导航栏、工具栏、Sheet、Menu 的玻璃，绝不自己画。
3. **一层玻璃**：同屏自定义玻璃不超过 2 组；禁止玻璃叠玻璃。
4. **透明要有意义**：玻璃背后必须有内容（封面、渐变、滚动内容）；背后是纯色就用不透明填充。
5. **可降级**：Reduce Transparency / Increase Contrast / Reduce Motion 下必须优雅退化。

### 5.2 玻璃层级

| 层级 | 内容 | 实现 |
| --- | --- | --- |
| L0 | 页面背景、卡片、列表、图片 | 系统背景色 / 封面取色渐变；**不加玻璃** |
| L1 | Tab Bar、导航栏、工具栏、侧边栏、Sheet、Menu | 系统自动（iOS/macOS 26） |
| L2 | 浮动收藏按钮、进度条、周选择器、筛选胶囊 | `GlassEffectContainer` + `glassEffect`，每屏 1–2 组 |
| L3 | 弹窗、确认框、Toast、Popover | 系统材质；不自定义玻璃 |

### 5.3 Design Tokens

| 类别 | 规范 |
| --- | --- |
| 品牌色 | Bangumi 粉 `#F09199`；深色模式提亮到 `#F4A7AE`，仅用于 tint/强调 |
| 类型色 | 书籍 `#C58B4A`、动画 `#E36A8A`、音乐 `#6C7BD9`、游戏 `#4FAE7C`、三次元 `#7A8A99` |
| 状态色 | 想看 `#5B8DEF`、看过 `#34A853`、在看 `#F09199`、搁置 `#F5A623`、抛弃 `#9AA0A6` |
| 语义色 | success / warning / danger / ratingGold `#F5B301`；全部提供深色变体 |
| 字体 | SF Pro（系统）；中文自动 PingFang SC；数字用 `.monospacedDigit()` |
| 字阶 | LargeTitle 34 / Title 28 / Title2 22 / Title3 20 / Headline 17 / Body 17 / Callout 16 / Subhead 15 / Footnote 13 / Caption 12 |
| 间距 | 4 / 8 / 12 / 16 / 20 / 24 / 32；8pt 网格 |
| 圆角 | 10 / 14 / 18 / 24 / 28；统一 `.continuous` |
| 阴影 | 仅浮动层：black 8%，radius 20，y=8；玻璃本身不叠重阴影 |
| 动效 | 标准 spring(response: 0.38, dampingFraction: 0.82)；快交互 `.snappy`；页面转场 `.smooth` |
| 触感 | 收藏切换 `.selection`；进度 +1 `.impact(.light)`；完成一话 `.success` |

### 5.4 关键界面规范

#### 首次启动

- 一页式欢迎：品牌标记 + 一句话说明 + “使用 Bangumi 登录” / “先逛逛”。
- 底部小字：非官方、数据来自 Bangumi、隐私政策链接。
- 不做多页轮播；不强制登录；登录成功回到刚才的页面。

#### 首页

- 顶部大标题 + 头像；背景是极淡的品牌粉径向渐变，不抢内容。
- “继续观看”：横向卡片，封面 3:4，底部细进度条；点击直达条目并定位到下一话。
- “今日放送”：按当前星期取 `calendar`，最多 10 条；右侧“全部”。
- “本季新番”：`/v0/subjects?type=2&year=&month=&sort=date`；按季度 chips 切换。
- “排行榜”：`sort=rank`；前三名给数字徽章。
- 玻璃：不使用自定义玻璃；导航栏/大标题由系统处理。

#### 放送（Calendar）

- 顶部一个**玻璃胶囊周选择器**（L2，单组玻璃）：周一–周日，今天高亮，左右滑动切换。
- 列表：封面 56×76、标题、更新信息、进度环、在看标记。
- 过滤：全部 / 我在看；空状态给“去收藏”。
- 本地通知：对“在看”且今天放送的条目，默认 20:00 提醒（可关）。

#### 条目详情（核心门面）

- Hero：封面 120×170 + 同图高斯模糊铺底（`MeshGradient` 取色），高度约 320；`backgroundExtensionEffect()` 让封面延伸到导航栏下。
- 标题区：中文名 + 原名 + 年份/平台/话数；评分环 + 排名 + 评分人数。
- 标签：横向 chips，点击进入按标签搜索。
- 收藏按钮：底部浮动玻璃胶囊（L2），显示当前状态；点开 Sheet 编辑。
- 章节：分段“本篇 / SP / OP / ED”；每行圆圈可点，长按菜单“标记到这话 / 取消”。
- 角色/制作/关联：横向卡片；点击进人物页。
- 吐槽：先展示 3 条 + “查看全部”（C 层）；加载失败显示“在 Safari 中查看”，不阻塞页面。
- 滚动时底部玻璃条保持可见；Tab Bar 随滚动最小化（系统行为）。

#### 收藏库

- 顶部分段：全部 / 想看 / 在看 / 看过 / 搁置 / 抛弃。
- 筛选菜单：类型、排序（最近更新/评分/放送日期/标题）、网格/列表。
- 卡片：封面、标题、进度环（`ep_status / total`）、评分、状态点。
- 长按：改状态、+1 话、在浏览器打开、分享。
- 玻璃：仅导航栏筛选按钮；卡片一律不玻璃。

#### 搜索

- 系统搜索栏（L1）+ scope（条目/角色/人物）。
- 筛选 Sheet：类型、年份、标签、评分、排序；审核版 `nsfw` 永远传 `false`，个人构建才允许通过编译开关放开。
- 结果网格；空结果给“去 Bangumi 网页搜索”。
- 历史记录本地保存；支持“清空”。

#### 我的 / 设置

- 资料头：头像、昵称、签名、加入时间（能拿到就显示）；统计用 5 次 `limit=1` 的收藏请求取 `total`。
- 设置用系统 `Form`；外观提供“跟随系统 / 浅色 / 深色”，不提供“玻璃强度”这种非 Apple 的开关。
- 关于：非官方声明、开源许可、隐私政策、反馈邮箱、Bangumi 主页。

#### Mac

- 侧边栏玻璃由系统提供；内容区用 `Table`/`List`，详情用 `ScrollView`。
- 工具栏：搜索、刷新、筛选、排序；`⌘R` 刷新、`⌘F` 搜索、`⌘1–5` 切换分区、`⌘,` 设置。
- 双击条目开新窗口（`WindowGroup(for: Subject.ID.self)`）；右键菜单完整。
- 窗口最小 960×640；默认 1280×820；支持全屏/分屏/Stage Manager。
- 不用自定义玻璃覆盖内容；Mac 的“玻璃感”来自侧边栏、工具栏、菜单和窗口材质。

### 5.5 玻璃组件骨架

```swift
struct GlassSurface<Content: View>: View {
    var shape: AnyShape
    var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)),
        @ViewBuilder content: () -> Content
    ) {
        self.shape = shape
        self.content = content()
    }

    var body: some View {
        if reduceTransparency {
            content
                .background(Color.bgmSurface, in: shape) // DesignSystem 中按平台映射
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
```

使用规则：

```swift
// 主操作：系统 glassProminent，带品牌 tint
Button("想看") { /* action */ }
    .buttonStyle(.glassProminent)
    .tint(.brandPink)

// 次级操作：玻璃 + interactive，必须放在 GlassEffectContainer 内
GlassEffectContainer(spacing: 12) {
    Button { /* action */ } label: { Image(systemName: "square.and.arrow.up") }
        .buttonStyle(.glass)
    Button { /* action */ } label: { Image(systemName: "ellipsis") }
        .buttonStyle(.glass)
}
```

注意：

- `glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)` 均为 iOS 26 / macOS 26 API，visionOS 不可用。
- `interactive()` 只给可点击元素；静态玻璃不要加。
- 同一 `GlassEffectContainer` 内的元素会互相融合/变形；用 `glassEffectID(_:in:)` 做状态切换的 morph。
- Sheet 内部不要再套自定义玻璃；系统 Sheet 已有材质。

### 5.6 封面取色

- 下载 32×32 缩略图，取平均色 + 提高饱和度，生成 3 个相近色。
- 详情页顶部用 `MeshGradient`（iOS 18+）铺 0.35（浅色）/0.5（深色）透明度，叠一层 `ultraThinMaterial` 保证文字对比度。
- 取色结果按 subject id 缓存到内存；避免每次滚动重算。
- Reduce Motion 时不做颜色渐变动画。

### 5.7 无障碍与降级

| 场景 | 处理 |
| --- | --- |
| Reduce Transparency | 玻璃 → 不透明 `secondarySystemBackground` + 1px 边框 |
| Increase Contrast | 文本/图标提升对比；玻璃边缘加描边 |
| Reduce Motion | 关闭 zoom 转场、Mesh 动画、数字滚动；用淡入 |
| Dynamic Type | 全部语义字体；AX 字号下网格自动变单列 |
| VoiceOver | 卡片合成 label：“《名称》，评分 8.3，在看，进度 13/25”；自定义动作“更新进度” |
| 色盲 | 状态同时用图标 + 文字，不只靠颜色 |
| 键盘 | iPad/Mac 全键盘导航；焦点环清晰；Esc 关闭 |
| 本地化 | 首发 zh-Hans + en；v1.1 加 ja；日期/数字用 `FormatStyle` |

### 5.8 性能预算

- 冷启动 < 1.2s（iPhone 15 级别），< 2s（iPhone 11）。
- 滚动稳定 120Hz（ProMotion），无 >16ms 卡顿；玻璃同屏 ≤ 2 组。
- 首页首屏 ≤ 4 个网络请求；条目详情 ≤ 5 个；列表分页 50。
- 内存常驻 < 250MB；图片内存缓存 100MB，磁盘 500MB。
- 数据库查询 < 16ms；FTS5 搜索 1 万条 < 50ms。

---

## 6. 技术架构

### 6.1 模块图

```
BgmoriApp（App target）
├─ AppShell        场景、窗口、路由、命令、环境注入
├─ Features        首页/放送/搜索/收藏/条目/章节/人物/我的/设置/社交
├─ DesignSystem    Tokens、GlassKit、通用组件、动效、无障碍
└─ CoreKit         网络、模型、认证、数据库、同步、图片、HTML 适配、日志
```

本地 SPM 包：

- `BgmoriCore`：无 UI，可单测。
- `BgmoriDesignSystem`：颜色/字体/组件，可预览。
- `BgmoriFeatures`：业务视图与 Store，依赖前两者。
- App target：只做组装、Info.plist、资源、扩展。

依赖方向：`Features → DesignSystem + Core`；`Core` 不反向依赖 UI。

### 6.2 目录结构

```
Bgmori/
├─ App/
│  ├─ BgmoriApp.swift
│  ├─ AppEnvironment.swift
│  ├─ AppRouter.swift
│  └─ Commands/
├─ Packages/
│  ├─ BgmoriCore/
│  │  ├─ Networking/
│  │  ├─ Models/
│  │  ├─ Auth/
│  │  ├─ Database/
│  │  ├─ Sync/
│  │  ├─ Images/
│  │  ├─ Scraping/
│  │  └─ Observability/
│  ├─ BgmoriDesignSystem/
│  └─ BgmoriFeatures/
├─ Extensions/
│  ├─ BgmoriWidgets/
│  └─ BgmoriIntents/
├─ Tests/
│  ├─ Fixtures/
│  ├─ SnapshotTests/
│  └─ UITests/
└─ docs/
```

### 6.3 网络层

```swift
actor APIClient {
    func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T
}
```

| 组件 | 职责 |
| --- | --- |
| `Endpoint` | path、method、query、body、是否鉴权、缓存策略、重试策略 |
| `AuthInterceptor` | 附加 Bearer；401 时单飞刷新一次并重试 |
| `RateLimiter` | 全局令牌桶：交互请求 2 req/s，后台 1 req/s，HTML 0.5 req/s |
| `RequestCoalescer` | 同 URL 的并发 GET 只发一次 |
| `RetryPolicy` | 408/429/5xx/网络错误；指数退避 0.5/1/2s + jitter；最多 3 次 |
| `ResponseCache` | URLCache + SQLite TTL；按资源类型分 TTL |
| `FlexibleDecoder` | snake_case、ISO8601（含小数秒）、`yyyy-MM-dd`、Unix 时间戳、未知枚举兜底 |
| `APIError` | unauthorized / forbidden / notFound / rateLimited / server / decoding / offline |
| `UserAgent` | `Bgmori/1.0 (iOS) (https://github.com/<you>/bgmori; <email>)` |

TTL 建议：

| 资源 | TTL |
| --- | --- |
| 条目详情 | 24h |
| 章节列表 | 24h |
| 每日放送 | 6h |
| 用户收藏 | 前台每次 + 10min 节流 |
| 搜索结果 | 不缓存（内存 1min） |
| 吐槽/日志/小组 | 1h |
| 图片 | 磁盘上限 500MB，自动清理 |

**限流事实**：Bangumi 服务端默认 10 分钟内 3000 次/用户（匿名按 IP），超限封 1 小时。客户端按 ≤1 req/s 的均值设计，富余很大；真正要防的是启动时并发拉取和图片风暴。

### 6.4 认证（OAuth 2.0 Authorization Code）

```
App → ASWebAuthenticationSession
   → https://bgm.tv/oauth/authorize?client_id&response_type=code&redirect_uri&state
   → bgmori://oauth/callback?code&state
   → POST https://bgm.tv/oauth/access_token (form)
   → { access_token, expires_in: 604800, refresh_token, user_id }
   → Keychain + GET /v0/me
```

要点：

- `code` 有效期 **60 秒**，回调后立即换取。
- Access Token 有效期 **7 天**；Refresh Token 会轮换，必须原子保存。
- 刷新单飞：`actor TokenStore`，同一时刻只有一个刷新任务；其余等待结果。
- 401 处理：刷新一次 → 重试原请求 → 仍失败则弹登录，不循环。
- Keychain：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`；service `com.yaron.bgmori.oauth`；不开启 iCloud 同步。
- `state` 随机校验；`ASWebAuthenticationSession` 不启用 ephemeral，让用户复用已有登录态。
- 回调 scheme 需在 Info.plist 注册；若 Bangumi 后台不接受自定义 scheme，改用 Universal Link（需域名 + AASA）。
- **client_secret 放在原生 App 里不是秘密**。MVP 可内置并混淆；发布前可选 Cloudflare Worker 代理换 token/刷新（无状态、不落库、隐私政策写明）。Bangumi 目前未提供 PKCE，这是现实限制。

### 6.5 持久化（GRDB）

| 表 | 主键 | 关键字段 | 用途 |
| --- | --- | --- | --- |
| `subject` | id | type、name、name_cn、summary、date、platform、images、infobox、tags、rating、rank、nsfw、eps、volumes、fetched_at | 条目缓存 |
| `episode` | id | subject_id、type、sort、ep、name、name_cn、airdate、duration、desc、comment_count | 章节缓存 |
| `collection` | subject_id | type、rate、ep_status、vol_status、comment、tags、private、server_updated_at、local_updated_at、sync_state | 我的收藏 |
| `episode_collection` | episode_id | subject_id、type、updated_at、sync_state | 章节进度 |
| `user` | id | username、nickname、avatar、sign | 用户 |
| `character` / `person` | id | name、images、summary、infobox、career | 人物缓存 |
| `subject_character` / `subject_person` / `subject_relation` | 复合 | subject_id、target_id、relation、order | 关联 |
| `comment_cache` | key | page、payload、fetched_at | HTML 解析结果 |
| `outbox` | id | op、subject_id、episode_id、payload、created_at、attempts、next_retry_at | 待同步变更 |
| `sync_state` | key | value | 上次全量同步等 |
| `blocked_user` | user_id | created_at | 本地屏蔽评论用户 |
| `search_history` | id | query、created_at | 搜索历史 |

- FTS5：`subject_fts(name, name_cn, summary, tags)`，触发器同步；本地搜索优先。
- 迁移：`DatabaseMigrator`，每次 schema 变更一个 identifier；禁止在迁移里做网络请求。
- Widget 共享：App Group `group.com.yaron.bgmori`；Widget 以只读 `DatabaseQueue` 打开，WAL + busy timeout。
- 数据库文件排除 iCloud 备份（缓存可重建）；Keychain 不随备份迁移。

### 6.6 同步与离线

核心原则：**SQLite 是 UI 的唯一真相，服务端是最终真相。**

```
用户操作 → 写 collection/episode_collection + 写 outbox（同一事务）
        → UI 通过 ValueObservation 立即更新
        → SyncEngine 顺序 drain outbox
        → 成功：写 server echo，删 outbox
        → 失败：保留 outbox，指数退避；4xx 标记 needsAttention
```

- **全量对账**：启动/前台/下拉刷新时拉 `/v0/users/{username}/collections` 全量（50/页），与本地合并；受 10min 节流；服务端没有的收藏删除（但有待同步的保留）。
- **不要依赖 `updated_at` 做增量**：官方 schema 明确说明修改评分/评价/进度时 `updated_at` 可能不更新。必须全量对账。
- **冲突**：同一设备基本无冲突；iPhone/Mac 同时改时，本地 pending 优先，服务端确认后覆盖；不弹复杂合并框。
- **批量进度**：`PATCH /v0/users/-/collections/{subject_id}/episodes` body `{ "episode_id": [1,2,8], "type": 2 }`；一次只能一种 type，UI 的“标记到这话”需按区间分组。
- **单集**：`PUT /v0/users/-/collections/-/episodes/{episode_id}` body `{ "type": 2 }`。
- **书架**：书籍用 `ep_status` / `vol_status`；动画/三次元用章节收藏；服务端会在章节变更后重算条目完成度，所以本地也要同步更新 `collection.ep_status`。
- **后台**：iOS `BGAppRefreshTask`（6h 一次，系统调度）；macOS 前台激活时刷新；`NWPathMonitor` 恢复网络后自动 drain。
- **账号切换/退出**：停 SyncEngine → 清 token → 清私有表/outbox → 保留公开缓存（可选）→ 重登。

### 6.7 图片

- Nuke `ImagePipeline`：内存 100MB、磁盘 500MB 上限；按大小 LRU 清理，启动/低存储时裁剪。
- 按场景取尺寸：网格 `common`(400)、列表 `small`(200)、详情 Hero `large`、全屏 `medium`(800)。
- legacy 日历返回 `http://lain.bgm.tv/...`，统一升级 https，并规范到 `r/400`。
- 封面占位：类型色渐变 + SF Symbol，不留白。
- 预取：列表滚动方向前 10 张；详情页进入前预取封面。
- 失败重试 1 次；仍失败显示占位，不弹错。

### 6.8 HTML 适配层（C 层）

```swift
protocol SocialSource {
    func subjectComments(id: Int, page: Int) async throws -> Paged<Comment>
}
```

- `HTMLClient`：独立 URLSession；UA 用 Safari 风格；1 req/2s；磁盘缓存 1h；只 GET。
- 解析器：`SubjectCommentsParser`、`EpisodeCommentsParser`、`GroupTopicParser`、`BlogParser`、`TimelineParser`，选择器集中管理。
- 已确认的选择器（2026-10 实测）：
  - 条目标题吐槽：`.item[data-item-user]`，用户名 `a.l`，评分 `.starlight.starsN`，时间 `.grey`，正文 `p.comment`。
  - 章节吐槽：`.commentList .row_reply[data-item-user]`，正文 `.reply_content .message`，表情 `img.smile[alt]`。
- 解析失败（0 条）→ 记录日志 → 显示“在 Safari 中查看”，绝不崩溃、不空白。
- 测试用固定 HTML fixture；页面结构变化时只改 parser。
- 不做 Cookie 登录：不碰提醒、好友动态、发帖；避免账号风控和审核问题。
- 合规：遵守 Bangumi 的 UA 规范；只从每台设备直连、不搭集中抓取服务；单页请求间隔 ≥2s，失败即退避。

### 6.9 BBCode / HTML 渲染

- 统一 `RichText` 模型：段落、加粗、斜体、删除线、链接、引用、代码、遮罩、图片（默认关）。
- `[mask]` / `.spoiler` → 模糊 + “点击显示”，尊重“隐藏剧透”设置。
- 链接只允许 http/https，点击前确认；`mailto` 允许。
- 图片默认不加载（评论内图片；省流量 + 避免不适内容）；用户可开。
- 表情 `(bgm38)` → 映射到本地小图或直接显示 alt 文本。
- 输出 `AttributedString`，保留可选中文本（macOS 可复制）。

### 6.10 可观测性与安全

- `os.Logger` 分 subsystem：network / db / sync / ui；所有 token、code、cookie 打码。
- MetricKit：崩溃、卡顿、启动、网络错误；不上传自定义用户数据。
- 默认零分析 SDK；App Privacy 可填“不收集”。
- ATS 全开，无例外；不做证书 pinning（避免 Cloudflare 轮换导致断网）。
- 深链白名单：只接受已知 host/scheme；不执行任意 URL。
- 分享/导出不含 token；日志文件不导出。
- `PrivacyInfo.xcprivacy`：无追踪；按需声明 UserDefaults / 文件时间等 required-reason API。

---

## 7. API 接入清单

Base：`https://api.bgm.tv`；Auth：`https://bgm.tv/oauth`。所有请求带 UA。

| 功能 | 端点 | 方法 | 鉴权 | 缓存 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 授权页 | `/oauth/authorize` | GET | — | — | Web 登录 |
| 换 token | `/oauth/access_token` | POST | — | — | form-urlencoded |
| 刷新 token | `/oauth/access_token` | POST | — | — | `grant_type=refresh_token` |
| 当前用户 | `/v0/me` | GET | ✅ | 1d | 登录后 |
| 每日放送 | `/calendar`（legacy） | GET | — | 6h | 字段/URL 归一化 |
| 浏览条目 | `/v0/subjects` | GET | — | 1h | `type` 必填；`sort=date\|rank`；`year/month/cat/platform` |
| 条目详情 | `/v0/subjects/{id}` | GET | — | 24h | 含评分分布、tags、infobox |
| 条目角色 | `/v0/subjects/{id}/characters` | GET | — | 24h | 含 CV |
| 条目制作 | `/v0/subjects/{id}/persons` | GET | — | 24h | 按 relation 分组 |
| 关联条目 | `/v0/subjects/{id}/subjects` | GET | — | 24h | 续集/前传等 |
| 章节列表 | `/v0/episodes?subject_id=` | GET | — | 24h | limit ≤200 |
| 章节详情 | `/v0/episodes/{id}` | GET | — | 24h | 含简介/时长 |
| 条目搜索 | `/v0/search/subjects` | POST | — | 内存 1min | 审核版显式传 `nsfw:false` |
| 角色搜索 | `/v0/search/characters` | POST | — | 1min | keyword |
| 人物搜索 | `/v0/search/persons` | POST | — | 1min | keyword |
| 用户资料 | `/v0/users/{username}` | GET | — | 1d | 无统计字段 |
| 用户收藏 | `/v0/users/{username}/collections` | GET | 公开/本人 | 10min | limit ≤50；含 slim subject |
| 单条收藏 | `/v0/users/{username}/collections/{subject_id}` | GET | 公开/本人 | — | 详情页补状态 |
| 新增/修改收藏 | `/v0/users/-/collections/{subject_id}` | POST | ✅ | — | 完整写入 |
| 修改收藏 | `/v0/users/-/collections/{subject_id}` | PATCH | ✅ | — | 部分字段 |
| 章节收藏列表 | `/v0/users/-/collections/{subject_id}/episodes` | GET | ✅ | 5min | limit ≤1000 |
| 批量章节 | `/v0/users/-/collections/{subject_id}/episodes` | PATCH | ✅ | — | `{episode_id:[...],type:2}` |
| 单章节 | `/v0/users/-/collections/-/episodes/{episode_id}` | PUT | ✅ | — | `{type:2}` |
| 角色详情 | `/v0/characters/{id}` | GET | — | 24h | |
| 人物详情 | `/v0/persons/{id}` | GET | — | 24h | |
| 收藏角色/人物 | `/v0/characters/{id}/collect` | POST/DELETE | ✅ | — | v1.1 |
| 目录 | `/v0/indices/{id}` + `/subjects` | GET | — | 1h | 按 ID 进入；v1.1 |
| 目录收藏 | `/v0/indices/{id}/collect` | POST/DELETE | ✅ | — | v1.1 |
| 编辑历史 | `/v0/revisions/subjects` 等 | GET | — | 1h | v1.1 只读 |

### 7.1 已知坑（务必写进代码注释/测试）

1. legacy `/calendar` 图片是 `http://lain.bgm.tv/...`，必须升级 https，否则 ATS 拦截。
2. 搜索 `filter.nsfw` 不传等于**包含 R18**；审核版必须显式 `false`，并在 UI 层再过滤 `subject.nsfw`。
3. 收藏 PATCH 的 `ep_status` / `vol_status` **只对书籍有效**；动画进度必须走章节接口。
4. 批量章节接口一次只能一种 `type`；“标记到第 N 话”要按 type 分组（已看/未看）。
5. `updated_at` 不能当增量游标（官方已注明修改评分/进度可能不更新）；必须全量对账。
6. 收藏列表 `limit` 最大 50；章节列表最大 200；章节收藏最大 1000。
7. 没有 `GET /v0/users/-/collections/{subject_id}`；用 `/v0/users/{username}/collections/{subject_id}`。
8. 收藏列表已内嵌 slim subject，别为每张卡再请求详情（N+1）。
9. `rate=0` 表示未评分；评分是 1–10 整数。
10. `date`/`airdate` 可能为空；`total_episodes` 与 `eps` 对连载番可能不一致。
11. 用户统计没有 API；用 5 个 `type` 的 `limit=1` 请求取 `total`。
12. 头像/封面 URL 带 `r=` 参数，更新后要换 key；不要永久缓存旧图。
13. OAuth `code` 60 秒过期；回调后不要做任何耗时操作再换 token。
14. Refresh Token 轮换；并发刷新会导致其中一个失效。
15. HTML 评论时间有相对格式（`13h 28m ago`）和绝对格式，解析要容错。
16. 评论可能含 BBCode、表情、遮罩、外链；必须统一清洗，不能直接塞 `WKWebView`。
17. 条目详情不返回当前用户收藏状态；用本地缓存或单条收藏接口。
18. 章节列表可能上千条；分页 + `List` 懒加载，别一次性建视图。

---

## 8. 里程碑与排期

> 以“全职、每天 6–8 小时、单人”为基准；业余按 1.6–1.8 倍换算。  
> 每个阶段结束必须有可演示的构建，不接受“最后一起联调”。

| 阶段 | 周 | 交付 | 验收标准 |
| --- | --- | --- | --- |
| **M0 技术验证** | 1 | OAuth 打通、Glass 原型 3 屏、API/评论解析 spike、范围锁定 | iPhone + Mac 都能登录；token 可刷新；原型真机不掉帧；评论能解析 |
| **M1 地基** | 2–3 | 工程/包/CI、设计 tokens、网络层、模型、GRDB、同步骨架、Auth | 单测绿；CI 双平台构建；登录态持久化；数据库可观察 |
| **M2 浏览主线** | 4–5 | 首页、放送、搜索、条目详情、章节列表、角色/制作、路由/深链 | 60fps；离线可看缓存条目；基础 VoiceOver；快照测试 |
| **M3 收藏闭环** | 6–7 | 收藏编辑、评分、标签、短评、进度、收藏库、Outbox、游客模式 | 离线改动重启不丢；多设备冲突可恢复；**MVP 可演示** |
| **M4 内容深度** | 8 | 条目吐槽（HTML）、BBCode/剧透、人物页、失败回退 | 固定 fixture 全通过；解析失败不崩；Safari 回退可用 |
| **M5 我的/设置/离线** | 9 | 资料、统计、设置、缓存管理、外观、关于、隐私清单 | 无障碍审计通过；本地化；离线态/空态/错误态完整 |
| **M6 Mac/iPad** | 10–11 | 三栏、多窗口、菜单命令、快捷键、工具栏、设置窗口 | Mac App Store 构建；最小窗口不破版；纯键盘可完成主流程 |
| **M7 系统集成** | 12 | Widget、App Intents、本地通知、Handoff、Spotlight、分享 | 桌面组件按时刷新；通知深链正确；Intent 可改进度 |
| **M8 打磨/Beta** | 13–14 | 动效/玻璃校准、性能、无障碍、本地化、TestFlight、修 bug | 崩溃率 <0.5%；启动 <1.5s；120Hz；外部 TestFlight 反馈闭环 |
| **M9 发布** | 15 | 商店素材、隐私政策、审核备注、提审、分阶段发布 | 审核通过；无 P0/P1；监控与热修流程就绪 |

### 8.1 关键路径

```
OAuth/API → 条目详情 → 收藏/进度 → 收藏库 → Mac 外壳 → Beta → 发布
```

- 评论解析、Widget、Spotlight 都可并行/后置，不阻塞主链。
- 设计系统要在 M1 就定稿 80%，否则 M2 会返工。
- App Store 素材/隐私政策从 M7 开始准备，不要留到最后一周。

### 8.2 版本切分

| 版本 | 内容 | 时间 |
| --- | --- | --- |
| **MVP（TestFlight 内测）** | 登录、放送、搜索、条目、收藏、进度、收藏库、iPhone 主流程（Mac 可运行） | 第 7 周 |
| **v1.0（App Store）** | + 吐槽、人物、设置、Mac 完整、Widget/Intents/通知/Handoff/Spotlight、深链、无障碍、本地化 | 第 15 周 |
| **v1.1** | + 目录、编辑历史、章节吐槽、小组/日志/时光机、iPad 打磨、日文 | 发布后 6–8 周 |
| **v1.2+** | 目录编辑、年度统计、可选 Worker/推送 | 按反馈 |

---

## 9. 质量与测试

| 类型 | 范围 | 工具/做法 |
| --- | --- | --- |
| 单元测试 | Core：解码、限流、重试、token 刷新、Outbox、BBCode、HTML parser | Swift Testing；覆盖率目标 Core 70% |
| 契约测试 | 真实 API 只读，夜间跑；校验字段/状态码 | 环境变量开关；失败不影响 PR |
| 快照测试 | 组件 + 关键页面：浅/深色、AX 字号、iPhone SE/Pro Max、Mac 窗口 | swift-snapshot-testing；固定 locale/timezone |
| UI 测试 | 登录（mock）、浏览、收藏、进度、搜索、离线、深链 | XCUITest；`performAccessibilityAudit()` |
| 性能 | 启动、滚动、内存、玻璃 GPU | XCTMetric + Instruments；真机 |
| 稳定性 | 断网/弱网/429/500/畸形 JSON/超长列表 | Mock transport + Network Link Conditioner |
| Beta | 20–50 名外部测试者 | TestFlight；崩溃/反馈分类 |

测试矩阵：

- iPhone SE (3rd) / iPhone 17 / iPhone 17 Pro Max；iPad Pro 13；MacBook 14。
- iOS 26.0、27.x；macOS 26、27。
- 浅色/深色、Reduce Transparency、Reduce Motion、AX5、Increase Contrast。
- 游客/登录/离线/同步失败/账号退出。

**Fixture 策略**：

- 每个 API 保存一份脱敏 JSON；解码测试用。
- HTML 保存 3 类页面（条目吐槽、章节吐槽、小组话题）；不存用户名/头像等个人信息。
- parser 断言“条数、首条作者、评分、时间、正文纯文本”，不依赖整页快照。

---

## 10. CI/CD 与发布

### 10.1 仓库与 CI

- 单仓库；`main` 始终可发布；短分支 + PR；Conventional Commits。
- GitHub Actions（`macos-26`，必要时自托管 Mac mini）：
  - `swiftformat --lint` + `swiftlint`。
  - `xcodebuild test`：iOS Simulator + macOS。
  - 快照测试（固定模拟器运行时）。
  - Archive + `fastlane` 上传 TestFlight（仅 tag）。
- 缓存 SPM、DerivedData；PR 不跑契约测试，避免限流。
- 版本：`MARKETING_VERSION` 1.0.0；`CURRENT_PROJECT_VERSION` 用 CI 序号；每次 TestFlight 写 changelog。

### 10.2 签名与配置

- Bundle ID：`com.yaron.bgmori`；Widget `com.yaron.bgmori.widgets`；App Group `group.com.yaron.bgmori`。
- Universal Purchase：iOS/macOS 同一 App 记录。
- 自动签名；Mac App Store 需要 Sandbox（network client、user-selected files、app group）。
- `Secrets.xcconfig`（gitignore）：`BGM_CLIENT_ID`、`BGM_CLIENT_SECRET`、`BGM_REDIRECT_URI`；提供 `Secrets.example.xcconfig`。
- Info.plist：URL scheme、`BGTaskSchedulerPermittedIdentifiers`、`ITSAppUsesNonExemptEncryption=NO`。
- 隐私清单：无追踪；按需声明 required-reason API。
- App 图标：iOS 26 Icon Composer 分层图标（自有标记，不用 Bangumi logo）；Mac 1024 圆角图标。

### 10.3 TestFlight

- 内部：每次 `main` 合并自动构建。
- 外部：M8 开始（第 13 周），20–50 人；重点测 Mac 窗口、玻璃可读性、弱网、收藏冲突。
- 收集：TestFlight 截图/崩溃 + 应用内“反馈”邮件；每周分类 P0/P1/P2。

### 10.4 App Store

| 项 | 内容 |
| --- | --- |
| 名称 | `Bgmori`（副标题：Bangumi 第三方客户端） |
| 类别 | 娱乐（主）/ 工具（次） |
| 年龄 | 最高年龄分级（按 App Store Connect 问卷，通常 17+/18+）；审核版不含 R18 |
| 价格 | 免费；无广告；无内购（或后续打赏） |
| 隐私 | 数据不收集（若接 MetricKit 仅诊断且不关联身份） |
| 素材 | 6.9" / 6.5" iPhone、13" iPad、Mac 截图；15–30s 预览（可选） |
| 文案 | 功能点 + “非官方，与 Bangumi 无关联” + 数据来源说明 |
| 审核备注 | 演示账号、游客路径、NSFW 过滤、举报/屏蔽、账号删除说明 |
| 合规 | 出口合规；中国区需 App 备案/ICP；商标许可（如能拿到） |

**审核风险与话术**：

- 商标：App 名称不含 “Bangumi”，描述用 “for Bangumi”；提供非官方声明；如收到 5.2.1，补授权邮件或改名。
- UGC：每条吐槽有“举报”（邮件 + Bangumi 原页）与“屏蔽该用户”；关于页写零容忍条款与联系方式。
- 登录：提供游客浏览，审核员无需账号也能看到核心 UI；同时给演示账号测收藏。若审核援引 4.8（第三方登录），说明账号属于 Bangumi、App 无自建账号体系。
- 账号删除：App 不创建账号；设置里提供“注销 Bangumi 账号”跳转 + “清除本地数据”。
- R18：审核版编译开关强制 `nsfw=false`，搜索显式过滤，设置不暴露开关。
- 分发：v1.0 先上 Mac App Store；若后续做站外分发，再加 notarization + Sparkle，不混入首版范围。

### 10.5 中国区

- App Store 中国区上架需要 App 备案号（工信部）与 ICP 主体信息；提前 4–8 周准备。
- 隐私政策中文版、SDK 清单、权限说明；未成年人保护要求需按当时法规核实。
- 若短期拿不到备案：先上全球区（不含中国大陆），后续补。

---

## 11. 风险登记表

| 风险 | 概率 | 影响 | 对策 |
| --- | --- | --- | --- |
| 官方 API 缺口导致“完全接入”预期落空 | 高 | 高 | 先给覆盖率矩阵；v1.0 只承诺核心 A/B + 吐槽；社交后置 |
| HTML 结构变更导致解析失败 | 高 | 中 | parser 隔离 + fixture + 0 条回退 Safari + 日志告警 |
| App Store 商标/非官方被拒 | 中高 | 高 | 自有品牌、非官方声明、提前联系 Bangumi 授权 |
| UGC/R18 审核被拒 | 中 | 高 | 举报/屏蔽、零容忍条款、审核版强制过滤、最高年龄分级 |
| OAuth secret 被提取 | 中 | 中 | 接受公共客户端现实；可选 Worker；可重置 secret；不存用户数据 |
| 启动并发请求触发限流 | 中 | 中 | 全局令牌桶、请求合并、缓存、后台低优先级 |
| 玻璃过多导致掉帧/可读性差 | 中 | 中 | 玻璃层级约束、每屏 ≤2 组、真机测试、Reduce Transparency |
| 多设备收藏冲突 | 中 | 低 | pending 优先 + 全量对账 + 明确错误提示 |
| 中国区备案周期 | 高 | 高 | 先全球发行；备案与开发并行 |
| 单人排期失控 | 高 | 中 | MVP 门禁、每周可演示、20% 缓冲、砍 v1.1 范围 |

---

## 12. 成本与资源

| 项 | 费用 | 备注 |
| --- | --- | --- |
| Apple Developer Program | $99/年 | 必须 |
| 域名（可选） | ~$12/年 | Universal Link / 隐私政策页 |
| Cloudflare Worker（可选） | 免费额度 | OAuth 代理/远程开关 |
| 设计工具 | Figma 免费版 | 或直接在 SwiftUI 里做 |
| 测试设备 | 已有 iPhone/Mac | 最好再有一台旧 iPhone 测性能 |
| 总计 | **约 $111/年** | 时间才是主要成本 |

工作量估算：

- 全职：约 15 周 × 40h = **600 小时**（含缓冲）。
- 业余：15h/周 ≈ **26 周**。
- 外包参考：设计 ¥20k–50k；开发 ¥100k+（不建议，沟通成本高）。

---

## 13. 首周行动清单

| 天 | 任务 | 产出 |
| --- | --- | --- |
| D1 | 注册 Bangumi OAuth 应用（图标/回调/简介）；给 Bangumi 发第三方客户端说明/授权邮件；建仓库、Xcode 工程、Bundle ID、App Group、Secrets 模板 | 能拿到 client_id/secret；工程能跑；授权邮件已发 |
| D2 | 用 `ASWebAuthenticationSession` 打通登录；Keychain 存 token；验证刷新 | iPhone + Mac 登录成功；杀进程后仍登录 |
| D3 | API client + 模型：`/calendar`、`/v0/subjects/{id}`、`/v0/users/{u}/collections`；真实数据解码 | 三个页面的数据能打印/预览 |
| D4 | 设计 tokens + 玻璃原型（首页/条目/收藏按钮）；真机与 Mac 各跑一遍 | 3 屏可点；玻璃不糊、不卡 |
| D5 | GRDB schema + ValueObservation + Outbox 骨架；收藏写入（POST/PATCH）打通 | 改收藏 → 本地立即变 → 服务端生效 |
| D6 | 垂直切片：游客 → 登录 → 放送 → 条目 → 收藏 → 收藏库 | 一条完整链路可演示 |
| D7 | 复盘；锁定 MVP 范围；CI 跑通；建 backlog/里程碑 | 第 2 周计划确定 |

**D1 的前置**：确认 Apple Developer 账号可用；确认 Bangumi 账号能创建应用；想好 App 名称（建议先查 App Store 重名）。

---

## 14. 待确认的决策

| # | 决策 | 推荐 | 影响 |
| --- | --- | --- | --- |
| 1 | 最低系统 | **iOS 26 / macOS 26** | 下探 18 需双套设计，+2–3 周 |
| 2 | 首发区域 | **全球（不含中国大陆）** | 中国区需备案，+4–8 周非开发工作 |
| 3 | v1.0 是否含社交只读 | **只含条目吐槽**；小组/日志/时光机放 v1.1 | 全含 +3–4 周，parser 维护成本高 |
| 4 | 是否加 Cloudflare Worker | **MVP 不加，发布前评估** | 加：secret 更安全、可远程开关；减：多一个故障点 |
| 5 | 变现 | **免费**；后续打赏 | 收费需 Bangumi 许可，且影响审核叙事 |

---

## 15. 参考

- Bangumi API 文档与 User-Agent 规范：<https://github.com/bangumi/api>
- OpenAPI v0 规范：<https://github.com/bangumi/server/blob/master/openapi/v0.yaml>
- Apple HIG · Materials：<https://developer.apple.com/design/human-interface-guidelines/materials>
- SwiftUI `GlassEffectContainer`：<https://developer.apple.com/documentation/swiftui/glasseffectcontainer>
- GRDB：<https://github.com/groue/GRDB.swift>
- Nuke：<https://github.com/kean/Nuke>
- SwiftSoup：<https://github.com/scinfu/SwiftSoup>

> 本文中的端点和字段以 2026-10 的线上 API 与 v0 规范为准；上线前用契约测试再核一遍。
