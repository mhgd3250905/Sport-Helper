# SDK 99c1449 逐帧复验

本轮新源码为 `d0a88871befcf0fab8c0aca1e97046ea3c635016`，SDK 三包统一锁定 main `99c14495685f160019e10340ea6f0de6418a65b9`，App 版本保持 `0.1.0+51`。基准沿用 [13c0bb4 的原始 58 帧](../base/)；本轮 [new/](new/) 独立保存新截图，未覆盖上轮内容。

使用同一冻结 driver `81f80b15fbfc34526aca03c18e835c0234553f064c9a46ab4543c5f65ac6f154`、同一输入 `a2c6df4c3e5dd8f3acab967ab835b15b0d9c6db3f98c318c0d8fcb705d490711`、同一 adapter、字体与媒体：逻辑 **412×915**、DPR **2.625**，PNG **1082×2402**。浅、深色各 29 帧，覆盖等待、标签切换、完成／失败／取消、出卡过渡、计划讨论标签、训练页进入／退出；清除标签终点为额外保留帧。捕获前、后 HEAD 和编译输入均一致，两个 capture tests 通过。

[逐帧差异表](pixel-diff.md)与[原始像素统计](pixel-diff.json)显示 **58/58 对精确一致，每帧不同像素数均为 0**。没有缩小、模糊、遮罩或排除差异区域。[source-bindings.json](source-bindings.json) 绑定实际源码提交、SDK 锁定、原基准收据、字体与输入；[receipts/](receipts/) 保留严格离线 lock 解析、命令、编译输入哈希和原始捕获日志。

运行路径仍为 **SF 原生成卡、出卡过渡、讨论标签 + SDK 训练滑动路由**。标签／剪影兼容接口需等 `ui-kit-slots` 合入 SDK main 并取得新批准的 pin 后再接入；当前零差异不表示这三项已经迁移完成。此处为软件 golden，不是真机或性能证据，Hark 验收仍待确认；本轮没有 APK、profile 或设备操作。

复现继续使用 [通用 launcher](../../../tools/ui_kit_frames/capture_frames.py)；以该源码提交建立工作树，指定新输出与证据目录，保留同一 [inputs.json](../../../tools/ui_kit_frames/inputs.json)。完整参数和基准说明见[工具文档](../../../tools/ui_kit_frames/README.md)。
