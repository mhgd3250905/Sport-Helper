# SmartFit 全 App 流畅度摸排：静态版，等待远程 profile 数据

本报告交开哥审阅，修复方案和动效参数由 Hark 决定。本步只出报告，未修改 App、SDK、测试或动效实现。日期：2026-10-29，Asia/Shanghai。

## 当前结论与边界

1. **“我的计划”单卡变形暂停在 SDK 接口缺口。** 现有收起卡与展开卡确为两个卡面，上一包未满足本次验收。SDK475 的公开组件把整卡收成零高度，缺常驻头部/收起摘要承载与展开触发位置；外壳和标题也位于动画内部。详见[接口缺口报告](sdk-plan-single-card-gap-2026-10-29.md)。不再用 App 另写动画绕过。
2. **目前没有本版本的真机帧样本或录屏。** ADB 未发现设备；开哥已确认远程采集原始报告与录屏。不启动模拟器，不把软件截图、611项历史测试或构建通过当成流畅度通过。
3. 已确认的源码行为包括：整套训练路由进出零时长、深浅色切换零时长；文本为完整响应后一次插入，并无逐 token 输出；App/所用 SDK 页面没有实际 Tab 导航。它们与“某次操作已超过16ms”是不同结论。
4. 当前 +41 第一项尚未验收，App main 不合入。后续顺序是补齐 SDK 单卡合同、完成 +41 验收及 main 合入，再由新 main 创建 `codex/motion-polish-1`，按 Hark 方案做 +42。本轮不创建该分支、不做 +42 修复、不动 release/1.0。

## 基线与取证包

| 项目 | 已核实状态 |
| --- | --- |
| App | `codex/ui-polish-1`；审计/采集包源 `4047072ba71838b2782180a2cd2d486ab0df8c8c` |
| 原 release 源 | `9777eb4a2eed52dda173bd31e2e7f3f69d413b83`；与审计源的产品文件空 diff，后续差异仅文档 |
| SDK 三包及 override | `475a5d84b5d0fce839d9d4475da22a6d1ce2df19` |
| 远程采集包 | `SmartFit-motion-audit-0.1.0+41-4047072-internal-arm64-v8a-profile.apk`；157,009,146 B / 149.74 MiB |
| 实际构建 | `internalProfile`，`com.ugk.smartfit.internal`，原生0.1.0 / 2041；性能扩展已编译，尚未在设备连接/执行 |
| 包 SHA-256 | `304de7d8629d9ade4bd64c5d476812f9f1fcd9b3d085cf01a6f7c113ec8b82ca` |
| 构建门禁 | 与既有 release 同证书，严格锁/SDK/素材、ZIP/ELF16KB、存储JNI通过；父 Agent 再次核对实际字节和哈希 |

该 profile 包保持当前功能，包含尚不合格的旧两卡呈现，只用于基线取证，**不是第一项的新修复 APK**。没有装机、清数据或采集原生帧。[采集包与回执](../../deliveries/motion-audit-20261029/)和[远程采集步骤](ui-motion-profile-remote-2026-10-29.md)一并提供。

## 统计口径

本次严格使用用户指定的 **>16.000ms，即原始整数微秒 >16000**，不是>=16ms，也不是旧工具的16.67ms或120Hz 8.33ms。不得先四舍五入后比较。

- 每项分别列 UI/build 最大值、Raster 最大值，以及各自超16000us的帧数；另列去重超标帧数：同一采样窗口中 `buildUs>16000 或 rasterUs>16000` 的帧只计一次。
- 不把 UI 与 Raster 相加当显示帧耗时。两线程流水工作；真实屏幕掉帧率、GPU完成时间不能从这两个数或录屏FPS推导。engine phase 时间保留供定位，但须说明指标含义。
- 跳动、闪烁、硬切分别记录；代码明确无过渡可作实现事实，未取得录屏不能写“没有闪烁/没有跳动”。网络、文件准备、保存等待等响应延迟单列，不能等同于某一慢帧。
- 不混合不同源码、设备、主题、刷新率、冷/热缓存及录屏开关的数据。主题切换项按明确的起止主题序列单列，不并入静态浅/深主题样本。原始帧截断或窗口不能定位的项保持未完成，不把缺样本写为0超标。

