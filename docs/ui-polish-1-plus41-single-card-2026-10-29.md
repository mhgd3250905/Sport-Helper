# +41 / 2041 我的计划单卡变形

> 历史候选记录：本页测试、APK 与未合并状态属于原交付时点。本批已按用户授权审核并整合为 +47，新增修复、版本台账和最终 main 对齐入口见[+47 整合记录](main-integration-plus47-2026-10-30.md)。本页原始证据保留。

同一 `codex/ui-polish-1 / 0.1.0+41 / 2041` 已重新打包，源码 `31fd3f0b0741175536b0a72ff2e0fc4f71b18f9f`。三包及 coach 传递 override 统一锁定 SDK main `71efb9218c5899d5f2811a82ee74aa74a105e07c`；严格锁解析通过，非 SDK 依赖不变。全量 **615/615、0 跳过**，`flutter analyze --no-pub` **0 问题**。

“我的计划”每条只保留一个固定 Key 的 `CoachPlanExpanded`，传入常驻 header、收起摘要和 onToggle，复用 SDK 单层外壳与内部高度/内容动效；新旧条目同帧互斥。查看详情、开练、菜单和展开后按需滚动保留。单卡浅深逐帧身份/几何、中途反向和旧应用流程 20 项定向回归首次全过。

新 APK `SmartFit-ui-polish-1-single-card-0.1.0+41-31fd3f0-internal-arm64-v8a-release.apk`，143,599,186 B / 136.95 MiB，SHA-256 `66e98c1b8ce2733c841eba45b88b4d0a5f3e4bdca6efb53551a11ec37a22f803`；同签名、ZIP/ELF16KB、存储 JNI 通过。用户已取消本轮录屏，本机未启模拟器或操作设备，交由开哥远程安装验收。本次未合入 App main、未操作 release/1.0；+42 仍待 Hark 定案、+41 验收合 main 后开展。以下 SDK475 及更早记录属于历史，不替代本候选。

## 单卡合同

每个条目的 SDK State、Key 和单层 CoachCardSurface 持续保留；App 不再包自己的卡片或 AnimationController。header 是计划名和原更多菜单，collapsedSummary 保留缩略图、时长/动作数、最近练过与开练；页面总数仍为“{N} 套”。header 与 summary Widget 在仅 expanded 改变时保持同一实例，主题在各自 build 内读取已有 token，重命名或计划数据更新时正常刷新。

独立插槽模式内部由 SDK 使用 280ms easeOutCubic 高度变化，完成后 App 等本帧布局结束，仅在条目底部超出屏幕时 ensureVisible，以 240ms easeOutCubic 滚动。过期请求、收起、切换、删除、详情与训练均沿用取消合同。SDK 未公开 onEnd，App 保留 280ms 延时加 post-frame，未另写动画。

SDK71 的内容合同为摘要退场120ms，正文延迟60ms后180ms淡入并从上方8px进入；收起正文120ms，摘要延迟160ms后120ms进入。App 不覆盖这些时间线，也不修改对话卡既有媒体飞行动效。SDK 接入指南为 `E:/AII-3D/3D-Pose-SDK/packages/ugk_coach_ui/docs/plan-expanded.md`。

左下通过公开 action 参数传入图标与14sp主色“查看详情”；详情显示副本保留原计划ID、完整剂量，只映射保存后的标题。右下开始仍直接 training，动作库/单动作 preview 和完成感受存储维持上一批接入。SF 未复制 SDK 详情行、未改 SDK 源码或缓存，也未覆盖推荐动作卡、训练页、完成页样式。

## 验证与边界

8 项单卡专项覆盖浅深逐16ms State/Element/RenderObject/标题几何稳定，80ms展开→32ms收起→48ms再展开→切换另一条，验证同时一增一减和同帧互斥；嵌套菜单/两种开练不误触 toggle，透明控件不响应，详情/原始剂量、重命名、删除与滚动取消均通过。旧 app_flow 12 项首次通过，未修改旧测试。定向日志为 saved-plans-and-app-flow-initial.log。

全量与分析在干净的打包源提交执行，官方219目录与匿名HTTPS素材检查显式开启。本次功能源只涉及 saved_plans_page.dart、其回归测试和两个 pubspec 文件；菜单/键盘、训练流程及其他全App动效没有新增改动。软件逐帧几何不是原生 FrameTiming，未声称全部帧≤16ms。

本轮不生成截图或软件演示视频；用户最新明确无需录屏，由其远程安装测试。旧4047072/SDK475 profile包和静态摸排保留作修复前基线；全App实测仍等待远程原始资料，不把本 release 包的软件验证填成真机性能结论。

## 交付来源

所有新回执位于 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-single-card/`：release-apk.json、package-metadata.json、validation.json、lock-audit.json、flutter-test-full.log、flutter-analyze.log 及打包门禁日志。旧9777/SDK475 APK和证据保留不变。后续文档提交不替代本页记录的打包源。

只读 Git 观察另存 git-scope-observation.json：App 本地与远端 main 均为 `adc79abef2b7195872e589f6225486e944b66644`；本地 release/1.0 为 `6c786c08450d5a988db32af025ef0a1f8f5ae331`，远端该分支为 `96fefa0b75b6764a9ff14d67dfbeb3e040bd2d31`，两者分别记录。本轮未对这些分支进行合并、推送或同步指针；不能用旧本地指针推断远端状态。
