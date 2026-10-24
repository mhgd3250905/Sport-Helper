# AI 对话会话控制下沉（2026-10-24，待审）

本轮将 SmartFit 与其它宿主重复的 AI 会话控制移入 SDK 的纯 Dart `CoachConversationController`，SmartFit 先接入。SDK 起点为 `main@854c44c`，SmartFit 起点为 `main@ad1c979`；开发分支均为 `feat/coach-conversation-controller-20261024`。当前未合 main、未推送发布 tag，完成验证后交开哥审批。

## 迁移边界

SDK controller 持有一个 `CoachAgent`，统一 send、文字/单选/多选回答、同步提交门禁、问题有效期、取消、新对话、恢复历史与销毁。问题只在 send 返回后启用；多选按原选项顺序整理；问题正文与普通回复相同只保留一个问题气泡。新问题或套路、取消、新对话、恢复历史会使旧问题失效，迟到结果不能复活问题。

SmartFit 读取 SDK 的可监听快照，替换自己的“等待回答”与“当前问题”事实源。App 的安全脚本、本地快捷指令、诊断与本地回落、条件解析、计划重命名和重新门禁、历史持久化、保存、导航及训练启动继续留在 App。`TrainingPlan` 到 `CoachRoutine` 的映射本轮不迁移。没有 Key 时隐藏所有 AI 入口的开关规则不变。

参考只读快照为 HipLab `64daf6a` 与 Flare 本机 master `63d3318`。本轮不修改这两个仓库，也不向 SmartFit `release/1.0` 写入或推送。

## 拟发布依赖

| 包 | 本轮安排 |
| --- | --- |
| `ugk_coach` | 拟发布 `ugk_coach-v0.5.0`，新增纯 Dart controller |
| `ugk_trainer` | 拟发布 `ugk_trainer-v0.2.3`，仅对齐 coach 版本约束与 Git tag；训练运行逻辑不变 |
| `ugk_coach_ui` | 保持已发布 `ugk_coach_ui-v0.1.1`；SDK README 补充 controller 接入方式，UI 运行代码不变 |

新 tag 的正式 SHA 待审批后发布时核对；不移动或重打旧 tag。验收分支可能使用本地隔离候选来源预验，但最终 App 依赖须锁正式 tag，并在 SDK 发布后从正式远端重新 Pub 验证，再合 SmartFit main。

## Controller 接口

构造：`CoachConversationController(agent: ..., clock: ..., choiceSeparator: ...)`。同一 agent 由 controller 管理 send/reset/dispose，HTTP client 的生命周期由 App 管理。

| 接口 | 用途 |
| --- | --- |
| `state` / `states` / `addListener` / `removeListener` | 读取或监听不可变消息、待答问题、等待状态、已准入套路、错误和最近结果；listener 同步，states 为异步广播且不回放 |
| `events` / `agent` | 读取同一个 agent 的进度事件或记忆配置；发送与生命周期仍由 controller 独占 |
| `send` | 发起普通输入或继续当前多轮任务 |
| `canAnswer` / `choiceText` | 检查当前问题资格，或取得按原选项顺序整理的合法答案文字 |
| `answerText` / `answerChoices` | 同 agent 继续回答，首个 await 前锁定，拒绝重复提交或过期问题 |
| `invalidateQuestion` | App 明确走本地命令时使旧问题失效 |
| `cancel` / `newConversation` | 取消当前轮或 reset 同 agent 开始新对话 |
| `restoreHistory` | 只恢复展示快照，历史问题不可答，不重建工具协议历史 |
| `dispose` | 幂等取消、重置和销毁所持 agent，关闭状态通知 |

SDK 完整接入说明和 Flutter 问题气泡映射见待审 SDK 提交中的 `docs/coach-conversation-controller.md` 与 `packages/ugk_coach_ui/README.md`，供 HipLab / Flare 后续自行升级。

发送/回答的返回值为 `CoachTurnResult?`。重复或无效调用返回 null；取消、外部取消信号或重置作废的在途轮次也可返回 null。等待中保留的问题快照不能直接用于启用 UI，须调用 `canAnswer(id)`。输入过长等未消费输入可保留问题供重试。

## 待审验收回执

本轮使用 Flutter 3.44.7 / Dart 3.12.2 完成验证。SmartFit 全量测试与分析使用候选 Git 源码，非本地路径覆盖；正式远端尚无本轮 tag。证据保存在项目目录 `deliveries/coach-conversation-review-20261024`，最终提交 SHA 收录在该目录的 `review-receipt.json`。

| 项目 | 当前状态 |
| --- | --- |
| SDK 待审 SHA | `d7e0b8fa3afc514fe3a53427cfddb8f7b24c984f` |
| SmartFit 待审 SHA | 本待审分支提交，完整 SHA 见交付回执（避免文档自引用提交哈希） |
| SDK 常规测试 | 新增 controller 14/14 通过；全 SDK 471/471 通过；`dart analyze` 无问题。覆盖多轮到套路，文字/单选/多选及排序，重复提交，取消/新对话/恢复历史，send 后启用，同 agent 复用与文字去重 |
| SmartFit 验证 | 真实 agent 问答与 UI 定向测试 55/55；全量 454 通过 / 13 原有条件跳过 / 0 失败；`flutter analyze --no-pub` 无问题 |
| 候选 Git Pub | 隔离候选 bare 镜像中两拟发布 ref 指向 SDK 待审 SHA；`flutter pub get --enforce-lockfile` 通过。无路径 override；除 coach/trainer ref、SHA 和版本外锁文件不变 |
| 正式远端 Pub | 待批准并发布 SDK tag 后执行 |
| 合入/推送 | 等开哥同意后，先 SDK 与 tag，再正式远端 Pub，最后 SmartFit main |

AI 开关和无 Key 隐藏入口的现有测试随全量检查通过。本轮未调用实际模型服务或使用真实 Key。App 超时回落仍由本地逻辑负责，回落消息不借用已失效问题的 SDK 消息 ID。
