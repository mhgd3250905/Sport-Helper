# 对话式主界面

主界面只有一段对话：漂在无边的空间里（默认跟随系统，可切换深空或浅色「白色无边空间」，保留已有外观选择），没有标题栏和边框。视觉规范见 [design-language.md](design-language.md)（2026-10-19 按 HipLab 设计纪律重做）。助手回复训练计划卡片，点「开始训练」进入现有跟练，「保存」后可复用。`feat/smartfit-ai-replies` 已接入 AI 代理，当前待验版本 `0.1.0+5`；未配置或调用失败时仍可用本地规则与模板。

当前里程碑与验收边界见 [版本管理与台账](version-management.md)。可以直接说「看看动作库」「上次练了什么」「换浅色」「关闭语音」「设置」「重新安全确认」或「自己选条件」；抽屉仅保留已存计划、动作库与设置。这些本地操作和安全门禁优先于 AI，不把模型回复直接当成操作指令。下方截图保留原对话首页的视觉记录，不是本次 AI 真机证据。

| 开场对话 | 安全确认 | 追问 | 计划卡片 | 已存计划抽屉 |
|---|---|---|---|---|
| ![](screenshots/chat-opening.png) | ![](screenshots/chat-safety.png) | ![](screenshots/chat-ask.png) | ![](screenshots/chat-card.png) | ![](screenshots/chat-drawer.png) |

## 结构

```
lib/chat/chat_models.dart      ChatMessage / ChatOption / Slots / ChatState / ChatReply + ChatEngine 接口
lib/chat/slot_parser.dart      槽位解析（目标、场景、器械、时长、水平、部位、需保护部位）+ 改计划意图
lib/chat/rule_chat_engine.dart RuleChatEngine：追问 → 选模板 → TemplatePlanGenerator → PlanValidator；改计划；已存计划
lib/chat/ai_chat_engine.dart   AI 对话与 SDK 计划生成、严格校验、本地回退及可发送上下文筛选
lib/chat/ai_coach_config.dart  Worker 地址、模型、X-App-Key / X-Device-Id 鉴权（无 Authorization）
lib/app/device_identity.dart   本机随机 UUIDv4；持久化成功后才返回，供 Worker 限流
lib/chat/chat_controller.dart  会话状态、开场安全确认、保存/开始/练完、历史（AppStore，最近 60 条）
lib/chat/safety_script.dart    免责声明 + 4 个安全问题 + 各自建议（含义与原安全页一致）
lib/ui/chat/                   cosmos（背景）、chat_widgets（气泡/选项/输入框/建议）、plan_card、saved_plans_drawer、expand_route
lib/ui/theme/                  设计 token（颜色/字号/间距/圆角/动效）、Material 主题与 SfPaletteScope、图标、按钮金字塔
```

## AI 接入（0.1.0+5 待验）

BaseURL 为 `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`；沿用原 `X-App-Key` 和原 UUID 的 `X-Device-Id`，不发送 `Authorization`。生成只使用随包 93 个动作，计划必须经过 SDK 与 App 严格校验才显示可保存、可开练的卡片；不合格输出最多重写一次。断网、超时或最终校验失败时回退 `RuleChatEngine`，HTTP 429 显示限流提示并回退本地；每设备 30 次 / 10 分钟的限制由服务器执行。

