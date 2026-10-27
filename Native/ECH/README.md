# ECH 连接层

Swift 通过 C ABI 调用 Go 标准库的 HTTP/TLS 客户端，覆盖官方 API、图片和匿名网页请求。没有外部 Go 模块，也不需要部署服务器。采用 Go 已实现的 TLS 1.3 ECH，未手写加密协议、使用 Apple 私有 API 或跳过证书验证。

## 构建

需要 Xcode 27.1、Go 1.27+ 和 arm64 Mac。Xcode 的 pre-build 阶段自动运行 `scripts/build-ech-library.sh`。也可分别手动执行：

```bash
bash scripts/build-ech-library.sh macosx
bash scripts/build-ech-library.sh iphonesimulator
bash scripts/build-ech-library.sh iphoneos
```

库由当前源码现场生成，输出到忽略入库的 `build/ech/<platform>/libBgmoriECH.a`，源码、构建脚本、Go 与 SDK 版本共同参与缓存判断。部署目标保持 iOS 27 / macOS 27。标准库及随 Go 分发的代码许可证位于应用资源 `GoRuntime-LICENSE.txt`。

## 请求流程

1. `MirrorRouting` 为官方地址生成内部 `.ech.invalid` 路由标记，`ConnectionTransport` 将它分派给 `ECHTransport`；标记不会交给系统 DNS 或外部浏览器。
2. Swift 将官方 HTTPS 地址、方法、请求头、请求体和时限传给 C ABI；阻塞调用在后台队列执行。Swift 取消会取消 Go 请求上下文。
3. 使用阿里、360、Cloudflare 的 HTTPS DNS 获取 `crypto.cloudflare.com` 的 HTTPS RR 中的 ECH 配置，合并并发引导，缓存两小时。配置被拒绝时只在经过证书验证的握手中接受重试配置。
4. 直接拨号 Cloudflare IP，按官方真实域名验证证书并要求 `ECHAccepted`。仅 ECH 握手成功后才发送 HTTP 请求。TLS 失败不会降级为普通 SNI。
5. 连接显式设置 `Proxy:nil`，套接字通过 `IP_BOUND_IF` 绑定当前可用的 `en*` / `pdp_ip*` 物理接口，从而绕过默认 TUN 路由。不会修改系统代理、VPN 或其他应用的网络。

内置多个 Cloudflare IPv4 地址，每日后台尝试刷新 Izuko 的公开地址清单；清单只提供 IP，TLS 始终验证 Bangumi 官方真实域名。清单不可用时保留内置地址，首次请求不依赖 GitHub 可达性。目录镜像 API 未更换。

目标只允许 `bgm.tv`、`api.bgm.tv`、`lain.bgm.tv`、`next.bgm.tv`、`doujin.bgm.tv` 的 HTTPS 443。禁止代理凭证和 Cookie，丢弃响应 Cookie；带 Authorization 的重定向不得跨域，写请求不得通过重定向重放。响应最大 32 MiB，连接和请求均受时限限制。日志只返回固定错误类别，不返回地址查询参数、请求体或凭证。

## 验证与边界

```bash
(cd Native/ECH && go test -race ./...)
bash scripts/test-ech.sh --live
bash scripts/test-shell-ui.sh all testECHOnlyConnectionsLightAndDark
```

[两端实际验证与截图](../../docs/screenshots/ech-direct/README.md)。当前传输选择具有 IPv4 地址的物理接口；纯 IPv6 网络尚未支持，自动模式仍可按既有策略使用普通连接。严格 ECH 模式下会报错，不以回退结果冒充成功。外部浏览器 OAuth 网页使用浏览器自己的连接；应用内账号 API 可以使用 ECH。
