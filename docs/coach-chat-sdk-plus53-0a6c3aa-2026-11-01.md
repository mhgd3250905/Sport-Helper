# SF +53 · 对话 SDK 长会话交付 · 2026-11-01

**软件、22 帧、真实模型 20＋21 轮及原机保留数据升级恢复全部通过。** 分支 `codex/coach-chat-sdk`，版本 **0.1.0+53 / 2053**；打包与全部门禁源码 `df4e460f5e2c6395300012d10ab0899f868cf897`。五包及 coach override 固定 SDK main `0a6c3aaea9e3890d938799703f97819d5986ee7d`；推送前再精确核对，远端读回见交付目录 `final-push-receipt.json`。

三个端口沿用 `requestCompose()`、`CoachChatUserInput.rawText`、`beforeNewConversation(snapshot)`。本轮只补宿主诊断适配：保留每轮原始字节、错误类型（成功为 null），转发真实请求编码器；不改 SDK、上限、重试、取消或 lease。原 **7 条断言所在 5 个完整文件字节未改**。

| 门禁 | 实际结果 |
| --- | --- |
| 全量 / 严格分析 | **678 通过、0 失败、0 跳过；analyze --fatal-infos 0 问题**；原 7 条通过；严格离线锁及非 SDK 依赖检查通过 |
| 同组浅深帧 | 对照 SF `3eb2a9e`，**22/22 完整 RGBA 零差、PNG 字节相同**；390×844，7,241,520 像素；等待卡 RepaintBoundary **[4,4]** |
| 旧模板自动回归 | core、office-relax 首次及第二次启动保持原卡、目标、剂量与保存记录；0 模型调用 |
| arm64 release | **42,833,292 B（42.833 MB，<45 MB）**；原证书、ZIP/ELF 16KB、Storage JNI、素材门禁及独立复验通过 |
| 原机升级恢复 | Android 16 原手机单次 **2052→2053 `install -r`**，安装哈希匹配、首次安装时间不变；两次启动均恢复旧对话 9 动作卡、6/9 回执、2 套计划及 **19/19 项原剂量**，旧详情可打开 |

原三段输入逐字不变，在同一正式 controller / Agent 真实调用 `deepseek-flash`，直接接续至第 20 轮，无外层重试或会话重置：

| 原对话 | 卡片 / 含准备排程秒 | HTTP | 耗时 | 输入 / 输出 tokens |
| --- | --- | --- | --- | --- |
| 在家拉伸 5 分钟 | **314 / 314（+4.67%）** | 4 | 17.581s | 40609 / 2134 |
| 推荐大腿内侧动作 | **4 个授权动作** | 2 | 5.328s | 16711 / 558 |
| 换一套，缩至 3 分钟 | **183 / 183（+1.67%）** | 4 | 12.727s | 43422 / 1473 |

双时长均过 ±10%，无反问、无手动计次；排程取真实 `SessionBuilder` 含准备阶段求和。首轮一次 `quote_not_found` 后 SDK 修正成功，伴随一次 `skipped_after_error`。全长 **20 轮成功 / 245.693s / 55 HTTP / 输入586756、输出26550 tokens**；第 17、18 轮为 23.760s、21.848s，均正常返回。

第 **21** 轮 **42ms、0 HTTP**，`limitReached` / `failureKind:conversationLimit` / `errorType:null`，原文“**本次对话已到长度上限，请开启新对话继续。**”无网络误报。最大实际请求 **57,775 B**，最大 beforeBytes **57,775 B**；**55/55** 与 SDK afterBytes 精确一致，均低于 65,536 B。36 次请求观测到折叠，首次 **48,548→22,435 B**；21 条逐轮结果含错误类型，847 条日志重新载入后逐轮结果完整一致。

[APK](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/release-preparation/SmartFit-coach-chat-sdk-0.1.0+53-df4e460-internal-arm64-v8a-release.apk) SHA256：`e9fd563bd891e9c40ce620782c128b1ec70e4d607d6354cbd305af2d6948594c`。

[机器报告](reports/coach-chat-sdk-plus53-0a6c3aa-2026-11-01.json) · [软件与原七条](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/release-preparation/seven-regressions-full-pass.json) · [22 帧](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/frames/pixel-diff.md) · [长会话](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/live-chat/long-session-summary.json) · [原生门禁](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/release-preparation/validation-release.json) · [升级恢复回执](../../deliveries/coach-chat-sdk-plus53-0a6c3aa-20261101/phone-upgrade/restore-verification.json)

**证据范围：** 长聊为正式控制器的新合成会话真实模型测试；seedBytes=0，折叠前未跨 64KB。手机仅做旧档升级与两次恢复，未发送新模型请求或开练。软件帧、排程与恢复结果不代表真机播放、训练秒表或性能验收。原始模型记录、私人存档截图及 UI 文本仅留本地。源码后只追加文档；**仅推本分支，不合 main、不动 release、不打 tag。**
