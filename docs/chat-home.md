# 对话式主界面

## 当前 +41 菜单补项（2026-10-29）

同一 `codex/ui-polish-1 / +41 / 2041` 继续修复菜单：单240ms控制器、固定面板、键盘共用占位及独立重绘边界。我的计划原地展开仍等待SDK最小公开接口授权，不能记为完成。用户无真机且明确不启动模拟器，由用户远程安装验收；当前软件验证与新APK回执见[本轮记录](ui-polish-1-plus41-menu-supplement-2026-10-29.md)。新交付独立位于 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-supplement/`；下方SDK488初包及其他旧验证均保留为历史。

## 同一+41的SDK488补充（2026-10-29）

推荐动作卡使用SDK默认样式，打开单动作给SDK训练页传preview；整套计划▶/开始仍为training。SDK完成页最终回执按同sessionId保存感受与训练记录，日志记录固定枚举，不改变教练会话、推荐或记忆。训练页移除SF天空及自绘完成效果，动作库与推荐卡均复用SDK。完整入口、兼容和验收边界见[SDK488补充](ui-polish-1-plus41-sdk488-2026-10-29.md)。

## 当前变化（+41，2026-10-29）

生成卡改为用户可读的标题/状态和SDK来源标签，隐藏原节点stamp；当前轮参数与已选动作直接取SDK账本，尚未收到当前轮task时显示初始准备态。交付通过同一会话条目作300ms交叉淡入和高度过渡，取消或新对话不关联旧交付。输入遮罩随实际输入高测量，从其上方72到输入底、与底部功能区同色。共用卡面与按钮通过公开SDK主题hook注入；SDK布局边界和未完成项详见[本批说明](ui-polish-1-plus41-2026-10-29.md)。

以下为 +40 基础行为及历史状态；涉及等待气泡旧展示的描述由上方 +41 变化替代。

## 基础行为（+40，2026-10-28）

当前为 `codex/coach-v2` 的 `0.1.0+40`，打包源码 `428c5f3db4a90907889a2fa3e0eb9633b38a48b0`，SDK 三包统一固定 `1532f0825b93777139be0e92e715ebec144a73b9`。开哥确认基础功能可用；包身份和主线边界以[版本台账](version-management.md)为准，自动化、本机模型和设备证据以[验收记录](acceptance.md)分别记录。

### SDK 会话与展示

正常输入交给 SDK `CoachAgent`，App 传空 `CoachContext`，不补场景、器械、时长，不从旧计划或历史消息继承条件。参数来源、追问、任务节点与计划版本由 SDK 账本管理。显式 App 按钮和安全确认仍由宿主处理。

- 等待气泡映射 SDK 节点，纵向展示，完成后折叠为一行。
- 询问使用 `CoachQuestionBubble`，回答、选项、表单和跳过调用对应 SDK 接口。
- 推荐使用 `CoachRecommendCard`；打开动作进入现有 SDK 单动作训练；排计划发送“请把刚才推荐的动作排成计划。”。
- 计划由 SDK 卡片展示，可保存或进入 SDK 跟练页。失败显示 `CoachFailureBubble`；手动选条件的本地模板功能独立保留。

保存 SDK `exportSession()` 的完整快照及显示消息；重开使用 `restoreSession`，旧档无快照走 `restoreHistory`，恢复回落只记日志。新对话取消当前请求，先保存开发者快照再 reset；归档期间输入等候重置完成。已保存计划、训练记录、记忆与设置继续保留。

### 输入和底部面板

输入框左侧为宫格/键盘开关，点击收起键盘并展开面板；再次点击、点对话区或返回操作收起面板，点输入框切换键盘。面板高度按行数、宽度和文字缩放自适应，背景随页面，开合平滑。四项入口为“我的计划、新对话、动作库、设置”；我的计划在独立页面中打开、删除。返回主页或回到前台时不自动聚焦输入框。

动作库与单动作训练使用 SDK；开始训练直接进入 SDK 跟练页，媒体下载、缓存和完整性校验继续由 App 提供数据源，训练加载与时序由 SDK 管理。

### 代码与配置入口

| 路径 | 当前责任 |
| --- | --- |
| `lib/chat/ai_chat_engine.dart` | SDK 会话适配、传输、取消及节点事件 |
| `lib/chat/chat_controller.dart` | 显示、安全确认、保存计划、SDK 快照及新对话归档 |
| `lib/chat/ai_coach_config.dart` | 四项 dart-define；当前 Bearer 配置，兼容可选 worker 分支 |
| `lib/ui/chat/chat_home_page.dart` | SDK 卡片映射、面板与导航 |
| `lib/ui/chat/chat_widgets.dart` | 输入、气泡容器及面板控件 |
| `lib/diagnostics/` | 仅开发者日志的原话、工具参数与回执摘要、版本和会话归档 |

当前模型 `deepseek-flash`，地址 `https://ai.uuugk.win/v1`。客户端重试为 0，SDK 预算沿用默认，App 外保护 390 秒。Key 只在执行时注入，不记录请求头或 Key；[开发者日志](developer-logging-2026-10-28.md)中的工具数据不进入聊天 UI。

