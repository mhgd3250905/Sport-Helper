# 历史记录：生成卡 / 交付过渡：已准备、暂未切换

<!-- sdk-main700d010-current:start -->
## +51 SDK main700d010 当前状态（2026-11-01）

**用户已反馈真机验收通过，并要求停止测试。** 已停止测量，换装同源 +51 release。13 帧非零的量化事实和原记录保留，0 像素目标仍未达，Hark 独立回执未记录；不合 main、不动 release/1.0、不打 tag，不自行改参数。

当前三包 pin `700d0100f1cb42ef122e774a6ee0076d1916b5e5`，运行接入已切 SDK 生成卡 / 交付过渡 / focus，版本 `0.1.0+51`。源码 B `de0bd432ec85f055206792b921964630739fd137`，实际模型运行 A `7548ee00955f3811fb9c18139503bb7f04abc11a`；A→B 仅 11 个帧工具文件，14 项模型输入 SHA 不变。SF 全量 **822/822、0 skip**，analyze --fatal-infos **0 issue**。

浅深 130 对帧：117 对零差，13 对共 299 像素，单帧最多 81 / 通道最大 59；原 58 对与新增 focus 边界全 0。SDK 4 个 RepaintBoundary 保留。5 次独立真实生成全部交付无反问、排程 ±10%；24 LLM / 24 HTTP，input 254462 / output 8058。首 case 手动 10 reps 估算 30 秒按授权不失败；missing goal 参数修复单列，duration recovery=0，未覆盖失败恢复分支。

包回执：release: artifact_verified; profile: artifact_verified。原生 profile：stopped_by_user_after_reported_acceptance；用户反馈通过按明确消息记录，不再补测等待态 overlay 或完整视频。原生手机内容不入仓。详见 [本轮总报告](../sdk-ui-kit-plus51-main700d010-2026-10-31.md)。以下旧 pin / 暂缓迁移 / 旧验收条件均为历史记录，以本节和报告界定当前状态。
<!-- sdk-main700d010-current:end -->


用户本轮裁决：先由 SDK 补兼容接口并提供新的 main pin；标签和剪影继续使用当前实现，再切换并重导对应帧。

当前运行接入保留 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b` 的宿主 `CoachTaskBubble` 和 `CoachDeliveryTransition`，包括原剪影 Widget 的 legacy alpha-bounds 裁剪、动作名称语义和全部四个 RepaintBoundary。SDK 新增同名导出只在相关宿主 import 中隐藏；没有修改动画参数、尺寸、颜色或素材。

必须暂留这两个组件的原因：现有 SDK `caa6817c51b3cb09c46909288d83aa88bdc2dbd4` 的生成卡只接收 ImageProvider，不能嵌入原 `SfAlphaAsset` Widget；其交付过渡又只识别直接 child 为 SDK 生成卡时设置完成标记。混用旧生成卡和新过渡会丢失完成勾编排，不能用自造 provider 或叠绘替代。

已完成的 SDK 摘要 / 生成卡 / 交付过渡接入作为限定补丁保存在同目录 `prepared-sdk-task-migration.patch`：基线 `13c0bb4`，仅含原生成卡子任务的 10 个 App / 测试文件，不包含 cadence、路由、focus、工具或其他工作。补丁包含原 18 行摘要适配以及直接 child 类型接入；SHA-256 为 `0d54dcc0ccde582378aac0995b2994975a5076e59fd3a4545d339292bdd314f0`。这是准备成果，不代表剪影已替换。

精确 task 主题色映射和 `smartfitTaskCutout` helper 已保留在宿主 adapter 中，现运行仍使用旧剪影 Widget。补丁包含这些已保留的 adapter hunks，因此不应对当前树盲目整份应用。收到新 renderer pin 后需复核接口、保留原裁剪与语义、再接入并重导对应浅深逐帧对比；现有 SDK 路径的 probe 不能证明 legacy 裁剪等价。

此次仅按裁决保存准备补丁并恢复原运行接入、组件单测及 SF 集成断言；未运行测试、提交或构建设备包。根任务统一执行后续门禁。
