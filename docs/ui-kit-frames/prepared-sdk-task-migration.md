# 生成卡 / 交付过渡：已准备、暂未切换

用户本轮裁决：先由 SDK 补兼容接口并提供新的 main pin；标签和剪影继续使用当前实现，再切换并重导对应帧。

当前运行接入保留 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b` 的宿主 `CoachTaskBubble` 和 `CoachDeliveryTransition`，包括原剪影 Widget 的 legacy alpha-bounds 裁剪、动作名称语义和全部四个 RepaintBoundary。SDK 新增同名导出只在相关宿主 import 中隐藏；没有修改动画参数、尺寸、颜色或素材。

必须暂留这两个组件的原因：现有 SDK `caa6817c51b3cb09c46909288d83aa88bdc2dbd4` 的生成卡只接收 ImageProvider，不能嵌入原 `SfAlphaAsset` Widget；其交付过渡又只识别直接 child 为 SDK 生成卡时设置完成标记。混用旧生成卡和新过渡会丢失完成勾编排，不能用自造 provider 或叠绘替代。

已完成的 SDK 摘要 / 生成卡 / 交付过渡接入作为限定补丁保存在同目录 `prepared-sdk-task-migration.patch`：基线 `13c0bb4`，仅含原生成卡子任务的 10 个 App / 测试文件，不包含 cadence、路由、focus、工具或其他工作。补丁包含原 18 行摘要适配以及直接 child 类型接入；SHA-256 为 `0d54dcc0ccde582378aac0995b2994975a5076e59fd3a4545d339292bdd314f0`。这是准备成果，不代表剪影已替换。

精确 task 主题色映射和 `smartfitTaskCutout` helper 已保留在宿主 adapter 中，现运行仍使用旧剪影 Widget。补丁包含这些已保留的 adapter hunks，因此不应对当前树盲目整份应用。收到新 renderer pin 后需复核接口、保留原裁剪与语义、再接入并重导对应浅深逐帧对比；现有 SDK 路径的 probe 不能证明 legacy 裁剪等价。

此次仅按裁决保存准备补丁并恢复原运行接入、组件单测及 SF 集成断言；未运行测试、提交或构建设备包。根任务统一执行后续门禁。
