# +48 卡片展开式训练过渡：原因核查与 SDK 接口交接

日期：2026-10-30。分支 `codex/trainer-transition`；本轮开始时 HEAD 为 `8495fb2e45a576ce5aeb45543acfbc8e269b5d75`，运行代码仍是 `c0a0fc0bf26a4955cc1bfe4e7f943e1a487594db`，其后只有文档收束，未回退工作树。版本保持 `0.1.0+48`，三包及 override 仍锁 `652135f532bac1a06fbf133dc497692d6b44c78a`。

**结论：SDK 652 缺少延迟启动、分块包装及结束展示阶段的公开接口，当前不能按新设计完成 App 接线。按用户“没有口子先回报，不要用遮罩绕过”的指令，本轮只交原因与接口报告，不修改运行代码、不改 SDK、不重新包装旧界面冒充新版。main、release/1.0 保持原状。**

## c0a0fc0 的确定原因与尚待真机确认项

### 进入：控件为什么同帧硬出现

[PlayerPage](E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition/lib/ui/player_page.dart:88) 在真实路由 completed 前只挂 `TrainingEntryPlaceholder`，之后才整棵挂载 `TrainerPlayer`。SDK training 模式会在 initState 启动计时/语音，旧实现用整棵延迟挂载避开它，但也使顶部卡、提示卡和控制区同帧出现，没有任何逐块入场。首图矩形一致的测试不能证明这些控件的视觉进场合格。

受控 widget 样本中，旧进入全页透明度在 66.667ms 已为 0.6735、100ms 为 0.8365、200ms 为 0.9961，而真实控件仍等到 320ms completed 才挂载。因此“先快速显出空舞台，随后全部出现”是旧设计的确定结果；并不是原生视频缓冲造成的控件延迟。

### 退出：保存等待、reverse 与首图切换

SDK [确认关闭](E:/AII-3D/3D-Pose-SDK/packages/ugk_trainer/lib/src/ui/trainer_player.dart:1364) 后冻结当前阶段，立即结束引擎并触发保存；[_close](E:/AII-3D/3D-Pose-SDK/packages/ugk_trainer/lib/src/ui/trainer_player.dart:1434) 等保存及 receipt 成功才普通 `Navigator.pop`。400ms 才出现小转圈，所以保存若约 230ms，会有一段完全静止且没有等待指示的时间；该时间在 reverse **开始前**。未取得那次存储时间戳，不能把录屏的 230ms 宣称为已量出的存储耗时。

普通关闭和系统返回都走 `_close`；自然完成的“完成”也使用普通 pop。未发现正常成功路径用 removeRoute、popUntil 或替换路由绕过 reverse。软件复验中，正常 260ms reverse 确实存在：130ms 时页面仍在 reverse、opacity=0.854741、dy=0.00871553；261ms 已移除。390×844 的样本中，前 100ms 只下移约 4.16px，透明度仍为 0.91788，明显变化集中在后段，容易呈现“静止后突然消失”的观感。

SDK 的 [TickerMode(false)](E:/AII-3D/3D-Pose-SDK/packages/ugk_trainer/lib/src/ui/trainer_player.dart:1512) 只包训练子树；Flutter 路由 controller 的 vsync 是 Navigator，位于其祖先，不会被这个子树开关停掉。不能把外层 reverse 不明显归因于该 TickerMode。

另一个确定的换帧点是 [mediaBuilder](E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition/lib/ui/player_page.dart:180)：reverse 第一次 build 将暂停视频换成 `ExerciseFrameZero`，而非保留任意暂停视频帧。当前动作海报与当时姿态可能不同；没有该段真实录屏文件，不能量出其视觉跳变幅度。

关闭确认框还有独立的 150ms DialogRoute 退场。SDK 等的是 dialog 的 popped future，没有等 dialog.completed，因此快保存时弹窗退场和训练 route reverse 可以重叠。新版应明确“确认框完全退出后”的展示事件，而不是让宿主猜测弹窗何时消失。

### 减动效确有两层判断，不能只看声明的 260ms

| 受控条件 | 软件复现结果 |
| --- | --- |
| MediaQuery=false、平台 flag=false | 320ms 进入、260ms reverse，未跳过 |
| MediaQuery=true | 构造时两时长都为 0，buildTransitions 直接返回 child |
| MediaQuery 强制 false，但平台 disableAnimations=true | 声明仍为 320/260；Flutter 默认 AnimationBehavior.normal 再乘 0.05，实际约 16/13ms |
| 进入时 MediaQuery=false，退出时变 true | controller 仍跑 260ms reverse，但 Fade/Slide 包装被直接移除，末尾直接移除整页 |