+40 本机真实模型验证：“拉伸一下臀部”先问“想在哪拉伸臀部？家里、办公室还是健身房？”，回答“在家”后交付推荐卡。共 10,693 ms、5 次调用，无报错，`scene=home / source=user / quote=在家`。本机日志版本来自 APK aapt；本轮没有装机或真机性能采集。

## 历史对话实现

<details>
<summary>+34 及更早的对话协议、抽屉、模板回落与截图说明</summary>

以下为对应日期的历史原文，旧文件名、旧模型与行为不作为 +40 的实现说明。

> 2026-10-26 最新状态：+32 扁平 main（06ea39d）保持不动；独立分支 +34 已接通 SDK v3 与按动作下载，内测出包及边界见[当前记录](posehub-on-demand-v3-2026-10-26.md)。下方为 +32 阶段及更早历史。

## 当前扁平候选（2026-10-26，待真机验收）

- App 候选为 `0.1.0+32`，分支 `feat/solid-surfaces-20261026`；扁平视觉基线为 `353f146b42a434d999e83912fe3e1147422a787e`。
- 正式依赖：`ugk_trainer-v0.3.1` 与 `ugk_coach_ui-v0.2.1`，均指向 `c6e261e75dc8647ccc2767bc253af664957c516b`；coach 保持 `ugk_coach-v0.5.0`。
- 保留页面结构、功能、星尘、A2 青绿以及透明人物出框；卡片、顶栏、底栏、输入、建议、弹层使用三档不透明实色表面。
- `packed_alpha.frag` 及其透明视频合成路径是播放功能，必须保留；本轮不接入或替换 219 素材。
- 本轮不改 App `main` 或 `release/1.0`；原有聊天、保存计划、训练记录、设备身份及其他用户数据不清空。
- 全库 `flutter analyze --no-pub` 为 0 问题；截图测试通过，已生成[首页/对话浅深预览与底部细节](../../deliveries/flat-release-20261026/screenshots-v2)。这些图来自实际 Flutter widget 渲染，不是真机截图，不证明安装、性能或设备验收已完成。
- 当前指定红米不可连接；安装、真机 Raster P99 与持续训练待实际采集。包体及对照变化以 `deliveries/flat-release-20261026/release-apk.json` 构建回执为准，旧 APK 的历史数字不代表本候选。
- 最终按 120Hz 的 8.33ms 预算检验计划卡滚动、长聊天、进页、底部切换与训练播放，浅深分别采集；逐帧原始整数微秒计算 P99，并报告超预算帧数。

