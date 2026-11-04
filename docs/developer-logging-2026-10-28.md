# 开发者日志：版本、工具与会话快照

## 当前接线（+21，2026-11-04）

App 当前为 **0.1.0+21 / internal arm64 2021**，功能通过 PR #9 合入 `main@ff91fc56606c11e57d98c0dae79be111074a61e2`；SDK 五包、coach override、锁文件和 AppBuildInfo 统一固定 `f7b8a8e4853e9f50fc93888e1768ec1dbc75b588`。运行、软件验证与 APK 源为 `3d39ca94b4c9144d388255bb56dff6e00f32877f`，与功能合入点同树 `b4a6c96eb2b836c8330ad361fedc2fbb6ad4f29f`、差异为空；本轮文档提交与这两个源分开记录。

既有回执为严格分析 **0 问题**、全量 **689/0/0**，+21 / 2021 包检查通过且签名与 +20 一致。本轮不读取用户日志、不重测或重建、不操作设备；手机验收仍全部待用户远程反馈，没有本版手机 `hasPlan=true` 观察回执。下方 +18 的 685 项及真实 16 轮 / 34 请求保留原绑定，不作为 f7 的真实模型验证。

正式启动显式选择 SDK 公开的 `agentMode: qaV2` 并加载 App aiTags；`AppServices` 构造默认仍为 legacy / 空标签。`CoachChatDiagnostics` 沿用 observer、controller 和 gateway lease 只读观察，既不选择工具也不改变请求、取消、重试、恢复或准入。下文工具与 AgentEvent 条目保留对 legacy 公开事件的观测兼容，只有相应事件实际发出才记录，不承诺 QA 模式也发布相同节点或工具历史。

## +18 与 +54 历史检查点

<details>
<summary>+18 QA 候选及 +54 主线的原始接线与证据</summary>

以下原文中的“当前”、源码和验证数字只属于原检查点；当前接线与字段契约以上方 +21 区及下文说明为准。

## QA v2 测试候选（2026-11-04）

分支 `codex/sdk-pin-v0.7.0`，App **0.1.0+18 / internal arm64 2018**，SDK `ugk_trainer-v0.7.1 / 9dd93163e9f355665e5c923f374c64f03bf65a86`。运行与 APK 源 `55442967ca6593b1279d81adfa030468aacd8731`；以下原 +54 主线记录保留原范围。

原观测客户端和 SDK `chat.turn.result` 继续沿用；QA v2 的 detail 带 `agentMode: qaV2`，不能把 error 轮次的 steps=0 当成没有模型调用。 软件全量 **685/0/0**、严格分析 0；真实 16 轮中 15 成功、1 次计划准入失败，34 请求均核对 max/enabled。计划门禁、器械元数据和肩痛输出的实测问题见[本轮报告](qa-v2-sdk071-plus18-2026-11-04.md)，真机待用户远程安装验收。

## 当前接线（+54，2026-11-04）

当前代码与既有验证源为 `c9823e61457eb3e8839c867c01b5b7fe110d7c73`，App `0.1.0+54 / 2054`，SDK 五包及 coach override 固定 `693cbc02cdf284163409868e117e438515c6a8d8`（`ugk_trainer-v0.6.0`）。`CoachChatDiagnostics` 通过 SDK observer、controller 和 gateway lease 只读观察公开事件与请求；不选择工具、不修改请求/响应，不改变取消、重试或准入。版本与既有软件、设备证据见[台账](version-management.md)及[验收记录](acceptance.md)。本次只更新设计说明，没有读取用户日志或重新操作设备。

</details>

<details>
<summary>+40 日志能力的历史检查点</summary>

日志能力检查点为 `5a1e25405f799bc8835a2d54fc9225dde6d45dfc`，位于 `codex/coach-v2`，当时继承 +39 的 SDK `32d2839a4edb6d47e5ffe362215ec1a94b208824`。该能力已随 +40 `428c5f3db4a90907889a2fa3e0eb9633b38a48b0` 出包，SDK 三包现统一为 `1532f0825b93777139be0e92e715ebec144a73b9`；版本与验收见[台账](version-management.md)及[+40 记录](coach-v2-plus40-2026-10-28.md)。下列日志契约继续适用，仅用于开发者日志，不把参数、工具或快照显示在聊天界面。

以上“现统一”和检查点验证只属于 2026-10-28 原时点；当前接线与字段契约使用下文。

</details>

## 版本与事件

启动先通过 `package_info_plus` 读取已安装包的 `version` / `buildNumber`。运行日志文件头与 `app.start` 都保存 `versionName`、`buildNumber` 和组合 `version`。Android 的原生构建号包含 ABI 偏移，直接记录原值；读取失败记 `unknown`，不猜测或回退到写死的旧版本。

原有 `record` 继续只接收白名单元数据。新增详细事件通过独立 `recordDeveloper` 写入 `data`，并沿用同一 `operation` 关联用户输入、请求、SDK 节点与交付：

| 事件 | 记录内容 |
| --- | --- |
| `chat.user` | `data.text` 优先使用 SDK `CoachChatUserInput.rawText`，缺失时用用户消息文本 |
| `ai.tool.requested` | SDK 原始工具名、调用 ID、批次和序号、原始及解析后的参数；`set_params.parameters` 逐项保存 `name/value/source/quote` 等全部原字段 |
| `ai.tool.result` | 同一工具身份、回执来源、`receiptAvailable`、结构化结果摘要 |
| `ai.agent.event` | SDK 原始事件名、轮次、任务、节点；节点事件附当前 SDK 已接受参数的完整来源字段 |
| `coach_chat.chat.turn.result` | SDK 公开的轮次结果 detail 写入 `data`；存在的 stage、errorType、message、status、reason 进入元数据，另列 kind（来自 failureKind） |
| `coach_chat.<SDK 事件名>` | 其余非 AgentEvent 的 Map detail 只提取存在的 stage、errorType、message、status、reason，不把整个 Map 当作详细事件写入 |
| `ai.turn.end` | 本轮公开结果的 status、elapsedMs、steps、hasPlan、hasActions；结果认领规则见下文 |
| `chat.session.archived` | 独立会话快照的文件名与保存状态 |

