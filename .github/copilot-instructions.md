# Bgmori Copilot Instructions

完整规范见根目录 `AGENTS.md`。以下是最容易犯错的约束。

## 项目

- 原生 SwiftUI 的 Bangumi 第三方客户端，iPhone + Mac，iOS 27 / macOS 27，Swift 6。
- 没有第三方 Swift 库；ECH 使用 `Native/ECH/` 的 Go 标准库静态连接层。
- `Bgmori.xcodeproj` 由 XcodeGen 生成、不入库；改工程设置请改 `project.yml`。

## 代码规则

- 数据流：View → AppModel/LibraryStore → APIClient → 本地缓存。View 不直接发请求、不直接读写 Keychain、不直接解析 HTML。
- 新 API 请求必须走 `APIClient`，带项目 User-Agent、限流和缓存；不要新建 URLSession 绕过。
- 收藏写入走 `LibraryStore` 的乐观更新与失败回滚。
- 颜色用 `Color.bgm*` 语义色；不要写死白底/黑字，必须检查深色模式。
- Liquid Glass：系统导航/工具栏/Sheet 优先；自定义玻璃只用于浮动控制层，同屏最多两组，禁止玻璃叠玻璃。
- 新页面要有加载、空、错误三种状态；错误可重试或回退。
- 不要复制其他 Bangumi 客户端的代码、文案或地址清单。
- 不要改 deployment target、Bundle ID、Team、URL Scheme。

## 安全

- 不把密码、令牌、Cookie、验证码写进仓库、日志、截图或注释。
- 登录令牌与官网会话只存 Keychain；社交页面保持匿名只读。
- 日志不打印完整 URL 的 code/token 参数或响应体。
- 测试不要使用真实账号密码。

## 验证

- Swift 改动：iPhone 17 / iOS 27.0 模拟器构建 + Mac（arm64）构建。
- UI 改动：两端浅/深色截图。
- ECH：`go test -race` + `bash scripts/test-ech.sh --live`，必须看到 `sni=encrypted` 与物理接口。
- 不要提交 `build/`、`.DS_Store`、`xcuserdata` 或密钥文件。

## Git

除非用户明确要求，不要 commit、push 或开 PR。提交用 Conventional Commits，一个提交只做一件事。
