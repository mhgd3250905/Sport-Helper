# 对话式主界面（feat/chat-home）

主界面只有一段对话：漂在无边的空间里（默认深空，可切换浅色「白色无边空间」），没有标题栏和边框。视觉规范见 [design-language.md](design-language.md)（2026-10-19 按 HipLab 设计纪律重做）。助手回复训练计划卡片，点「开始训练」进入现有跟练，「保存」后可复用。**当前不接大模型**，全部离线规则；模型接入时只换引擎，不动界面。

| 开场对话 | 安全确认 | 追问 | 计划卡片 | 已存计划抽屉 |
|---|---|---|---|---|
| ![](screenshots/chat-opening.png) | ![](screenshots/chat-safety.png) | ![](screenshots/chat-ask.png) | ![](screenshots/chat-card.png) | ![](screenshots/chat-drawer.png) |

## 结构

```
lib/chat/chat_models.dart      ChatMessage / ChatOption / Slots / ChatState / ChatReply + ChatEngine 接口
lib/chat/slot_parser.dart      槽位解析（目标、场景、器械、时长、水平、部位、需保护部位）+ 改计划意图
lib/chat/rule_chat_engine.dart RuleChatEngine：追问 → 选模板 → TemplatePlanGenerator → PlanValidator；改计划；已存计划
lib/chat/chat_controller.dart  会话状态、开场安全确认、保存/开始/练完、历史（AppStore，最近 60 条）
lib/chat/safety_script.dart    免责声明 + 4 个安全问题 + 各自建议（含义与原安全页一致）
lib/ui/chat/                   cosmos（背景）、chat_widgets（气泡/选项/输入框/建议）、plan_card、saved_plans_drawer、expand_route
lib/ui/theme/                  设计 token（颜色/字号/间距/圆角/动效）、Material 主题与 SfPaletteScope、图标、按钮金字塔
```

**接大模型**：实现 `ChatEngine.reply(text, state)`（同一接口），产出的计划仍是 TrainingPlan v1，必须过 `PlanValidator`；失败时回落到 `RuleChatEngine`。在 `AppServices.chatEngine` 处替换即可。

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

见 PR 描述。