## 按当前证据安排的优先级

以下按**确认不合格 → 明确即时切换 → 待测工作量 → 其他路径**排序，是远程采样/复核优先级，不是已经测得的卡顿严重度排名。真实最大值、超标数量和录屏到齐后，再按影响与实测严重程度重排。所有技术建议待 Hark 裁决，不在本步实施，不新增视觉设计或动效数值。

表中“未采”均表示尚无真机样本；最大值顺序为UI/Raster，超标帧数顺序为UI/Raster/去重。不会以0替代缺失值。

| 优先 | 场景 | 是否>16ms | 最大值 ms | 超标帧数 | 跳动/闪烁/硬切 | 当前实现、建议方向 |
| --- | --- | --- | --- | --- | --- | --- |
| P0 已确认 | M00 我的计划展开/切换/收起 | 未采 | 未采/未采 | 未采/未采/未采 | 两卡交替已由用户确认不合格；原生录屏待回传 | App收起卡与SDK展开卡分别绘制、分别动画；先由SDK补常驻外壳/头部合同，App不另写动画。此项没有新修复交付。[E1] |
| P1 明确即时切换 | M06a 整套训练页进入/返回 | 未采 | 未采/未采 | 未采/未采/未采 | 源码正反duration均zero；实际闪白/聊天闪现未测 | TrainingRoute固定最终视频bounds，避免初始媒体与聊天叠加合成。先分解路由、媒体准备和首帧，不直接给整段视频加淡入/缩放。[E2] |
| P1 明确即时切换 | M08 深浅色切换 | 未采 | 未采/未采 | 未采/未采/未采 | 主题不插值已确定；闪烁/长停顿未测 | themeAnimationDuration=zero；brightness变化递归markNeedsBuild全部后代。长聊天/多计划下先查build峰值，再决定缩小主题依赖范围，过渡方案交Hark。[E3] |
| P2 待测工作量 | M02 新消息出现与完整回复首次布局 | 未采 | 未采/未采 | 未采/未采/未采 | 有SDK入场；整段文本一次显示，是否跳位未测 | node触发chat广播，全历史消息描述重建；80ms快照持久化再广播store。长历史下测同步导出/JSON与双重通知，再考虑隔离当前进度监听、复用消息描述。[E4] |
| 不适用 | M02s 逐 token 流式文字 | 不适用 | 不适用 | 不适用 | 当前没有逐token呈现 | 请求stream:false，等完整响应后追加messages；不能编造流式帧数据，也不在App加打字机来冒充流式。完整回复插入见M02。[E4] |
| P2 待测工作量 | M03a 生成过程卡连续动画 | 未采 | 未采/未采 | 未采/未采/未采 | 快节点/冷缩略图切换是否空帧未测 | 局部controllers、ShaderMask微光、逐帧选图/构建；不等于逐帧重新解码。先测UI分配及Raster着色，若为热点再缓存静态子树与已选动作，保留既定规格。[E5] |
| P2 待测工作量 | M03b 推荐卡/计划卡插入对话 | 未采 | 未采/未采 | 未采/未采/未采 | 正常生成→交付同entry交叉淡入；快回复/离屏重挂可跳过该层过渡 | 保留稳定key；测交付首次布局与冷图片就绪。推荐是两列Wrap一次布局，不能当作长网格懒建。SDK热点由SDK处理，不复制卡片。[E5] |
| P2 待测工作量 | M04 对话计划卡展开/收起 | 未采 | 未采/未采 | 未采/未采/未采 | 已有共享卡/飞图；快速反向及长计划未测 | SDK对话私有时间线550/450ms，与公开280/180路径不同；点击时测文本/避让几何，逐帧高度带列表布局，child已复用。先区分启动测量峰值与持续layout。[E6] |
| P2 待测工作量 | M01 键盘弹出/收起时对话与输入 | 未采 | 未采/未采 | 未采/未采/未采 | 等高交换有保持占位；实际IME跳动/闪烁未测 | Scaffold不自动resize，dock用raw insets和同一controller；消息child缓存但Positioned.bottom每帧改变viewport，RepaintBoundary不能隔离layout。测UI/layout及系统IME分别归因。[E7] |
| P2 待测节奏 | M06d 输入菜单、键盘↔菜单、反向切换 | 未采 | 未采/未采 | 未采/未采/未采 | 异高IME/无IME可触发额外余量收尾阶段；观感待录 | 面板Size/Fade/8px移动同controller，固定内容高度；余量收尾仍复用controller。测普通、交换和中途反向，确认是否有布局峰值或多阶段停顿，再由Hark定处理。[E7] |
| P2 待测图片 | M05 动作库网格滚动/筛选 | 未采 | 未采/未采 | 未采/未采/未采 | 首图出现/快速滚动闪烁未测 | 正式入口为SDK GridView.builder，包内219张640×640 standing，无按显示尺寸decode hint。W=390夹具图区149逻辑像素，须对实际W×DPR核算；不能仅凭无cacheWidth判卡顿。冷/热滚分测，若解码热点成立才评估hint/已有小图。[E8] |
| P2 待测媒体 | M07a 训练视频首帧：整套与单动作分别测 | 未采 | 未采/未采 | 未采/未采/未采 | 有native首帧守卫和现有封面淡出；冷等待/闪屏未测 | 站位保留至prepare ready、native first-frame和一轮composition；Texture+GPU alpha shader，无逐帧CPU readback。SDK有媒体预取，App legacy prefetch在正式模式不生效；拆文件准备、codec、shader、首帧等待。[E9] |
| P2 待测媒体/保存 | M07b 训练完成页进入及返回聊天 | 未采 | 未采/未采 | 未采/未采/未采 | session body直接换为结果页，但结果页有独立庆祝；是否生硬/掉帧未测 | 完成明细全量Column，退出预取/计时并保存；按钮等保存成功可点。分别量完成首帧、明细布局和保存等待，不能把按钮暂禁用直接当掉帧。[E9] |
| P3 已有普通转场 | M06b 训练图文详情页进出 | 未采 | 未采/未采 | 未采/未采/未采 | 有普通页面转场；预览媒体出现待录 | MaterialPageRoute走现有主题平移/遮暗，媒体按可见项激活。测页面layout与首个预览，不把它当zero训练路由。[E10] |
| P3 已有普通转场 | M06c 我的计划页面进出/条目滚动 | 未采 | 未采/未采 | 未采/未采/未采 | 页面有转场；条目两卡问题见M00 | CustomScrollView+SliverList；56逻辑像素图当前取640 cover，另有192 thumbnail可核对内容。若冷首现为热点再比较已有小图/解码hint；不能在本步换素材或布局。[E8,E10] |
| P3 弹层分测 | M06e 更多菜单、重命名/删除、训练底部反馈层 | 未采 | 未采/未采 | 未采/未采/未采 | 使用现有PopupMenu/showDialog/modal sheet；不全是硬切 | 分开打开/收起、带键盘和取消流程；不要用输入菜单的帧结果替代所有弹层，也不统一改时长。[E10] |
| P3 锚点检查 | M02b 自动滚到底与等待中阅读历史 | 未采 | 未采/未采 | 未采/未采/未采 | 是否强拉/阅读锚点跳动未测 | SDK reverse:true，底为offset0；发送前animateTo0，没有每条回复无条件强滚。分别测停底/等待中上滑/旧卡展开后新回复，复现后再决定近底跟随及锚点策略。[E4] |
| 不适用 | M08t Tab切换 | 不适用 | 不适用 | 不适用 | 当前没有该导航入口 | App与所用SDK lib没有TabBar/PageView/底部Tab导航；当前四项是功能菜单+push路由。采实际入口/返回，不新增Tab或伪造Tab基准。[E10] |

