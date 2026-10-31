# SmartFit +51 第一阶段：SDK 路由、节奏与审阅证据

本阶段已经完成独立可推进部分；**整体尚未验收通过**。用户选择先由 SDK 补兼容接口并另给新 main pin，标签和现有剪影渲染保留。5 分钟真实生成计划也未达到时长门禁。当前不合 main、不动 release/1.0、不打 tag；Hark 通过前不出 release APK/profile、不操作手机。

## 源码与 SDK

- 分支 `codex/coach-ui-kit`，基准 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b`。
- 实际测试、真实生成和新版 golden 的源码提交 `b27ffe06b7ed0338d379b0474f458679eb282e2f`；后续仅补证据、文档和复现工具数据。
- 版本 `0.1.0+51`；三包与 coach override 均锁定 `caa6817c51b3cb09c46909288d83aa88bdc2dbd4`，锁文件和实际解析缓存同 SHA。
- 当前分支未继承本机 main 的 +50 文档提交；从用户指定 13c0bb4 创建。本轮没有移动 main 或 release/1.0。

## 已完成与保留边界

`training_route.dart` 改为 111 行 SDK `TrainerSlideRoute` 的诊断薄适配，仅监听 public control 与 dispose。所有训练入口继续复用 `openTraining`，保留 startGate、媒体海报、退出保存失败恢复及 SF 帧记录/Activity；没有复制 SDK 路由动画或控制器。

已删除 `test/training_slide_route_test.dart`（669 行迁入 SDK 的纯路由单测），保留 SF 入口/播放器/单练集成，并新增 5 项宿主诊断桥测试。生成卡、交付过渡、讨论标签源码及其仍在运行的测试暂留；四个 RepaintBoundary 保持原实现。没有修改尺寸、时长、曲线、颜色或素材。

生成/交付的精确主题映射、摘要适配和 SDK 接入已经准备，见 [准备说明](ui-kit-frames/prepared-sdk-task-migration.md)与 [限定 patch](ui-kit-frames/prepared-sdk-task-migration.patch)。SDK 当前仅接受 ImageProvider，过渡又只识别直接 SDK bubble child，故保留旧剪影 Widget 时必须暂留完整旧 bubble/过渡运行链。接口证据见 [SDK 缺口](ui-kit-sdk-gaps-2026-10-31.md)。

以下为不超过 20 行的接入准备；尚未替换当前运行的旧剪影，新的 renderer pin 到达后需按真实接口更新：

```dart
final summary = coach.CoachTaskSummary.fromState(state, task: task);
return CoachTaskBubble(
  title: summary.title,
  status: summary.status,
  phase: summary.phase,
  parameters: summary.parameters,
  picks: summary.picks,
  complete: summary.complete,
  waiting: true,
  onCancel: cancel,
  cutoutFor: (id) => smartfitTaskCutout(context, library.tryGet(id)),
);
```

## 节奏与真实生成门禁

先从原 source 建立 execution rhythms 并应用 hold，再只向规划目录内存副本补同一 `cycleFor()` 的 `assets.video.sources.repSeconds`；首个有效来源仍带真实 app/path，源包、SHA、原始剂量和执行 Rhythm 未改。保留 lead、分相位及语音；lead 不均摊进 repSeconds。卡片改取同一 SessionBuilder phases 总和，含默认 10 秒准备；原 planSeconds 的不含准备语义保留。

原五分钟 v3 的字节级原稿作为 SF 回归保留：历史目录估时 313 秒，统一周期的规划估时 344 秒，实际排程/卡片含准备 345 秒；剩余 1 秒是原有深蹲 lead。原稿本身仍超出 5 分钟 +10%，没有为了门禁改写它。

正式三张计划通过与 App 相同的 `PoseHubActionLibrary.load → AppTestCatalog.fromSdk → AppTestContent.build`、同一 profile、AiChatEngine/ChatController 和真实 DeepSeek transport 生成；每个目标只保留这一轮原始结果。随后用真实 SDK SessionEngine 完整回放阶段时钟。**这是软件执行时钟回放，不是真机训练或墙钟验收。**

| 目标 | Coach 估时/秒 | 卡片含准备/秒 | 执行含准备/秒 | 对目标偏差 | 结果 |
| --- | ---: | ---: | ---: | ---: | --- |
| 5 分钟 | 383 | 384 | 384 | +28.00% | 未通过 |
| 10 分钟 | 611 | 612 | 612 | +2.00% | 通过 |
| 20 分钟 | 1256 | 1258 | 1258 | +4.83% | 通过 |

三张均无手动计次阶段。5 分钟的 Coach 383 秒与执行 384 秒仅差 1 秒 lead，但计划整体超出目标 84 秒 / 28%，故本项门禁明确未通过。原始生成剂量、目标和 SDK 配时规则均未更改，也没有再次抽样挑出成功结果。10/20 分钟的估算与执行差额分别为保留的 1/2 秒起拍。

[三份原稿与 transport 调用](reports/sdk-ui-kit-plus51-stage1/)及 [正式汇总](reports/sdk-ui-kit-plus51-stage1/live-summary.json)保存原始事实。首轮曾沿用旧诊断工具的目录投影，309/630/1261 秒及其手动阶段结果保留在本机 delivery 作诊断；它们不计为本阶段正式门禁，未用于替代上述失败样本。

## 软件与逐帧验证

本提交全量 **857/857**、0 失败/0 跳过；`flutter analyze --no-pub --fatal-infos` 为 0 问题；严格离线 lock resolution 通过。[软件回执](reports/sdk-ui-kit-plus51-stage1/software-gates.json)包含源码、输入及日志哈希。

基准 13c0bb4 与源码 b27ffe0 使用同一个 driver、输入、字体、逻辑 412×915 / DPR 2.625，浅深色各 29 帧，共 58 对，**每帧不同像素数均为 0**。覆盖等待 0/0.4/0.8/1.2/1.6 秒、标签、完成/失败/取消、出卡 5 帧、focus 及训练进入/退出各 5 帧；额外保留 focus 清除完成帧。

[逐帧差异表](ui-kit-frames/pixel-diff-stage1.md)、[提交与字体绑定](ui-kit-frames/source-bindings.json)、[复现工具](../tools/ui_kit_frames/README.md)可供 Hark 审阅。当前只有训练路由已迁入 SDK；零像素差不能代替标签/剪影完整迁移、可访问性、真机性能或 Hark 确认。

## 后续顺序

收到含图标 builder/剪影 renderer 的新 SDK main pin 后，完成三组件切换、删对应 SF 副本测试并重导相应帧；5 分钟生成配时缺口另行处理并重新验证三档真实计划。推送审阅分支供 Hark 逐帧确认后，才构建 arm64 release APK、执行签名/16KB/JNI/45MB 门禁并采 profile overlay。当前本轮 APK 大小、签名/16KB/JNI 及 UI/raster 最大值均为**尚未采集**，不得借用 +50 的旧证据。
