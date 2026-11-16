# GEMINI.md

本仓库的完整规范在 [`AGENTS.md`](AGENTS.md)。Gemini CLI 从仓库根目录启动时请先读本文件，再读 AGENTS.md。

## 必须遵守

- 原生 SwiftUI，同时支持 iPhone 与 Mac；部署目标 iOS 27 / macOS 27，不要下探。
- 改完 Swift 代码必须构建 iPhone 17 模拟器与 Mac 两端。
- 不引入第三方 Swift 库；ECH 只使用内嵌 Go 标准库连接层。
- 数据流：View → AppModel/Store → APIClient → 本地缓存；View 不发网络请求。
- 不复制其他 Bangumi 客户端的实现或地址清单；只依据官方 API/网页和本仓库代码。
- 不提交、不推送、不开 PR，除非用户明确要求。
- 不伪造构建、网络、登录或截图结果。

## 常用命令

```bash
bash scripts/build-install-ios.sh --route subject:8 --screenshot build/tmp/shot.png
bash scripts/build-install-macos.sh
(cd Native/ECH && go test -race ./...)
bash scripts/test-ech.sh --live
```

详细目录地图、任务配方、验证矩阵与已知坑见 [`AGENTS.md`](AGENTS.md)。