## 取证工具本身的缺口

- **T1 SDK元信息不可据此认包。** `lib/app/build_info.dart:32` 仍是488字符串；`performance_report.dart:82` 尝试写入该值，但包含`/`和`@`，会被 `frame_recorder.dart:365,615` 的安全过滤拒绝。实际锁定与采集包为475。用本次profile-apk.json的源码、指纹、SDK锁、包哈希认包；后续可由构建生成安全的纯SHA字段，不在本轮改代码。
- **T2 路由/子状态标签不覆盖全部场景。** ChatHome给我的计划命名saved_plans，但 `performance_routes.dart:13` 未映射，落入other_route；SDK完成态没有单独push路由，仍可能标training。Popup菜单也可能other_route。不要把这一标签聚合值冒称精确单项，须单项采样文件、明确操作区间，必要时补DevTools时间线。
- **T3 旧十格不是本次全App验收。** 旧工具按刷新周期、120Hz P99 8.33ms等统计，仅五个固定场景；不能覆盖键盘、生成、主题和完成态，更不能直接当>16ms计数。保留rawFrames重新按16000us统计。
- **T4 设置与导出也有帧。** 全部rawFrames包含设置页；旧case只在部分聚合中排除。主题切换本来就在设置，不能一概丢弃settings；其他项需剔除性能页/分享动作，明确边界。

