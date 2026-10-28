# 新番播放时刻（bgmlist）

2026-10-28，iPhone 17 / iOS 27.0 模拟器与当前 arm64 Mac。

仅接入 `https://bgmlist.com/api/v1/bangumi/onair`，通过 `sites` 中 `site == bangumi` 的 ID 精确匹配现有放送表，不按标题模糊匹配。保留 Bangumi 的放送表、开播日期、评分和收藏信息；未匹配或没有可靠周播周期的作品不添加时刻。

读取 `broadcast` 中的 ISO 8601 时间与 `P7D` 周期，统一显示北京时间。若换算后星期与原放送表不同，时刻前明确标出实际星期。不会从首播日期推算小时、分钟，也不将周播时刻当成逐集延期或停播公告。

请求使用 APIClient 的 User-Agent、限流和连接处理，不携带 Bangumi Authorization 或 Cookie，不经过 Bangumi 镜像或自定义 API 根地址。单独缓存 6 小时，自动请求失败时最多保留 48 小时的缓存；手动刷新走网络，失败时保留页面已有数据并提供重试及 bgmlist 网页入口。页面任务重建不会中断 AppModel 持有的播放时刻加载。

数据来源：[bgmlist](https://bgmlist.com)，上游数据来自 [bangumi-data](https://github.com/bangumi-data/bangumi-data)（CC BY 4.0）。

## 验证

```bash
bash scripts/test-bgmlist.sh --live
BGMORI_UI_RESULT_DIR="$PWD/build/bgmlist-ui-check" \
  bash scripts/test-shell-ui.sh all testCalendarAiringTimesLightAndDark
```

解析与请求测试覆盖 Bangumi ID 隔离、北京时间换算、跨天及跨星期、无效或已结束的周期、缓存与强制刷新、异常响应不覆盖有效缓存，以及请求不携带凭证。两端真实接口返回 114 条在播记录，其中 111 条可解析为带 Bangumi ID 的周播时刻；这不代表现有放送表的每部作品均可匹配。

界面使用访客模式，检查浅深色下《侦探已经死了。第二季》显示 `21:30 播出`，仍保留 `10月7日开播`，未匹配的《航海王》不添加时刻。