结果摘要只选取状态、错误/修复信息、变化字段、参数、计数等相关字段，避免复制整份目录或技能。取消轮次不套用新轮次的历史，重复历史不重复记录，工具 ID 重用以批次关联。

legacy 公开历史的原观测契约中，`show_plan` / `show_actions` 终端批次逐工具回执未公开：能观察到的真实回执标记 `receiptAvailable: true`，来源为 `request` 或 `history`；其余明确标记 `receiptAvailable: false`、`sdk_receipt_not_exposed`，仅记录 SDK 轮次结果的交付摘要，不伪造工具执行成功。取消且无回执时另记 `cancelled_without_observed_receipt`。这是宿主保留的 legacy 观测兼容说明，不据此断言本版 SDK 的内部工具行为。

### SDK Map 诊断字段

`CoachChatDiagnostics._sdkFields` 只取实际存在的 `stage`、`errorType`、`message`、`status`、`reason`，不补造缺失字段；显式 `null` 保留。`RuntimeLog` 仅对 `coach_chat.*` 事件为这五个字段开放字符串 / null 的专用白名单，一般事件仍使用原有元数据规则。`message` 先经凭据脱敏，再截取最多 **300 个 Unicode runes**；详细 `coach_chat.chat.turn.result.data` 顶层的 message 也执行相同规则，重载既有日志时仍经过这些过滤。不能把它描述为无限长、未经处理的原文透传。

### 本轮结果与 hasPlan

开始 typing 时保存 `controller.lastResult` 到 `_resultBefore`。结束时若观察到 AgentEvent turnId，只认领同 turnId 的结果；没有 turnId 时，只认领与 `_resultBefore` 不同的新结果对象，避免沿用上一轮交付。随后 `ai.turn.end` 的 `hasPlan` 取本轮结果 `plan != null`，`hasActions` 同理；未认领到结果的 status 为 `unavailable`。该逻辑适配 QA 接线未提供 AgentEvent turnId 的情况，不要求 App 补写或重放 SDK 轮次。

`hasPlan=true` 表示本轮公开结果带计划，不代表计划已保存、已训练或真机验收通过。error 轮次的 steps 为 0 也不能证明没有模型调用；应分别看实际观察到的请求事件。本轮只对齐这些宿主日志规则，没有读取或生成新的用户手机日志。

## 新对话归档与保留

开始“新对话”时，由 SDK 的 `beforeNewConversation(CoachChatSnapshot)` hook 把清空前快照传给宿主；`CoachChatDiagnostics.archiveConversation` 将 `snapshot.session.toJson()` 交给 `RuntimeLog.archiveSession`。聊天恢复使用的完整 `CoachChatSnapshot` envelope 由 history adapter 独立保存，两者不能混称。SDK 负责新对话与后续输入的顺序；归档失败由日志层记录错误类型，不弹窗、不阻断新对话。

原生路径为 App 私有 Application Support 下的 `diagnostics/session-snapshots/`，文件名 `SmartFit-session-<UTC>-<序号>-<随机后缀>.json`。先在该归档目录的临时子目录写文件并 flush，再在同一文件系统内原子重命名到归档目录；仅轮换本服务文件，保留最近 5 份，不清除其他数据。Web 开发测试使用相同接口的内存归档，不新增下载或 UI。

运行日志沿用最近 7 天、1500 条、512 KiB 的有界保留策略，与会话快照的 5 份保留相互独立。正式 flavor 关闭；内测或显式开启的 debug 才采集详细内容。

自动持久化等待训练转场空闲，合并突发事件并串行写入；完整脱敏及 JSON 编码在 worker isolate 执行，防止旧快照覆盖新快照。导出/显式 flush 仍可要求写入，不把整个训练期间都当作转场。

## 凭据与请求头

采集器不接收 HTTP 请求头、完整 HTTP 请求或 reasoning。构建注入的 Key 在日志初始化前注册为脱敏值，客户端创建时再次保护实际 Key。递归移除凭据/请求头键，清理原文中的已知 Key、Base64 变体和显式鉴权值；同样处理嵌套 JSON 字符串和归档快照。用户原话及 `quote` 除凭据脱敏外保留原文。

观测 OpenAI 兼容客户端时保留其公开的 `config`、`auth`、`buildBody` 与 `close` 接口，真实请求体编码继续委托原客户端，供 SDK 上下文预算使用；这些接口透传不表示把鉴权值、请求头或完整请求体写入日志。

当前接线的相关回归包括 `test/diagnostics/coach_chat_turn_diagnostics_test.dart`、`test/diagnostics/developer_log_details_test.dart`、`test/coach_session_snapshot_test.dart`：分别约束轮次诊断与编码器透传、日志/归档细节，以及 SDK envelope 和 legacy 恢复。测试结果及源码绑定以[验收记录](acceptance.md)为准；本次文档更新沿用已绑定源码的既有回执，未重跑这些测试。

历史 SDK 公开协议回归覆盖真实工具名、失败与跳过回执、终端缺失回执、参数来源及取消；宿主回归覆盖真实版本读取、原话重载、脱敏、JSON 数值溢出、归档顺序、后续输入排队和保留最近 5 份。+40 检查点的测试命令与结果保留在本机 `deliveries/developer-logging/`，不以本地测试替代装机验收。
