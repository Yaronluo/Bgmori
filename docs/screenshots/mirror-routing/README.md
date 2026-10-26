# 自动镜像接入

验证日期：2026-10-27。设备：iPhone 17 / iOS 27.0 模拟器、当前 Mac / arm64。

- 使用 `https://bangumi.wiki/api/v1/mirrors`，按服务读取主站、API 与图床地址；域名没有写死为当前镜像。
- 镜像目录保存在 Application Support，使用 ETag 与六小时有效期；更新失败保留上次目录，读取失败支持地址回退与受限频率的重新发现。
- API、图片、OAuth 授权与 Token 交换、浏览器链接统一使用镜像路由。旧镜像链接会映射到当前地址，图片仍保留 CDN 尺寸优化及跨域名缓存复用。
- 网页人机验证不会缓存为正文或显示为空列表；保留原站读取与 Safari 回退。收藏等写请求不自动跨地址重放。
- 来源说明集中在「设置 → 关于软件」，移除登录页和「我的」页的相关声明。

验证结果：

- 两端 Debug 构建、浅深色 UI 自动检查通过；条目封面、登录页、关于软件均截图检查。
- `scripts/test-mirrors.sh --live`：两端的服务映射、域名轮换、目录持久化、并发发现合并、ETag、失败保留、验证页识别、读取回退、401、写请求不重放，以及真实条目和封面解码通过。
- 图片、导航、收藏强制刷新回归测试通过；五类真实分类、组合筛选及分页通过。
- 三篇真实日志正文通过；另有一篇返回网站的「数据库中没有查询到该日志的信息」，正确识别为不存在。
- 当前 Mac 的已有账号能够恢复并显示收藏。未执行真实收藏修改，也未重新执行 OAuth 授权。
- 新版安装并打开于 `/Applications/Bgmori.app`，本地签名校验通过。

| 页面 | iPhone 浅色 | iPhone 深色 | Mac 浅色 | Mac 深色 |
| --- | --- | --- | --- | --- |
| 条目 | [截图](iphone-subject-light.png) | [截图](iphone-subject-dark.png) | [截图](mac-subject-light.png) | [截图](mac-subject-dark.png) |
| 关于软件 | [截图](iphone-about-light.png) | [截图](iphone-about-dark.png) | [截图](mac-about-light.png) | [截图](mac-about-dark.png) |
| 登录 | [截图](iphone-login-light.png) | [截图](iphone-login-dark.png) | [截图](mac-login-light.png) | [截图](mac-login-dark.png) |