仅发送 AI 可见的相关对话轮次、当前输入与显式当前计划/训练条件；本地控制消息不充当模型历史，已存计划和训练历史不自动上传。本机随机设备 UUIDv4 使用独立键 `smartfit.device-id.v1`，首次持久化成功后才用于 AI 请求，存储失败使用本地引擎。构建配置见 [README](../README.md#构建)。

当前 `+5` 源码为 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`，6 项接口/UUID/鉴权配置测试及分析通过；核心 180 项此前通过，本轮未重跑。debug 包已保留数据覆盖安装。新地址实机通用问答通过（27,722 ms，1 次 HTTP 请求）；三次计划请求分别等待 43,447 / 41,589 / 41,952 ms 后均因 `all upstreams failed (tencent:AbortError)` 回退本地，第三次已简化为 3 动作 / 3 分钟。用户确认服务调整完成后重试仍发生，已显示本地模板提示且继续可用，新接口计划生成未通过。服务器 30 次 / 10 分钟配额未实际刷到第 31 次，仅自动化覆盖 429 不重试与提示。

`+5` 实际界面另已保存旧 `+4` 接口生成的「办公室肩颈放松」10 动作原始 AI 计划，从原卡进入 `ugk_trainer`，视频/倒计时正常，暂停后于 34 活动秒提前结束；重启后计划与部分训练结果保留，设备标识未变，前台服务已释放。请求通过调试 VM 延时调用真实 `ChatController`，由界面确认回复/卡片；保存、开练、暂停、结束均为实际 UI 点击。完整记录见 [验收记录](acceptance.md)，这次局部流程不代表新地址 AI 计划链路通过。

旧 `0.1.0+4` / `cc16f530944cf4f6034365aa111528536978ecc3` 的分析及 180 项测试通过；旧地址实机曾约 21 秒成功生成 AI 计划，随后追问回落本地。旧记录不代替当前 `+5` 验收；未合 main 或推送。

## 对话规则（RuleChatEngine）

- 信息不足时短句追问，最多两问，带可点选项：想练哪方面？→ 大概几分钟？→（力量/全身/核心且在家时）有哑铃或弹力带吗？问满两次仍缺的按默认（徒手）并在回复里说明。热身/拉伸不问时长。
- 一句话说全（「在办公室午休 10 分钟，肩颈很僵」）直接出卡片。
- 改计划：再短一点 / 长一点 / 改成 N 分钟；简单点 / 难一点（入门↔基础↔进阶）；换掉第 N 个 / 换掉<动作名> / 换一个（反问哪个）；换一套。卡片后补一句「有哑铃」「在家」「膝盖疼」会按新条件重排。
- 复用：上次那个 / 老样子（最近开始训练的计划，否则最近用过的已存计划）；我的计划（列出已存计划，点选调出）。
- 安全：开场 4 问任一「是」→ 给出对应就医/停止建议，不生成计划，只开放动作库；说到胸闷、头晕、心慌等 → 建议停止并就医；提到某部位疼 → 避开相关动作并提醒持续疼痛先就医。可在「关于与设置」重新确认。
- 无关闲聊 → 「这个我帮不上忙，我只负责帮你安排训练」+ 建议，不假装闲聊。

## 开始训练：卡片展开成跟练页

| 跟练 · 准备 | 跟练 · 训练中 | 跟练 · 休息 | 浅色 · 卡片 | 浅色 · 跟练 |
|---|---|---|---|---|
| ![](screenshots/chat-player-prep.png) | ![](screenshots/chat-player-work.png) | ![](screenshots/chat-player-rest.png) | ![](screenshots/chat-card-light.png) | ![](screenshots/chat-player-work-light.png) |

- 计划卡片封面上的「开始」圆盘、抽屉里已存计划的 ▶：`CardExpandRoute`（`lib/ui/chat/expand_route.dart`）做容器变换——卡片 500 ms 内放大到全屏（`fastOutSlowIn`），先铺天空底色，跟练页按全屏尺寸布局后随卡片宽度缩放并淡入（中途不重排），背后的对话只变暗不缩放。返回 420 ms 收回卡片当前位置；从抽屉开始的（抽屉已关）收回到对话中间。系统「减少动画 / 移除动画」时只淡入淡出。路由展开后不透明，对话页（含星尘）停止绘制。
- 跟练页（`PlayerPage`）结构参照 HipLab 训练页：顶栏关闭 · 区块名 + 进度条 · n/N；视频直接放在与渲染底一致的舞台上（不加模糊、不加色、不再套玻璃框），左上「已暂停 / 换左侧」、右上「不舒服」标签；动作名、组次与剂量、计时环（训练中强调色，准备/休息中性色）、要领；训练中下方显示「下一个」；底部上一个 / 暂停（全页唯一强调色圆盘）/ 跳过。完成页、不舒服面板、结束确认框同一套 token。计时、语音时序、视频播放与左右镜像、中断恢复、记录逻辑都没改。

## 视觉与性能

- 背景：两色天空渐变 + 一团极淡冷光 + 48 颗微尘缓慢上漂（CustomPainter，独立图层，≤30 fps）。App 进入后台、被其他页面覆盖（跟练中）、系统「减少动画」、或「关于与设置 → 星尘动效」关闭时停止。
- 气泡与卡片：色调分层，不再使用 `BackdropFilter`（上一版每个气泡一次背景模糊），绘制更省。
- 字体：内置 Noto Sans SC 可变字重子集（4.1 MB，OFL），真机与截图字重一致。

## 需要本机验证

待服务器恢复计划生成后，再做新地址 AI 计划链路的真机验收；当前不申请合并，合 main / 推送等待开哥新批准。旧 `+4` AI 生成、`+5` 局部启动/提前结束及 `+2` 完整训练证据分别保留，不据局部流程或通用问答成功标记整体验收通过。见 [验收记录](acceptance.md)。
