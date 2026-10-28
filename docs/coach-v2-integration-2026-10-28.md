# SmartFit Coach Agent v2 接入检查点

基线是 `codex/feedback-r1-part1` 的 `db1e550a6f863ab170a607f5dac800498c89f040`（+38）；从该提交建立 `codex/coach-v2`。10-27 的自适应面板和删除 App 意图逻辑此前未完成，已并入本轮。当前预留下一版本 `0.1.0+39`，两个 SDK 公开接口缺口解决前不作为完整交付出包。

## 已实施

三包 git 依赖及 lock 统一为 SDK main `adbc90890e4b4f0a5717e902f995059a34e52243`。使用正式 GitHub 源；trainer 的传递依赖仍引用未发布 coach tag，因此在受版本控制的 pubspec 中对 coach 固定相同 commit，不再依赖本机 ignored override 文件。随包 SmartFit profile 同步 SDK 原文件。

删除 `RuleChatEngine`、`SlotParser`、`Slots`、`_slotsFor`、App 条件继承及改计划判断、App 模板失败回落与计划 ID 重写。`AppChatActions` 只处理 UI 显式命令；自由文本原样交 SDK。当前计划、请求在 App 中只服务卡片、保存及训练展示，不作为 CoachContext 发送。Agent 的重试、超时、上下文阈值不覆盖；客户端 maxRetries=0、timeout 保留 SDK 的 120 秒。

按用户本轮追加授权，App 请求配置切到 `https://ai.uuugk.win/v1`、`deepseek-flash`、SDK `ApiKeyAuth` 的 Bearer 鉴权。凭据仅在本机构建/验证时读取并注入，不入 Git；不修改 SDK 默认配置文件。内测包来源与凭据方式仍须与正式发布边界区分。

等待界面直接映射 SDK node 事件的节点顺序、状态和 stamp，纵向展示，output 完成后折叠；询问继续使用 SDK CoachQuestionBubble 和 answer/skip；计划继续使用 SDK CoachPlanCard。旧按阶段轮换的等待文字已删除。

底部面板随宽度、文字大小和内容行数确定高度，正常四项一行，窄屏/大字换行；四格菜单图标，背景同页面，保留展开/收起、输入切换、返回与点击对话区关闭。删除键盘高度偏好和定时器；旧偏好安全忽略。减少动效时直接布局面板，避免零时长 AnimatedSize 在 layout 中同步触发布局异常。

修正两项原有对比度回归的主题 token（浅色 accent、深色 muted），测试阈值维持 4.5。旧离线意图和模板协议测试删除或改写为 v2 的真实公开工具协议/明确手动计划 fixture；导航、保存、安全、计时、语音和媒体预取边界保留。

## 检查结果

固定 Flutter 3.44.7 执行 internal 全量：523 项通过，0 跳过；包括真实官方 catalog 和匿名 HTTPS 下载/校验/复用/离线缓存探针。`flutter analyze --no-pub` 无问题，`git diff --check` 通过。日志分别为交付目录的 `all-tests-final.log`、`analysis-final.log`，锁文件离线严格解析证据为 `lock.log`。这是当前已实现代码的回归结果，不包含尚无 SDK 接口的新完整快照恢复和 SDK 推荐 Widget 验收。

## 一次性真实模型验证

每段执行一次，无人为重跑；前两段各新会话，第三段接第一段。使用产品实际 catalog/profile、当前 AiChatEngine、SDK 默认 Agent 配置。三个响应模型标签均为 `deepseek-flash`，无报错，无追加追问。

| 对话 | 耗时 | 模型调用 | 结果 |
| --- | ---: | ---: | --- |
| 在家徒手20分钟练核心 | 14.728 秒 | 6 | SDK 准入计划，目标 20 分钟 |
| 推荐几个拉大腿内侧的动作 | 7.529 秒 | 3 | SDK 准入推荐数据 |
| 换一套，缩短到10分钟 | 18.131 秒 | 4 | 同一 SDK plan_id，目标 10 分钟，主体新动作比例 100% |

证据位于 `E:/AII-3D/3D-Sport-AI/deliveries/coach-v2-plus39/live/`，`summary.json` 为文字回报数据，`results.json` 为本轮三段无私有旧存档的完整结果。推荐数据通过不代表尚不存在的 SDK 推荐 Widget 已接入；这不是手机测试。

## 尚未解决的 SDK 边界

1. `CoachSessionState.toJson/fromJson` 已具备完整账本，但没有通用导入入口。`restoreHistory` 仅在有已准入计划卡时调用 `restorePlan`，关闭旧询问，不能恢复推荐、问答和未完成任务。本轮未伪造 App 恢复。当前只保留旧存档 SDK 兼容恢复；旧 per-card planState 只读迁移，不再维护新副本。完整新会话持久化须等 SDK 的通用快照入口。
2. adbc908 没有 `CoachRecommendCard`；当前推荐 UI 仍为原 App ActionCard。须等 SDK 提供组件后替换，不把推荐冒充训练计划。
3. 独立假模型探针复现：本轮 replace_all 草稿被拒后，show_plan 旧 ID 仍可能再次交付未修改版本。证据为交付目录 `sdk-replace-redisplay-probe.json` 和同名说明。App 未增加绕行；正向合法换套与本次真实模型用例通过，不能替代该负向缺口。

等待 SDK 新提交后，统一升级三个 ref/lock，接入真实快照和 SDK 推荐卡，补相应恢复/显示回归，再完成 +39 的构建和收据。`main`、`release/1.0` 不操作；推送和合并仍须开哥真机确认。
