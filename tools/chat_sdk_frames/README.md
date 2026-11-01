# 实际 SF 接入后的 22 帧验收

本工具验证 `ChatHomePage → CoachChatPage` 的真实 SF 接入。实际 profile、颜色、字体、媒体、动作映射和训练端口来自生产 `createSmartfitChat(AppServices)` 的 `profile` 与 `bindings.actions`；不复制 SDK 旧候选中的 SF profile 或训练回调，不改 SDK/App 以压平差异。

基准是 SDK 已封存的 `sf-3eb2a9e-v7`，来源 SF `3eb2a9e88ef4d28e02f4cf306c1716d61baa7f10`、SDK700。新版实际解析 pin 为 `a13e3b674359c93c941f7f59d1edf09a6d609487`。SDK 旧 `candidate-final` 仅是 SDK 自己的宿主试验；它的输出不代表这次 SF 迁移已通过。

逻辑390×844、DPR1、top/bottom inset24；完整 Flutter3.44.7 / Dart3.12.2 / framework84fc5cbb22 / engine69c8c61792。正常动效、原静态48星背景、原 NotoSansSC 字体与真实 PoseHub 图片；internal flags 与 SDK capture-environment 一致。工具位于 `tools/`，因此显式执行原 `test/flutter_test_config.dart` 的 `SfCutouts.animate=false`，保持原环境。

每主题11帧：empty、waiting-250ms、plan-collapsed、plan-expand-280ms、plan-expanded、recommendations、focused-saved-plan、training-enter-150ms、training-enter-300ms、training-exit-140ms、training-return。11个原采样、交互顺序、完整训练视口与预缓存清单均沿用 SDK 已验证脚本；不为差异改变时刻或视口。

waiting250ms 从实际 CoachTaskBubble 元素子树计数并断言 RepaintBoundary 为4，排除外层page/list/router。训练采样同时断言真实SF TrainingRoute继承SDK TrainerSlideRoute，并记录路由值及SDK来源页transition hold；只观测，不改时间或页面。

`inputs/` 保留原22份JSON字节，包含原 plan 剂量、消息、Core snapshot、控制器时钟及采集日期。完整 inputs 集合 SHA256 为 `cc0910f0b32cf4c9af6b835b1f88a071af7aad371b9bba418edfa0ea8890b464`。正常 snapshot restore/admission 恢复 canonical 计划，不重跑配时。测试 controller 仅覆写只读 suggestions getter，复现原 live 帧；等待使用真实 pending FakeLlm。生产 profile、scope、validation、host actions 与页面均不覆写。

`freeze_baseline.py` 不跑 Flutter，只读 SDK 工作树和原基线，从 SDK pin 的 Git 对象提取 reference。已核对原SF归档2727文件：2443字节相同、284仅CRLF换行变化、没有内容差异；438张原图按原index逐一校验。v7实际harness与后来格式化的pin模板经 Dart3.12格式化并移除空行后相同（只用于来源核对，不改变原脚本或基线）。两份raw脚本、原环境、原截图、原输入与逐文件SHA均保留在外部收据。

`support.dart` 和 `support/coach_v2_fixtures.dart` 为原SF fixture helper 的LF副本，仅换行规范化，值不变；原字节在 baseline-receipts。6张真实 cover/thumbnail 共75,346字节由 `media-inputs.json` 冻结，复现用的素材副本不在 pubspec 范围。捕获前要求实际App已有同字节素材，不生成placeholder或静默替图。

```text
python tools/chat_sdk_frames/freeze_baseline.py --sdk-repository <SDK仓库> --sf-repository <SF仓库> --sealed-baseline <SDK/build/chat-extract-baseline/sf-3eb2a9e-v7> --output <新frames根>
python tools/chat_sdk_frames/capture_frames.py --checkout <冻结SF工作树> --expected-source <实际源码完整SHA> --baseline <frames根/base> --output <frames根/new> --receipts <frames根/new-receipts> --flutter <完整Flutter3.44.7/bin/flutter.bat> --pub-cache <pub-cache>
python tools/chat_sdk_frames/compare_frames.py --frames-root <frames根> --new <frames根/new> --receipts <frames根/new-receipts> --output-prefix <frames根/pixel-diff>
```

先由根 Agent 协调同工作树的独占 Flutter 窗口；launcher 不执行 pub get、不 checkout/patch SDK、不改生产或test源码。实际五包须从干净的 a13e3b pub-cache 解析，framework/flutter_test 须来自同一完整工具链。捕获前后核对 HEAD、编译输入、实际 package sources 和22张基准图 SHA 不变。输出与收据必须是新路径，拒绝覆盖。

Dart 使用 Flutter `GoldenFileComparator.compareLists` 默认零差阈值；不用可调 comparator，不向原SDK目录写失败图。随后Python对完整390×844 RGBA独立逐像素统计，不裁剪、遮罩或给容差。差异逐帧报告，不能以既有 SDK 候选结果代替新 SF 捕获；零差也不建立真实模型、真机媒体、profile性能或Hark验收。
