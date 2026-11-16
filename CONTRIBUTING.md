# 贡献指南

感谢你愿意参与 Bgmori。这是一个原生 SwiftUI 的 Bangumi 客户端，同时支持 iPhone 与 Mac。

- 项目是**非官方**第三方客户端，与 Bangumi 官方无关联。
- 当前版本 `1.0.0`，仍在持续开发；接口和界面可能随上游调整。
- 源码以 MIT 许可证开源；Bangumi 的条目数据、封面、商标与用户内容不在 MIT 许可范围内。

## 环境

| 依赖 | 要求 |
| --- | --- |
| macOS | 27 |
| Xcode | 27.1+ |
| Swift | 6.0 |
| Go | 1.27+（只用于 ECH 静态库） |
| XcodeGen | 2.46+ |
| 模拟器 | iPhone 17 · iOS 27.0 |

## 本地运行

```bash
git clone https://github.com/Yaronluo/Bgmori.git
cd Bgmori
xcodegen generate --spec project.yml --project .
open Bgmori.xcodeproj
```

选择 `Bgmori` scheme；iOS 选 `iPhone 17 (iOS 27.0)`，Mac 选 `My Mac`。真机运行需要在 Signing & Capabilities 选择自己的 Team。

日常构建与安装：

```bash
bash scripts/build-install-ios.sh --route subject:8 --screenshot build/tmp/shot.png
bash scripts/build-install-macos.sh
```

`Bgmori.xcodeproj` 由 XcodeGen 生成且不入库；脚本会按需重新生成。

## 代码约定

- 全部 UI 使用 SwiftUI；平台差异用 `#if os(iOS)` / `#if os(macOS)`，不使用 Catalyst。
- 数据流：View → AppModel/LibraryStore → APIClient → 本地缓存；不要在 View 里直接发请求。
- 新增请求走 `APIClient` 的限流与缓存；收藏写入走 `LibraryStore` 的乐观更新与失败回滚。
- 颜色使用 `Color.bgm*` 语义色；同时检查浅色与深色模式。
- Liquid Glass 系统控件优先；自定义玻璃只用于浮动控制层，同屏最多两组。
- 新页面必须有加载态、空状态、错误状态；错误要能重试或回退。
- 不引入第三方 Swift 库；ECH 连接层使用 Go 标准库。
- 不复制其他 Bangumi 客户端的实现、文案或地址清单。

## 测试

至少运行与改动相关的脚本：

```bash
bash scripts/test-cache.sh
bash scripts/test-navigation.sh
bash scripts/test-shell-ui.sh all
bash scripts/test-social.sh --live
bash scripts/test-ech.sh --live
(cd Native/ECH && go test -race ./...)
```

改 Swift 代码必须通过 iPhone 17 模拟器与 Mac 两端构建。UI 改动附浅/深色截图；HTML 解析改动保留 Safari 回退。

## 提交与 PR

- 一个提交只做一件事，消息用 Conventional Commits，例如 `feat: add seasonal shelf`。
- 提交前确认 `git status` 没有 `.DS_Store`、`xcuserdata`、`build/`、密钥或凭证。
- 不要 force push `main`；不要擅自改 deployment target、Bundle ID、Team 或 URL Scheme。
- PR 请写清：改了什么、为什么、实际跑过的构建/测试、验证边界。
- 涉及 UI 的 PR 附 iPhone 17 与 Mac 的浅/深色截图（长期保留的放 `docs/screenshots/`）。

## 安全

- 不要把密码、令牌、Cookie、验证码写进仓库、日志、截图或 issue。
- 登录令牌与官网会话只存 Keychain；社交页面保持匿名只读。
- 发现安全问题请按 [SECURITY.md](SECURITY.md) 私密报告，不要在公开 issue 中贴细节。

## 文档与截图

- 设计记录：`docs/DESIGN-REFRESH.md`、`docs/MACOS-DESIGN.md`。
- `docs/PLAN.md` 是历史方案，实际实现以 `README.md` 和 `AGENTS.md` 为准。
- 截图索引：`docs/screenshots/readme/README.md`；临时截图放 `build/tmp/`，检查后删除。

## AI 辅助开发

仓库根目录有 [`AGENTS.md`](AGENTS.md)，是 Codex、Claude Code、Cursor、Copilot、Gemini CLI 等代理的规范源；`CLAUDE.md`、`GEMINI.md`、`.github/copilot-instructions.md`、`.cursor/rules/bgmori.mdc` 只是入口。使用 AI 辅助时请让它先读 `AGENTS.md`，并遵守其中的构建、安全与验证要求。
