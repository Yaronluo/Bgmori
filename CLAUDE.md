# CLAUDE.md

本仓库的完整规范在 [`AGENTS.md`](AGENTS.md)。开始改代码前请完整读一遍；本文件只是入口和速查。

## 速查

- Bgmori 是原生 SwiftUI 的 Bangumi 客户端，iOS 27 / macOS 27，Swift 6。
- 构建两端：
  - `xcodebuild -project Bgmori.xcodeproj -scheme Bgmori -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -derivedDataPath build/DerivedData-ios CODE_SIGNING_ALLOWED=NO build`
  - `xcodebuild -project Bgmori.xcodeproj -scheme Bgmori -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-mac CODE_SIGNING_ALLOWED=NO build`
- 日常安装：`bash scripts/build-install-ios.sh` / `bash scripts/build-install-macos.sh`。
- 不要引入第三方 Swift 库，不要改 deployment target、Bundle ID、Team、URL Scheme。
- 不要在 View 里直接发请求；数据流是 View → AppModel/Store → APIClient → 缓存。
- Liquid Glass 只用系统控件和浮动控制层；自定义玻璃同屏最多两组，禁止玻璃叠玻璃。
- 颜色用 `Color.bgm*` 语义色；改 UI 必须检查浅色/深色和 Dynamic Type。
- 凭证只存 Keychain；社交页面匿名只读；不要把 Cookie 发往镜像。
- 不要复制其他 Bangumi 客户端的实现、文案或地址清单。
- 除非用户明确要求，不要 commit、push 或开 PR。

## 文件入口

- 全局状态：`Bgmori/App/AppModel.swift`
- 路由：`Bgmori/App/AppRouter.swift`
- 网络：`Bgmori/Core/API/APIClient.swift`
- 收藏：`Bgmori/Core/Storage/LibraryStore.swift`
- ECH：`Native/ECH/main.go`、`Bgmori/Core/API/ECHTransport.swift`
- 设计：`Bgmori/Design/Theme.swift`、`Bgmori/Design/Components.swift`

完整任务配方、验证矩阵和已知坑见 [`AGENTS.md`](AGENTS.md)。
