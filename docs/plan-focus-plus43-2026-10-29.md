# 已保存计划继续讨论：+43 / 2043

候选分支 `codex/plan-focus` 基于尚未合入 main 的 +42 源码 `d90054902c1cb850f246ecfad100af81b0f31bad`。版本为 `0.1.0+43`，internal arm64 原生 versionCode 预期 2043；最终 APK 身份、源码完整 SHA、文件哈希与构建门禁以 `E:/AII-3D/3D-Sport-AI/deliveries/plan-focus-plus43/release-apk.json` 和 `package-metadata.json` 为准。候选保留未合并、未推送，交开哥真机验收。

`ugk_coach 0.8.0`、`ugk_coach_ui 0.4.0`、`ugk_trainer 0.6.0` 以及 coach 传递 override 均锁定已核对的 SDK main 提交 `b490eec43b408a8a35ce81a7830833bc6a3ff278`。相对 +42 的锁文件只变化这三包的 ref/resolved-ref，共六个值。接口依据该提交的 `packages/ugk_coach/docs/plan-focus.md`，没有修改 SDK 仓库或缓存源码。

## 导入与恢复

`showSaved` 先保留 App 展示卡，再将完整计划通过严格解码后调用 SDK `focusExternalPlan(externalId: saved.id, plan: ..., title: saved.name)`。导入失败显示“这套计划暂时无法在对话里编辑”，展示卡仍保留；这类展示不绕过 AI 输出与训练的 SDK 校验。导入成功后立刻等待 `coachSessionJson` 持久化。聊天写入串行，避免较早的展示快照覆盖较晚的 focus 快照。SDK 快照和显示数据在入队时同步捕获，退出后继续完成写入并关闭 UI 通知，避免 SDK 释放时清空账本或通知已释放的 AppStore。

SDK 决定当前讨论的计划、模型 messages、计划版本与 savedRef。`AiChatEngine._reply` 没有使用 App `ChatState.plan` 拼接计划提示。App 仅透传 SDK focus，并保存/恢复 SDK 完整快照；历史卡片的版本与引用还须与 SDK 快照中的同版本、同内容记录匹配。

## 显示与保存

输入栏上方显示 SDK 当前 focus 的“正在讨论：{计划名}”。标签遵循 28 高、14 圆角、左 10/右 4 内边距、图标 14、间隔 6、文字 13sp/w500、页面左 20、距输入框 8、浅色主色 10%/深色 18%。关闭调用 SDK `clearPlanFocus()` 并持久化。进入淡入并上移 8/180ms/easeOutCubic，退出淡出 120ms/easeInCubic，标题切换交叉淡化 150ms。

新卡的 savedRef 命中仍存在的保存记录时，原主按钮变为“更新到我的计划”，旁边增加间隔 12 的“另存一份”文字按钮。更新只替换该保存记录的计划内容和 `sdkVersion`，保留记录 ID、用户名称、保存时间、最近练习时间及既有训练历史；完成后主按钮显示“已更新”。另存生成独立记录，名称为当前保存名加“ 新版”，同名追加序号。引用记录已删除时回到普通保存。旧数据缺少 `sdkVersion` 时为 null；同一 plan.id 的新内容/新版本会更新快照。已保存内容重新作为本地展示卡插入时，按确切保存快照显示已保存，不凭空添加 SDK provenance，也不将已有版本号覆盖为 null。

## 验证与证据

四组新增回归覆盖存储版本、输入栏标签、计划卡按钮和 SDK/App 会话往返：新会话导入后完整动作/剂量可见、已有 A 再选 B、文件存储重启恢复、导入失败保留卡片、写入先后顺序、历史 v2/v3 引用、删除后的普通保存、更新/另存、取消期间抑制迟到结果。最终全量测试、分析和 HTTPS 素材检查原始日志存放于交付目录，汇总以 `validation.json` 为准。

最终源码全量测试 665/665 通过、0 跳过，`flutter analyze --no-pub` 0 问题，官方动作目录和匿名 HTTPS 素材检查已开启；会话/退出的 29 项定向回归也已通过。初次截图清理脚本、早期标签生命周期及退出通知失败日志均保留，最终回执只引用修复后的完整通过记录。

复用先前摸排中的真实接口脚本和同一接口，按“这是什么计划”“把第3个动作换掉”“时间缩到5分钟”完成三轮，共 8 次模型调用。首次正确识别保存名称和 8 个动作；第二轮第 3 项从卷腹替换为死虫式并产生 v2；第三轮产生目标 5 分钟、6 动作的 v3，savedRef 始终指向原保存记录。完整回复和最后一轮 messages 见交付目录 `live-report.md`、`last-turn-messages.json`，原始请求存于 `live/requests.json`，不包含认证头。

真实第三轮 SDK 估时为 313 秒，产品卡片按原有估时规则显示约 6 分钟；`targetMinutes=5` 不等于已验证精确 300 秒。本轮不改 SDK 的时长算法。摸排脚本的旧诊断样本包含不符合新导入门禁的 goal/mode/perSide；本次保持计划名与八个动作 ID，按当前动作目录纠正为可校验的完整计划，详见真实接口报告。

四张浅/深色 PNG 由真实三轮数据及 SDK 快照恢复后，在实际 App 聊天组件中软件渲染；截图脚本还实际点击“更新到我的计划”和“另存一份”，检查保存内容确为真实 v3，保留原记录与名称。软件截图不等于真机视觉、性能或留存数据验收。本轮未安装设备或启动模拟器。

App main 已核对为 `31fd3f0b0741175536b0a72ff2e0fc4f71b18f9f`，本轮未合并/推送候选；`release/1.0` 未操作。此前的只读摸排报告和 +42 交付均保留在各自目录。