后两条是**可复现条件，不是对用户手机状态的认定**。当前 App 未发现主动覆写这两个值以制造该分歧；缺少那次真实 flags、route 起止时间和 FrameTiming，不能断言手机命中了其中哪一条，也不能用声明时长排除缩时。正常分支的弱位移/尾段淡出，与真正被减动效跳过或缩短，必须区分。

后续宿主动效应统一选择 normal 与 reduced 的时间线。按本次 reduced=150ms 的要求自行处理后，有限动效 controller 应避免再被平台默认缩至 5%，并记录两层 flag、选定时长、实际起止与中断原因以便核验。

### 列表跳动：插入摘要改变了布局占高，不是第二次主动滚动

[聊天返回](E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition/lib/ui/chat/chat_home_page.dart:222) 已等待 `route.completed` 才调用 `finished`。但 [ChatController.finished](E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition/lib/chat/chat_controller.dart:854) 会立即追加摘要、刷新 suggestions 并 notify；SDK [CoachChatList](E:/AII-3D/3D-Pose-SDK/packages/ugk_coach_ui/lib/src/chat_list.dart:120) 是 reverse 列表，新 row 立即占满布局高度。[CoachAppear](E:/AII-3D/3D-Pose-SDK/packages/ugk_coach_ui/lib/src/primitives.dart:348) 只改绘制 opacity/transform，不动画布局占高。

实际 ChatHome 的受控 390×844、1× 样本已复现：offset=0 与 offset=100 两种情况下，插入 finished 后第一帧，原可见消息锚点都立即上移 **81 逻辑像素**，ScrollController.offset 完全没变；随后 0–360ms 位置不再变化。故只“保留 scroll offset”不能保住可见内容锚点，新增消息占高本身就会移动旧行。

返回路径没有一个固定 130ms 的 jumpTo/animateTo 定时器。对话会在训练页淡出时先被露出，overlay 真正结束后才插入摘要，再发生上述布局变化；这解释了两次视觉变化的顺序，但该次录屏的 130ms 实值仍需原始时间戳核对。新版应在 route 结束前保留离开时的可见锚点，之后用同一次布局补偿及明确的 300ms easeOutCubic 滚动，不能插入一条已占满高度的新 row 后再补一个可见跳转。

## 必需 SDK 接口（名称草案，652 中尚不存在）

### ugk_trainer：三个公开扩展点

```dart
TrainerPlayer(
  autoStart: false,                  // 新增，默认 true 保持旧宿主行为
  controller: TrainerPlayerController(),
  partBuilder: (context, part, child) => /* host Transform + Opacity */,
  onExitRequested: (request) async => /* await controls exit, not save again */,
  // onFinished / onCompleted 保留原数据保存职责
);

controller.start();                 // 幂等，真正开始计时与语音
controller.cancelBeforeStart();     // 未开始即取消，不产生零秒训练记录
```

1. **autoStart/controller**：提前布置真实训练 UI，但时钟、语音、recorder 的开始时点和默认视频解码均等实际 start。现有 preview 不是此接口：它是另一种 UI/流程，`onStartTraining` 只是 SDK 内按钮通知，didUpdateWidget 也不把 preview 切成 training。下载预取可以与 UI 开始分开，不将网络预取误列为“视频纹理”。
2. **partBuilder**：SDK 创建、定位并拥有真实控件 child，宿主只包装。part 至少区分 `topProgress`、`nextUp`、`discomfort`、`cue`、`counterAndNavigation`、`pauseButton`；pause 不应再被 transport 父层重复位移/淡化。问题标记由 App 自行同批进场。需要时应同时提供完成页相关 part，不能要求宿主复制 SDK 完成页。
3. **onExitRequested 展示门禁**：明确区分 `earlyExitConfirmed` 与 `completionFinishTapped`。早退在确认框完全退场后发出一次；自然完成在点“完成”时发出，而不是训练逻辑刚练完时。SDK 冻结数据与输入，但保留真实展示树，保存和宿主控件退场 future 同时进行；保存成功且 UI gate 完成后，复用原 `onCompleted` receipt 门禁，再普通 pop 启动舞台缩回。失败保留 SDK 重试、同一 session ID 和一次保存结果；400ms 等待指示仍由 SDK 持有。无需重复增加同义 beforePop。

这些接口要有 owner/generation 与取消合同：重复 start/退出、进入中返回、后台、replay、换计划和迟到 future 不得启动第二轮；终态必须释放 UI gate。可附加 SDK 真正能等待的 `disposalComplete`，但不能把没有 native 回执的资源误报为已物理释放。