退役的实验文档、报告和旧图已按原字节移出候选，原文与 SHA-256 见 [历史证据归档清单](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。下方历史记录只描述各自时点，不代表本候选重新通过了那些检查。

当前保存版本为 `feat/voice-aac-comparison` / `0.1.0+15`，运行源码 `15079e6`，本地标签 `smartfit-v0.1.0+15-internal-verified`。开哥于 2026-10-23 确认本次测试通过；App 固定 SDK `f684e02`（coach 0.3.3 / trainer 0.1.6），保留无顶部栏与已合入的 PR #5 计划卡优化，增加内测日志及 Android 发布包存储修复。当前本地主线仍为 +12，本次仅保存版本；包身份与验收范围以[台账](version-management.md)和[验收记录](acceptance.md)为准。

历史 +10 分支 `fix/chat-without-top-bar` 按真机反馈移除顶部「新对话」栏，聊天直接使用系统状态栏以下的空间；「新对话」移到左下角计划抽屉，仍可取消当前请求并 reset。底部输入与建议栏保持原有布局。

历史 +9 通过 [PR #4](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) 完成当时的界面整合：输入栏与建议浮动在对话上方，紧凑计划卡原地展开，展开后保存；开始训练仍交给共享 SDK。当时 237 项测试与实际浏览器深浅色交互通过。新对话、取消/进度、门禁动作/计划卡和 AI 记忆保留。下面 `+8` 的说明和旧截图属于 SDK 接入阶段；PR #4 截图记录基础样式，计划卡细节另见 [PR #5](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。

主界面只有一段对话：漂在无边的空间里（默认跟随系统，可切换深空或浅色「白色无边空间」，保留已有外观选择），没有标题栏和边框。视觉规范见 [design-language.md](design-language.md)。助手可回复文字、动作卡或计划卡：动作卡点开详情，计划卡可开练或保存。SDK 接入阶段的 `0.1.0+8` 使用 SDK 0.3.2，2026-10-21 经开哥授权合入 `ebb0840`，已推送 origin/main 并核对远端一致。旧 `+7` 功能随本次进入主线，旧证据不替代本轮独立验证。AI 最终失败使用「预设方案」。

当前里程碑与验收边界见 [版本管理与台账](version-management.md)。可以直接说「看看动作库」「上次练了什么」「换浅色」「关闭语音」「设置」「重新安全确认」或「自己选条件」；抽屉仅保留已存计划、动作库与设置。这些本地操作和安全门禁优先于 AI，不把模型回复直接当成操作指令。下方截图保留原对话首页的视觉记录，不是本次 AI 真机证据。

| 开场对话 | 安全确认 | 追问 | 计划卡片 | 已存计划抽屉 |
|---|---|---|---|---|
| [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |

## 结构

```
lib/chat/chat_models.dart      ChatMessage / ChatOption / Slots / ChatState / ChatReply + ChatEngine 接口
lib/chat/slot_parser.dart      槽位解析（目标、场景、器械、时长、水平、部位、需保护部位）+ 改计划意图
lib/chat/rule_chat_engine.dart RuleChatEngine：追问 → 选模板 → TemplatePlanGenerator → PlanValidator；改计划；已存计划
lib/chat/ai_chat_engine.dart   长期持有 CoachAgent；typed 工具结果、进度事件、本地回落、取消/reset、持久化卡片恢复重验
lib/chat/ai_coach_config.dart  Worker 地址、模型、X-App-Key / X-Device-Id 鉴权（无 Authorization）
lib/app/device_identity.dart   本机随机 UUIDv4；持久化成功后才返回，供 Worker 限流
lib/app/user_memory_store.dart App 实现 UserMemoryStore.load/save，独立本机记忆键
lib/data/app_store.dart        AI 记忆开关及其他本机设置、聊天、计划、训练结果
lib/chat/chat_controller.dart  会话状态、开场安全确认、保存/开始/练完、历史（AppStore，最近 60 条）
lib/chat/safety_script.dart    免责声明 + 4 个安全问题 + 各自建议（含义与原安全页一致）
lib/ui/chat/                   cosmos（背景）、chat_widgets（气泡/选项/输入框/建议）、action_card、validated_plan_card、plan_card、saved_plans_drawer、expand_route
lib/ui/theme/                  设计 token（颜色/字号/间距/圆角/动效）、Material 主题与 SfPaletteScope、图标、按钮金字塔
```

## AI 接入（0.1.0+8 / SDK 0.3.2，核心已验，已合入并推送 main）

`ugk_coach 0.3.2` 与 `ugk_trainer 0.1.4` 的 git ref 均固定 SDK main `b26e4fda807b6ef3db15a61ba30c67fb51dce5e1`。保留 `CoachAgent`、`CoachTurnResult` 和 typed 卡片边界；Agent 读 skill、核对后交付 `show_actions/show_plan`。默认最多 100 逻辑步，同一步重试不占新步骤；`CallOutcome` 没有新增枚举，重试记录使用 `UsageRecord.retry`。BaseURL、模型及鉴权仍为 `https://api.uuugk.win/v1`、`deepseek-v4-flash-0731`、`X-App-Key/X-Device-Id`，App Key 仅经 dart-define 注入，无 Authorization。

`AiChatEngine` 长期持有 Agent；关闭界面保留会话，「新对话」取消并 reset，作废结果不回写。请求中禁用发送、保留取消入口，`cancelled` 不显示。`reading/checking` 显示查库/核对计划；`retrying` 显示「网络不稳，正在重试（n/max）…」，上下文过长的 1/1 特例显示「正在整理上下文，继续思考…」；`slow` 显示「还在想…」。SDK 单次请求 60 秒、整轮 360 秒、每步最多 4 次重试，30 秒发慢提示；客户端 `maxRetries=0` 避免双层重试，App 外保护 390 秒，门禁最多重交 2 次。

纯文字只使用 SDK 接纳后的文字结果显示气泡；动作卡只接 `ValidatedActions`，计划卡只接 `ValidatedPlan`，保存、恢复和交给 `ugk_trainer` 的边界保持不变。模型原始输出、未接纳工具参数与中间读取结果不进入渲染层；恢复持久化卡片时重新过 SDK 门禁。失败仍回落本地模板并标「预设方案」，回落计划也要通过 `admitTemplate`。每轮 `CoachContext` 继续传入用户水平、时长、保护部位及场景/器械；AI 动作目录仍为实际随包 93 个动作。

App 实现 `LocalUserMemoryStore`，以 `load/save` 整表读写独立本机键 `smartfit.ai-memory.v1`；`enableUserMemory` 默认开启，开关持久化并即时同步 Agent。SDK 每条记忆工具等待真正保存成功才确认；已确认事实在后续取消/reset 时保留，未确认的迟到写入按 SDK 契约补偿。关闭保留原记忆；清除等待 `clearMemory()`，保存失败会抛错，成功后复读存储确认已空才提示成功。

开关和清除均保留当前聊天与已保存计划。当前对话已明确说过的条件仍属于对话上下文，因此验证关闭后不再引用本机记忆时，要先开「新对话」隔离旧消息和 App 已解析条件；新对话本身不删除本机记忆。记忆开启时摘要随请求上传；普通 App 操作、已存计划列表和训练历史仍不自动上传。UUID 保持独立键 `smartfit.device-id.v1`，不随清除记忆改变。

最终失败按重试用尽、不可重试、整轮超时或空转显示不同「预设方案」提示，异常与原始输出不进 UI。SDK 0.3.2 已在 main，App 不 patch SDK。App `b39304488e964b22a65501363a15140b5d0ca235` 的 224 项测试、分析、锁文件及 debug 构建通过。六条新交互均 ok、无回落，显式动作卡独立严格补验也通过。原臀桥合法文字导致的脚本无卡断言失败 / exit 1 保留，不称原脚本全通过。完整记录见 [0.3.2 验证](coach-032-smoke-2026-10-21.md)，旧 `+7` 仅属 [历史](coach-agent-smoke-2026-10-21.md)。

## 上一阶段 AI 接入（0.1.0+6 工具会话，历史）

以下保留 `+6` 的接口、超时与验收记录，不代表 `+7` 的当前实现或验证结果。

`ugk_coach 0.2.0` 与 `ugk_trainer 0.1.4` 通过 git 依赖共同固定到 SDK main commit `09a392bc0b736e6a23eef71d55d86108660e0e59`。入口改为 `CoachSession.send()`，不再使用旧版 `CoachAssistant.ask()` JSON 信封路线。BaseURL 为 `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`；App Key 只通过 `--dart-define=SMARTFIT_AI_TOKEN` 注入。SDK `UgkWorkerAuth` 发送 `X-App-Key` 和持久化 UUID 的 `X-Device-Id`，不发送 `Authorization`。

纯文字结果按气泡显示；`show_actions` 只将 `ValidatedActions` 交给 `ActionCard`，动作名称、媒体和详情入口从本地动作库按已验证 id 解析。`show_plan` 只将 `ValidatedPlan` 交给 `ValidatedPlanCard`，再适配同一 TrainingPlan v1 保存或交给 `ugk_trainer` 开练。模型原始响应、工具参数和未通过门禁的内容不进入渲染层。已保存展示历史恢复为卡片前重新过 SDK 门禁，无法接纳的卡片不恢复。

App 生命周期内长期持有一个 `CoachSession`，关闭 AI 界面不清空；「新对话」取消当前请求并调用 `reset()`，旧轮晚到也不会写回新会话。发送期间禁用发送按钮，SDK 对重复发送立即返回 `busy`，不排队。等待态说明首轮计划可能需要 75–120 秒，并提供取消入口；`cancelled` 结果不显示。配置为单次 HTTP 超时 120 秒、HTTP 重试 0 次；门禁可要求模型最多重交 2 次，即最多 3 次提交，整轮保护超时 365 秒。

每轮 `CoachContext` 传入已知的用户水平 `level`、时长 `minutes`、保护部位 `avoid`，以及场景、器械等条件。明确给出的水平和时长是门禁硬约束，计划不一致时要求模型重交。断网、超时、限流或门禁最终失败使用原有 `RuleChatEngine` / `TemplatePlanGenerator`，回复和计划标「预设方案」；模板计划也经 SDK `admitTemplate`，不合格时不显示计划卡。每设备 30 次 / 10 分钟的限制由服务器执行，429 不在 HTTP 层自动重试。

随包 `assets/coach/smartfit.json` 与 SDK `09a392b` 的 `profiles/smartfit.json` 一致，其 `notes` 提及全目录 142 动作及 49 个未带素材的动作。该备注不表示 App 已加载 142 动作：`AppServices.loadContent()` 使用 SDK `DrillPackAdapter` 从实际 `PackSet.exercises` 构造 AI 目录，当前只注入随包 93 个动作，工具 schema 和门禁都使用这份目录。

模型请求包含当前输入、本轮训练条件、用户明确采用的当前计划和该 `CoachSession` 的历史（含已接纳工具调用与门禁反馈）；本地控制消息不充当模型历史，已存计划和训练历史不自动上传。本机随机设备 UUIDv4 使用独立键 `smartfit.device-id.v1`，首次持久化成功后才用于 AI 请求，存储失败使用本地引擎。构建配置见 [README](../README.md#构建)。本次不修改 SDK 代码，也不修改 pub 缓存。

`+6` 的分析、测试与模拟器 Worker 冷烟结果以 [验收记录](acceptance.md) 为准，本文不预先标记通过。本轮没有真机验收结果，旧包真机记录不代替本次工具会话验证；2026-10-21 已经开哥授权合入 `main`（`f83642e`）。

## 旧 AI 接入记录（0.1.0+5 / +4，历史）

旧 `feat/smartfit-ai-replies` / `+5` 使用 `ugk_coach 0.1` JSON 信封接口，不同于 `+6` 工具会话和当前 `+7` Skill Agent 实现。`+5` 源码为 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`，6 项接口/UUID/鉴权配置测试及分析通过；旧源全量 180 项此前通过，该轮未重跑。debug 包已保留数据覆盖安装。新地址实机通用问答通过（27,722 ms，1 次 HTTP 请求）；三次计划请求分别等待 43,447 / 41,589 / 41,952 ms 后均因 `all upstreams failed (tencent:AbortError)` 回退本地，第三次已简化为 3 动作 / 3 分钟。用户确认服务调整完成后重试仍发生，已显示本地模板提示且继续可用，新接口计划生成未通过。服务器 30 次 / 10 分钟配额未实际刷到第 31 次，仅自动化覆盖 429 不重试与提示。

`+5` 实际界面另已保存旧 `+4` 接口生成的「办公室肩颈放松」10 动作原始 AI 计划，从原卡进入 `ugk_trainer`，视频/倒计时正常，暂停后于 34 活动秒提前结束；重启后计划与部分训练结果保留，设备标识未变，前台服务已释放。请求通过调试 VM 延时调用真实 `ChatController`，由界面确认回复/卡片；保存、开练、暂停、结束均为实际 UI 点击。完整记录见 [验收记录](acceptance.md)，这次局部流程不代表新地址 AI 计划链路通过。

旧 `0.1.0+4` / `cc16f530944cf4f6034365aa111528536978ecc3` 的分析及 180 项测试通过；旧地址实机曾约 21 秒成功生成 AI 计划，随后追问回落本地。上述旧记录不代替 `+6` 或 `+7` 的独立验收；`+5` 阶段未合 main 或推送。

## 本地操作与预设方案规则（RuleChatEngine）

以下追问次数和模板编辑规则描述本地引擎；AI 正常可用时，训练问答与工具选择由 `CoachAgent` 处理。本地 App 操作和安全回答仍优先处理。

- 信息不足时短句追问，最多两问，带可点选项：想练哪方面？→ 大概几分钟？→（力量/全身/核心且在家时）有哑铃或弹力带吗？问满两次仍缺的按默认（徒手）并在回复里说明。热身/拉伸不问时长。
- 一句话说全（「在办公室午休 10 分钟，肩颈很僵」）直接出卡片。
- 改计划：再短一点 / 长一点 / 改成 N 分钟；简单点 / 难一点（入门↔基础↔进阶）；换掉第 N 个 / 换掉<动作名> / 换一个（反问哪个）；换一套。卡片后补一句「有哑铃」「在家」「膝盖疼」会按新条件重排。
- 复用：上次那个 / 老样子（最近开始训练的计划，否则最近用过的已存计划）；我的计划（列出已存计划，点选调出）。
- 安全：开场 4 问任一「是」→ 给出对应就医/停止建议，不生成计划，只开放动作库；说到胸闷、头晕、心慌等 → 建议停止并就医；提到某部位疼 → 避开相关动作并提醒持续疼痛先就医。可在「关于与设置」重新确认。
- 无关闲聊 → 「这个我帮不上忙，我只负责帮你安排训练」+ 建议，不假装闲聊。

## 开始训练：卡片展开成跟练页

| 跟练 · 准备 | 跟练 · 训练中 | 跟练 · 休息 | 浅色 · 卡片 | 浅色 · 跟练 |
|---|---|---|---|---|
| [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [历史图像索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |

- 计划卡片封面上的「开始」圆盘、抽屉里已存计划的 ▶：`CardExpandRoute`（`lib/ui/chat/expand_route.dart`）做容器变换——卡片 500 ms 内放大到全屏（`fastOutSlowIn`），先铺天空底色，跟练页按全屏尺寸布局后随卡片宽度缩放并淡入（中途不重排），背后的对话只变暗不缩放。返回 420 ms 收回卡片当前位置；从抽屉开始的（抽屉已关）收回到对话中间。系统「减少动画 / 移除动画」时只淡入淡出。路由展开后不透明，对话页（含星尘）停止绘制。
- 跟练页（`PlayerPage`）结构参照 HipLab 训练页：顶栏关闭 · 区块名 + 进度条 · n/N；视频直接放在与渲染底一致的舞台上（保持媒体原色与原构图），左上「已暂停 / 换左侧」、右上「不舒服」标签；动作名、组次与剂量、计时环（训练中强调色，准备/休息中性色）、要领；训练中下方显示「下一个」；底部上一个 / 暂停（全页唯一强调色圆盘）/ 跳过。完成页、不舒服面板、结束确认框同一套 token。计时、语音时序、视频播放与左右镜像、中断恢复、记录逻辑都没改。

## 视觉与性能

- 背景：两色天空渐变 + 一团极淡冷光 + 48 颗微尘缓慢上漂（CustomPainter，独立图层，≤30 fps）。App 进入后台、被其他页面覆盖（跟练中）、系统「减少动画」、或「关于与设置 → 星尘动效」关闭时停止。
- 气泡与卡片：使用集中 token 的不透明实色表面；滚动内容不采样页面背景。
- 字体：内置 Noto Sans SC 可变字重子集（4.1 MB，OFL），真机与截图字重一致。

## 本轮核心验证

`+8` 的六条新交互均 ok、无回落，真实覆盖重试恢复、slow、记忆持久化与隔离；独立 show_actions 严格补验 4 步、72.908 秒通过，App 接收原准入动作对象，未误交付计划。原六条脚本的臀桥无卡断言失败及 exit 1 如实保留。2026-10-21 开哥授权以 `ebb0840` 合 main，合并树等于审核分支 `f0ebafc`，运行源码、测试和 APK 保持 `b393044`，本次未重跑；已推送 origin/main 并核对远端一致。完整指标见 [0.3.2 验证记录](coach-032-smoke-2026-10-21.md)。

</details>
