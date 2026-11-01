# SF +52 · 对话 SDK 修复交付 · 2026-11-01

**软件、视觉、双时长门禁通过，APK 已覆盖安装真机；恢复与交互由用户手动验收。** 分支 `codex/coach-chat-sdk`，本轮源码 `90a5e9b76b94c2a8a5eb3162e88d8a90a6fc7140`，接续 `083cdad`；版本 **0.1.0+52 / 2052**。五包统一锁定已核对的 SDK main `a13e3b674359c93c941f7f59d1edf09a6d609487`。

仅接入 SDK 的 `requestCompose()`、`CoachChatUserInput.rawText` 与 `beforeNewConversation(snapshot)` 三端口，删除 reset 后猜测归档的旧适配。原 7 条断言所在 **5 个完整测试文件字节未改**；没有在 App 重写对话逻辑或给 SDK 打补丁，导航、动作库、我的、设置及外观动效保持原接法。

| 门禁 | 本轮实际结果 |
| --- | --- |
| 全量 internal / 严格分析 | **674 通过 / 0 失败 / 0 跳过；analyze --fatal-infos 为 0**；原 7 条全部通过 |
| 原同组浅深关键帧 | 对照 SF `3eb2a9e`，**22/22 完整 RGBA 零差、PNG 字节相同**；390×844、dpr1；两主题等待卡均 **4 个 RepaintBoundary** |
| 旧档集成回归 | 原 core、office-relax 的卡片、目标、剂量及保存记录均保留；首次及关闭后第二次恢复通过，0 模型调用 |
| arm64 release | **42,826,116 B（42.826 MB，<45 MB）**；原证书、ZIP/ELF 16KB、Storage JNI、素材门禁通过 |

同一全新真实会话按原输入连续三轮，无外层重试、无重抽：

| 对话 | 卡片 / 含准备排程秒 | 模型 / HTTP | 耗时 | 输入 / 输出 tokens |
| --- | --- | --- | --- | --- |
| 5 分钟拉伸 | **306 / 306**（300 秒目标，+2%） | 3 / 3 | 11.329s | 30006 / 1297 |
| 推荐动作 | **4 个授权动作** | 2 / 2 | 6.714s | 17360 / 754 |
| 换一套，缩到 3 分钟 | **187 / 187**（180 秒目标，+3.89%） | 5 / 5 | **21.821s** | 65479 / 2968 |

排程为实际播放器 `SessionBuilder` 阶段时长之和（含准备），并非真机实练计时；均无手动计次阶段。两计划过 ±10%，三轮无反问。总计 **10 调用 / 输入112845 / 输出5019 tokens**；第三轮超过原 20 秒异常线，1 次 `incompatible_action` 后重出成功，`duration_fit_failed` 为 0；全部原记录保留。

**真机交接：** Xiaomi 2602BRT18C / Android 16，内测包 `com.ugk.smartfit.internal` 单次 `adb install -r` **2051→2052 成功**，实际安装 APK 哈希与交付包相同。按用户最新指令停止自动恢复自测，未启动 App、点击或读取私有存档；真机恢复、播放与性能仍待用户确认。

[APK](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/release-preparation/SmartFit-coach-chat-sdk-0.1.0+52-90a5e9b-internal-arm64-v8a-release.apk) SHA256：`42a5ce1f683b7b625cfc503889632631ea6f5704083fa8f13426fedb9753fd13`。

[7 条原回归与全量证据](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/release-preparation/seven-regressions-full-pass-source90a5e9b.json) · [22 帧逐帧表](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/frames/pixel-diff.md) · [真实模型记录](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/live-chat/summary.json) · [原生门禁](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/release-preparation/release-apk.json) · [安装回执](../../deliveries/coach-chat-sdk-plus52-a13e3b-20261101/phone-install-only/install-only-receipt.json) · [机器报告](reports/coach-chat-sdk-plus52-a13e3b-2026-11-01.json)

仅推送本分支，实际远端 HEAD 见外部 `final-push-receipt.json`；后续报告提交仅改文档，APK 与全部门禁仍绑定上述源码。**不合 main、不动 release、不打 tag。**