## 源码证据索引

App根目录A：`E:/AII-3D/3D-Sport-AI/Sport-Helper-ui-polish-1`。SDK快照S：`E:/AII-3D/3D-Sport-AI/deliveries/feedback-r1-part1-plus37-r2/pub-cache/git/ugk-3d-pose-sdk-475a5d84b5d0fce839d9d4475da22a6d1ce2df19`。所有结论按此快照，非后续SDK工作树。

- E1：A `lib/ui/chat/saved_plans_page.dart:178,374`；S `packages/ugk_coach_ui/lib/src/plan_expanded.dart:16,88,217,234`。
- E2：A `lib/ui/training_route.dart:3`、`lib/ui/chat/chat_home_page.dart:181,214`。
- E3：A `lib/main.dart:289`、`lib/ui/theme/app_theme.dart:258,272`。
- E4：A `lib/chat/chat_controller.dart:183,509,917`、`lib/data/app_store.dart:246,401`、`lib/ui/chat/chat_home_page.dart:265,291,401`；S `lib/src/llm/openai_compatible_client.dart:39,150,248`、`packages/ugk_coach_ui/lib/src/chat_list.dart:57,127`。
- E5：A `lib/ui/chat/coach_task_bubble.dart:118,326,563,644`、`lib/ui/chat/coach_delivery_transition.dart:27`；S `packages/ugk_coach_ui/lib/src/recommend_card.dart:31,186`。
- E6：S `packages/ugk_coach_ui/lib/src/plan_card.dart:161,749,873,945,1180`。
- E7：A `lib/ui/chat/chat_composer_dock.dart:35,176,232,242,270`、`lib/ui/chat/chat_home_page.dart:289,307,318`。
- E8：S `packages/ugk_trainer/lib/src/pose_hub/pose_hub_action_browser.dart:180,231,311`、`pose_hub_pack_image.dart:7`；A `lib/ui/chat/saved_plans_page.dart:489`、`lib/ui/theme/media_theme.dart:10`、`lib/app/app_test_content.dart:72`。
- E9：S `packages/ugk_trainer/lib/src/pose_hub/pose_hub_pack_media.dart:79,151,196`、`media/packed_alpha_video.dart:115,182,320`、`ui/trainer_player.dart:725,775,1430,2627`、`ui/trainer_completion.dart:44,237,313`；A `lib/ui/player_page.dart:144`。
- E10：A `lib/ui/theme/transitions.dart:13`、`lib/ui/chat/chat_home_page.dart:150,356`、`lib/ui/chat/saved_plans_page.dart:150,285,546`；S `packages/ugk_trainer/lib/src/ui/trainer_player.dart:606,1266,1340`。Tab检索同时覆盖A/lib与S中Trainer/CoachUI的lib。

完整只读分项证据：[对话/生成/计划](../../deliveries/motion-audit-20261029/chat-generation-plan-static-4047072.md)、[媒体/路由/解码](../../deliveries/motion-audit-20261029/media-routes-draft.md)。原始数据回来后补最大值、超标帧数、视频时间点与最终严重度排序；目前没有任何“全App≤16ms”结论。
