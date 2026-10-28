# 开发者日志：版本、工具与会话快照

日志能力检查点为 `5a1e25405f799bc8835a2d54fc9225dde6d45dfc`，位于 `codex/coach-v2`，当时继承 +39 的 SDK `32d2839a4edb6d47e5ffe362215ec1a94b208824`。该能力已随 +40 `428c5f3db4a90907889a2fa3e0eb9633b38a48b0` 出包，SDK 三包现统一为 `1532f0825b93777139be0e92e715ebec144a73b9`；版本与验收见[台账](version-management.md)及[+40 记录](coach-v2-plus40-2026-10-28.md)。下列日志契约继续适用，仅用于开发者日志，不把参数、工具或快照显示在聊天界面。

## 版本与事件

启动先通过 `package_info_plus` 读取已安装包的 `version` / `buildNumber`。运行日志文件头与 `app.start` 都保存 `versionName`、`buildNumber` 和组合 `version`。Android 的原生构建号包含 ABI 偏移，直接记录原值；读取失败记 `unknown`，不猜测或回退到写死的旧版本。

原有 `record` 继续只接收白名单元数据。新增详细事件通过独立 `recordDeveloper` 写入 `data`，并沿用同一 `operation` 关联用户输入、请求、SDK 节点与交付：

| 事件 | 详细字段 |
| --- | --- |
| `chat.user` | 原始 `text`（保留前后空白及换行）、实际发送的 `sentText`、询问 ID、显示标签、是否宿主明确指令 |
| `ai.tool.requested` | SDK 原始工具名、调用 ID、批次和序号、原始及解析后的参数；`set_params.parameters` 逐项保存 `name/value/source/quote` 等全部原字段 |
| `ai.tool.result` | 同一工具身份、回执来源、`receiptAvailable`、结构化结果摘要 |
| `ai.agent.event` | SDK 原始事件名、轮次、任务、节点；节点事件附当前 SDK 已接受参数的完整来源字段 |
| `chat.session.archived` | 独立会话快照的文件名与保存状态 |

结果摘要只选取状态、错误/修复信息、变化字段、参数、计数等相关字段，避免复制整份目录或技能。取消轮次不套用新轮次的历史，重复历史不重复记录，工具 ID 重用以批次关联。

当前 SDK 的公共历史不公开 `show_plan` / `show_actions` 终端批次逐工具回执。能观察到的真实回执标记 `receiptAvailable: true`，来源为 `request` 或 `history`；其余明确标记 `receiptAvailable: false`、`sdk_receipt_not_exposed`，仅记录 SDK 轮次结果的交付摘要，不伪造工具执行成功。取消且无回执时另记 `cancelled_without_observed_receipt`。

## 新对话归档与保留

开始“新对话”时，先取得当前 `controller.exportSession().toJson()`，在取消/清空前形成归档内容；归档写入完成后才清空 SDK 会话。归档期间的新输入等候这次重置完成，多次点击合并为一次。保存失败只记错误类型，不弹窗、不阻断新对话。

原生路径为 App 私有 Application Support 下的 `diagnostics/session-snapshots/`，文件名 `SmartFit-session-<UTC>-<序号>-<随机后缀>.json`。先在该归档目录的临时子目录写文件并 flush，再在同一文件系统内原子重命名到归档目录；仅轮换本服务文件，保留最近 5 份，不清除其他数据。Web 开发测试使用相同接口的内存归档，不新增下载或 UI。

运行日志沿用最近 7 天、1500 条、512 KiB 的有界保留策略，与会话快照的 5 份保留相互独立。正式 flavor 关闭；内测或显式开启的 debug 才采集详细内容。

## 凭据与请求头

采集器不接收 HTTP 请求头、完整 HTTP 请求或 reasoning。构建注入的 Key 在日志初始化前注册为脱敏值，客户端创建时再次保护实际 Key。递归移除凭据/请求头键，清理原文中的已知 Key、Base64 变体和显式鉴权值；同样处理嵌套 JSON 字符串和归档快照。用户原话及 `quote` 除凭据脱敏外保留原文。

SDK 公开协议回归覆盖真实工具名、失败与跳过回执、终端缺失回执、参数来源及取消；宿主回归覆盖真实版本读取、原话重载、脱敏、JSON 数值溢出、归档顺序、后续输入排队和保留最近 5 份。检查点的测试命令与结果保留在本机 `deliveries/developer-logging/`，不以本地测试替代装机验收。
