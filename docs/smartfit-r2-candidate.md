# SmartFit r2 内测候选

当前候选在 `codex/feedback-r1-part1`。三个 SDK 包均固定本机 `codex/smartfit-feedback-r2` 的提交 `cc03d4a962e7167bf3b008832f85018daa410014`。按照 SDK 的 `docs/smartfit-r2-integration.md`，本机使用未提交的 `pubspec_overrides.yaml` 覆盖三包，以解析候选 trainer 对尚未发布的 coach tag 的依赖。该本机路径和覆盖仅用于候选验证，不可作为正式发布依赖。

真机确认并发布正式 tag 后，合入 main 前必须把三个包的 `pubspec.yaml` 和 lock 文件替换为正式 tag，删除本机覆盖文件，再重新构建及验证。不得推送或合入 main、release/1.0，直到用户明确批准。

r2 的新训练确认卡以 SDK 对当前输入的推断为准，旧条件仅用于预选。训练生成失败时展示 SDK 失败气泡，不自动出本地预设。卡片使用已通过 SDK 门禁的计划器械及目标时长，动作图使用 trainer 随包透明首帧。

设备与真实模型验证结果以该候选 APK 的最终交付回报为准；自动化模拟不等同于真机飞行模式、语音、截图或远端服务验收。

此前 SDK `e4590a7` 对“把当前训练方案缩短到 7 分钟”的时长门禁会误用新时长；`42bc4eb` 修复活会话的调整，`005dd9d` 支持随历史恢复已准入计划及条件，`cc03d4a` 支持换一套并要求动作有足够变化。实际验证结果以本轮测试回报为准。
