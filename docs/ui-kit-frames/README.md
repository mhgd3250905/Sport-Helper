# +51 界面套件逐帧对比

基准为 SF `13c0bb4cc24982be50bbb2471fc83ace6f64e40b`，本阶段新源码为 `b27ffe06b7ed0338d379b0474f458679eb282e2f`。`base/`、`new/` 每个提交的浅、深色各 29 帧，每个提交共 58 帧，使用逻辑尺寸 **412 × 915**、**DPR 2.625**；PNG 编码尺寸为 **1082 × 2402**（Flutter 按物理像素向上取整）。这是软件 golden，不是真机截图或性能证据。

两边使用同一个 [capture_test.dart](../../tools/ui_kit_frames/capture_test.dart) 和同一份 [inputs.json](../../tools/ui_kit_frames/inputs.json)。旧、新公开构造参数不同，只用薄适配连接真实组件；不复制绘制和动画，也不改变 token。场景容器为左右 20、顶部 64、底部 20，内部模拟聊天列表的垂直内容自适应约束。字体从实际 `FontManifest.json` 加载，包含保留的 NotoSansSC；剪影通过实际 `PoseHubAssetBundle` 及已校验的随包图片加载。

生成等待在 0 / 400 / 800 / 1200 / 1600ms 采样；标签在切换前与切换后 260ms 采样；完成勾在 260ms 采样。失败使用实际 `CoachFailureBubble`；取消帧通过实际取消回调移除生成卡。出卡按原 890ms 连续时间线采 0 / 25 / 50 / 75 / 100%。讨论标签采进入 90ms、停留 180ms、清除 60ms，并额外保留清除完成 120ms。训练页使用生产 `openTraining`、`PlayerPage` 和真实滑动路由，进入按 300ms、退出按 280ms 各采五帧；退出采样直接调用真实路由控制器的 `beginExit`，不复制动画。

计划卡输入始终为 SDK 保存的原五分钟 v3 JSON，未改变任何剂量。此 JSON 只用于稳定视觉对比；5 / 10 / 20 分钟真实生成门禁另行验证。卡片时长若因含准备口径修复发生文字变化，也应在像素差异中如实保留。

每个主题的 `capture-manifest.json` 记录帧 SHA256、字体 SHA256、源码与编译输入、共享 driver 和输入 SHA256。[source-bindings.json](source-bindings.json) 保存两份实际提交的逐文件编译输入；WIP 的帧与报告已原样归档到本机 delivery，没有作为最终证据。复现入口为 [capture_frames.py](../../tools/ui_kit_frames/capture_frames.py)，参数和离线输入见[工具说明](../../tools/ui_kit_frames/README.md)。

[逐帧像素差异表](pixel-diff-stage1.md)及[原始统计](pixel-diff-stage1.json)显示 **58/58 帧精确一致，每帧不同像素数均为 0**。统计由 [compare_frames.py](../../tools/ui_kit_frames/compare_frames.py) 直接比较 RGBA 得出，没有模糊、裁剪、遮罩或忽略差异区域；抗锯齿候选仅作描述，不能代替 Hark 验收。

本阶段按用户裁决保留 SF 原生成卡、出卡过渡和讨论标签，训练滑动路由已接 SDK；SDK 的剪影 renderer 与讨论标签图标兼容接口补齐后再继续迁移。上述零像素差只证明当前运行路径的固定输入一致，不代表这些保留组件已经完成迁移。后续应在获准的 SDK 锁定和实际接入稳定后，重导新帧、生成差异表并交 Hark 审核。Hark 通过前不出本轮 release APK 或真机 overlay，不合 main。