实际 stage rect 和当前海报可先通过现有 `mediaBuilder` 内宿主自己的 key、`request.drill`、主题与镜像信息测量/保留。专用 `onStageLayout(TrainerStageSnapshot)` 属于可选便利，不作为必需新接口；不再复制私有 stage 几何公式。

### ugk_coach_ui：两个小补口

4. **稳定的计划英雄媒体语义**：现有 `CoachUiBuilders.media` 已允许宿主合法包装/测量图片；但 `CoachMediaRequest` 没有用途，hero、thumbnail、flyer 都经同一 builder。建议加 `CoachMediaRole.planHero`（或专用 hero builder），让 App 只对该图注册 key、隐藏原图和计算锚点，不猜 SDK 私有树或 asset/尺寸。每张卡的消息 ID 可由 App 局部闭包持有，无需 SDK 增加全局 owner 控制器。
5. **逐条关闭/覆盖默认入场**：最小新增 `CoachChatEntry.appear = false`（默认沿用旧动效），或等价 motion override。现有列表会强制包装 CoachAppear；再套 App 的 12px/240ms 会叠加旧 rise10/360ms/scale0.98，数值错误。`initiallySeen` 仅 State 初始化拷贝一次，不能当作后续逐条 opt-out。补口后 App 可使用已公开 CoachAppear 或自己的小块 Transform/Opacity，仅控制 finished。

ScrollController 已由宿主拥有，300ms 滚动、offset/可见锚点保留、目标不可见兜底都可在 App 做，不要求 SDK 重写列表或接管滚动。整卡 origin getter 也早已公开：当前 App 的 onStart 回调丢弃了它，且它不是图片区域。接入时应在点击当刻先取定媒体 Rect，再做异步 started/precache/push；回退目标必须重测并校验可见/已删除，不能沿用旧位置。

图文入口也有明确的 App 接线工作：聊天打开详情时设置了 `returnPlanOnStart:true`，当前 [PlanPage._startTraining](E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition/lib/ui/plan_page.dart:191) 先 pop 图文页，再由 ChatHome._details/_start 打开训练。这会先销毁新设计要求保留的图文媒体锚点，并可能与新训练 push 发生过渡重叠。新版必须保留该来源 route，由图文上下文 push/返回，完成摘要另行通知聊天 owner；不能继续先 pop 来源页再伪造一个锚点。这属于宿主修正，不是 SDK 缺口。

## 数值冲突：未擅自修改

| 进入控件 | 开始 | 时长 | 完成 |
| --- | ---: | ---: | ---: |
| 顶部卡 | 280ms | 220ms | 500ms |
| 胶囊 | 320ms | 220ms | 540ms |
| 提示卡 | 360ms | 220ms | 580ms |
| 数字/前后按钮/问题标记 | 400ms | 220ms | 620ms |
| 暂停按钮 | 400ms | 260ms | 660ms |

因此全部照做时，控件到 **660ms** 才结束，与“总长 560ms、560ms 开始视频/计时”冲突。若 560ms 挂视频，会与最后 100ms 动画重叠，也违背动画期间无纹理。已单独询问优先级，未自行压缩时长或移动起点。

退出的 250+380=630ms 对应约 19 个 30fps 帧间隔；若“缩到位后”再串行加 120ms 交叉淡化，完整可见序列为 750ms、约 23 帧。应明确“约19帧”是否只指缩回前两段、120ms 尾段是否在路由外继续；当前不擅自叠加、删减或覆盖这段。

## 本轮证据与交付边界

本轮 **20 项只读诊断回归通过**：原路由/训练保存/聊天返回 14 项，以及外部受控诊断 6 项。没有修改 App/SDK/产品测试代码。受控时间与逻辑像素是 widget 仿真，不是手机帧耗时、原生视频或录屏证据。

证据目录：`E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-redesign-audit/`，包含 `diagnose_existing_transition_test.dart`、`diagnostic-r1.log`、`software-observations.json`。上一版 773/773、analyze 0、签名/16KB/JNI 与两份 APK 继续作为 **旧 c0 候选**证据保留，不冒充新设计验证。

新版 UI 尚未实现，没有新的 release/profile APK、进入/退出录屏或真机 UI/Raster 最大帧耗时。先交 SDK 接口合同；SDK 发布可用接口并由用户给定新 pin、同时澄清时序后，再继续本分支。当前 pin 652 不动，不改 SDK、不合 main、不推送、不打 tag。文档提交及源码保护观察见本轮外部 `audit-closeout.json`。
