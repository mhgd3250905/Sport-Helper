# SmartFit 流畅度静态审核（2026-10-23）

本轮找到可供采样验证的 App 与 SDK 性能候选，尚无数据证明其中任何一项就是开哥手机滑动卡顿的原因。此文档不把静态代码模式判为性能故障，也不据此修改视觉或 SDK。首包应保持业务与视觉原样，只加入内测性能记录器；取得基线后再决定修复范围。

## 审核范围与证据边界

- App：`Sport-Helper-media-cache`，分支 `feat/performance-baseline`，审核起点 `c35068003fe484f793ce051134444ae3b0172c4d`。下列 App 行号针对该审核起点；新增记录器后可能移动。
- SDK：`ugk_coach` 与 `ugk_trainer` 固定依赖 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`（`pubspec.yaml:14–22`）。只读查阅 `E:/DevCaches/pub/git/ugk-3d-pose-sdk-f684e02f38e652633c23fa8946a53d02b6aa3ea2`，未修改 SDK 或 pub 缓存。下表 SDK 路径均相对该 SDK 仓库。
- 覆盖：动作库快速滑动、筛选、动作详情进出、长聊天滑动、计划卡展开、训练切动作、下载/校验中滑动，以及图像、玻璃、动画、重建和 UI isolate 工作。
- 这是静态检查，没有使用 debug、模拟器或真机的帧数据作为结论。所有候选的“实测/修复”均为“未实测 / 未修复”。后续模拟器仅用于同环境相对比较；不能充当真机性能绝对值或开哥验收。

## App 候选清单

| 编号 | 场景 | 原因候选与代码证据 | 文件位置（App 仓库相对路径） | 优先验证方法 | 实测 / 修复 |
| --- | --- | --- | --- | --- | --- |
| A01 | 长聊天滑动；AI 回复进度更新 | 外层虽然是 `ListView.builder`，`_messages()` 先遍历所有消息并构造全部行 Widget，再反转成列表；`itemBuilder` 只是索引现成 Widget。`findChildIndexCallback` 每次线性搜索行。在长会话遇到通知时可能增加 UI 构建时间；并非所有离屏 RenderObject 都已布局。 | `lib/ui/chat/chat_home_page.dart:293–382`、`:383–385` | 不同消息数下录制“静止 / 滑动 / AI 回复中滑动”，看 UI 时长和 Rebuild。冷启动只恢复最多 60 条，但当前会话内 `messages` 仍可增长。 | 未实测 / 未修复 |
| A02 | 长聊天与 AI 进度；计划卡重新出现 | `_chat` 的 `ListenableBuilder` 包住消息列表、玻璃背景来源、建议条及输入栏。控制器每次 Agent 进度事件都会 `notifyListeners()`。`ValidatedPlanCard.build()` 还会以 `toJson()` → App `fromJson()` 转换计划。候选是通知导致的重建范围，而不是已经发现逐 token 重建；当前 SDK 事件是 thinking/reading/checking 等步骤进度。 | `lib/ui/chat/chat_home_page.dart:230–275`；`lib/chat/chat_controller.dart:52–80`；`lib/ui/chat/validated_plan_card.dart:32–35` | Rebuild 统计中检查更新进度时旧消息、卡片与输入是否一起 build；Timeline 看转换是否可见。 | 未实测 / 未修复 |
| A03 | 动作库快速滑动；聊天动作卡；计划列表与已保存计划 | 封面 `Image.asset` 没有 `cacheWidth/cacheHeight`。60/64 逻辑像素缩略图仍调用 `sfPoster`，没有使用已打包的 `common-lossy/thumbs`。若源图像素明显大于显示尺寸，可能增加解码/缓存与上传成本；尚未用图像像素尺寸和 Timeline 量化。 | `lib/ui/library_page.dart:240–244`；`lib/ui/chat/action_card.dart:48–54`；`lib/ui/plan_page.dart:335–343`；`lib/ui/chat/saved_plans_drawer.dart:230`；`lib/ui/custom_plan_page.dart:300`；`lib/ui/theme/media_theme.dart:11–12` | 同样列表路径对比冷缓存/热缓存，检查 image decode、Raster、内存。若确认才按布局尺寸 × DPR 选择解码尺寸，并验证清晰度。 | 未实测 / 未修复 |
| A04 | 长聊天首次出现计划卡；首次展开 | 每张计划卡首次挂载，在 `didChangeDependencies` 中遍历计划所有动作并对原始 `AssetImage` 执行 `precacheImage`。这已减少展开过程中解码的机会，但多张卡连续入屏时可能把解码工作前移到滚动阶段。 | `lib/ui/chat/plan_card.dart:368–385` | 记录卡片进入 viewport 与第一次展开的独立窗口；看解码峰值是否和卡片挂载重合。 | 未实测 / 未修复 |
| A05 | 长聊天滑动；筛选 chips；计划卡展开 | App 将玻璃放在建议 chips、输入栏、计划卡和公共控件。`SfGlassSurface` 创建 `GlassContainer(useOwnLayer: true)`；聊天使用 `GlassBackgroundSource` 捕获包括滚动消息的背景。滤镜/折射的真实成本依赖设备后端、区域和自适应质量，静态代码不能证明它导致卡顿。 | `lib/ui/theme/glass.dart:133–147`；`lib/ui/chat/chat_home_page.dart:230–245`；`lib/ui/chat/chat_widgets.dart:486`、`:565–567`；`lib/ui/chat/plan_card.dart:884–888` | 比较 UI 与 Raster；同时记下浅/深主题、自适应玻璃质量、星尘开关。若需要固定底色实验，先做内测开关，并提供同场景开/关截图供开哥选。 | 未实测 / 未修复 |
| A06 | 计划卡展开；进入训练转场 | 展开编排包含多个动态 `Opacity`、clip、flyer、玻璃表面；训练转场同时淡入页面和背景。非整数透明度可能产生合成成本，但 Flutter 是否产生离屏层必须看实际 layer tree/Timeline。`Opacity` 本身不是已确认的 `saveLayer` 事件。 | `lib/ui/chat/plan_card.dart:654–690`、`:755–775`、`:948–975`；`lib/ui/chat/expand_route.dart:113–152` | 记录首次与第二次展开/收起、进入/退出训练，并观察 Raster、离屏层与 shader 事件。保持同动作数、同主题与相同动画设置。 | 未实测 / 未修复 |
| A07 | 浅色动作库快速滑动 | 每个封面使用 `SfColors.cardShadow`；浅色有 blurRadius 24 与第二层小阴影，深色没有阴影。候选仅涉及浅色 Raster；不能把现有阴影直接删除。 | `lib/ui/library_page.dart:229–235`；`lib/ui/theme/tokens.dart:205–212` | 同设备同数据的深/浅主题分别采样，排除图片冷热缓存差异。如确认需外观变化，按开关和截图流程处理。 | 未实测 / 未修复 |
| A08 | 下载和校验同时滑动 | `TrainingMediaLog` 订阅仓库所有通知，每次 `_changed()` 都遍历所有 manifest 动作及包以比较 phase。虽然日志只在阶段变化或每 30 秒汇总进度时写出，扫描仍跟随 SDK 的 chunk 级通知频率。候选是目录规模 × 通知频率造成的 UI isolate 负担。 | `lib/diagnostics/training_media_log.dart:27–29`、`:35–91`；关联 SDK S02 | 下载期间看 Timeline 中此 listener 时间与通知频率；同时记录 RuntimeLog 是否开启。帧记录器禁止复用这个逐事件落盘通道。 | 未实测 / 未修复 |
| A09 | 长聊天发送/回复后滑动；设置变化；保存训练 | `ChatController._persist()` 先遍历当前所有消息做 `toJson()`，`AppStore` 再同步 `jsonEncode` 全部本地状态后异步写 SharedPreferences。持久化聊天会截到 60 条、history 到 30 条，但 `savedPlans` 和 session 集合也在序列化范围；`async` 不会自动把 JSON 运算移到其他 isolate。 | `lib/chat/chat_controller.dart:628–632`；`lib/data/app_store.dart:182–210`、`:359–367`；`lib/core/storage/local_state_storage.dart:26–28` | 用相同消息数、保存计划数与训练记录规模，记录发送/保存紧接滑动的 UI 峰值；不要仅看到 `jsonEncode` 就进行重构。 | 未实测 / 未修复 |
| A10 | 计划生成与滑动同时发生 | 模板生成方法返回 Future，但方法内部描述匹配、模板排名、动作过滤/排序主要同步执行。当前目录规模可能足够小，尚无证据显示超预算。 | `lib/domain/plan_generator.dart:78–105`、`:118–175`、`:231–266`；`lib/ui/custom_plan_page.dart:39–69` | 给生成阶段加短期 Timeline 任务，并在离线回退模板场景记录 UI；只有测得显著工作才评估 isolate。 | 未实测 / 未修复 |
| A11 | 筛选切换；计划详情选择动作 | 动作库筛选会重新过滤完整动作目录并切换带不同 key 的网格，动画过渡期间可能同时绘制新旧网格。计划详情为 `ListView(children: ...)` 并在选择动作时 `setState`，会重新构建该页和全部计划行；通常动作数有限，需要先测。 | `lib/ui/library_page.dart:24–27`、`:66–78`、`:86–115`；`lib/ui/plan_page.dart:154`、`:250–275`、`:315` | 筛选连续切换测 UI/Raster；计划详情使用实际最大计划长度测 Rebuild。筛选栏本身只有固定少量类别，不应机械改成 builder。 | 未实测 / 未修复 |
| A12 | 计划详情上下滑动；详情进出；训练动作切换 | 计划详情只创建一个预览，进入训练前关闭它；但预览在自身 ListView 滚出可见区时没有 viewport 可见性信号，`ExerciseVideo` 默认 `playing: true`。SDK 同样没有滚动可见性观察，故可能继续播放离屏预览。动作详情关闭会 dispose；是否确有离屏耗电/帧竞争应实测。 | `lib/ui/plan_page.dart:142–149`、`:170–175`；`lib/ui/exercise_video.dart:12–15`、`:70–87`；关联 SDK S03 | 滚到预览完全离屏，观察视频活动/CPU、平台视图与帧时长；反复开关详情看资源数是否回落。 | 未实测 / 未修复 |
| A13 | 首次动画与首次进入页面 | App 先 `LiquidGlassWidgets.initialize()`，并开启自适应质量，但审核未找到 Android `EnableImpeller` 或 iOS 显式 Impeller 配置。缺少显式配置不能推断 Impeller 关闭；应以 engine 启动日志、设备 API/图形能力和实际运行后端确认。 | `lib/main.dart:74–76`、`:128–136`；`android/app/src/main/AndroidManifest.xml`；`ios/Runner/Info.plist` | 分别记录实际后端、首帧冷启动/热运行与同设备 Impeller 开关对比。切换需要重启；不能在同轮混合统计。 | 未实测 / 未修复 |
| A14 | 含多个自绘图标的列表/控件 | `SfIcon` 的 painter 确实调用 `canvas.saveLayer`，但明确约束为图标坐标中的 28 × 28 区域，用于 `dstOut` 挖空，不是整屏离屏层。应记录其存在，暂低优先级，不能只凭关键词删除而破坏图标。 | `lib/ui/theme/sf_icons.dart:151–160` | 若 Raster trace 显示大量此类小图层才进一步归因；保留绘制正确性。 | 未实测 / 未修复 |

## SDK 候选与交给 SDK 的调查项

以下是“待实测定位的 SDK 责任范围”，不是已确认需要修改 SDK 的缺陷。本次不修改 SDK，也不通过 dependency override 或本地缓存修改绕过边界。

| 编号 | 场景 | 原因候选与证据 | 文件位置（SDK 仓库相对路径） | 可向 SDK 提供的验证证据 | 实测 / 修复 |
| --- | --- | --- | --- | --- | --- |
| S01 | 下载完成校验；冷缓存命中检查；清单加载期间滑动 | native 缓存通过 `sha256.bind(file.openRead()).first` 校验，IO 是异步流，但 Dart 哈希 chunk 运算仍在当前调用 isolate，代码未见 isolate 调度。子清单还同步 `sha256.convert`、UTF-8 与 `jsonDecode`。每次 `_available` 会进 `cached()`，因此反复进入已下载动作可能重新读完整文件校验。不能把它描述为同步文件 IO。 | `packages/ugk_trainer/lib/src/media/training_media_storage_native.dart:36–41`、`:98–101`；`packages/ugk_trainer/lib/src/media/training_media_repository.dart:319–329`、`:384–390`；`packages/ugk_trainer/lib/src/media/training_media_models.dart:89` | 标记视频 ensure 开始/完成；Timeline 关联 hash/JSON CPU 时间、文件大小及 UI 峰值。SDK 可在确认后评估后台校验与可信缓存策略，完整性校验不能省略。 | 未实测 / 未修复 |
| S02 | 素材下载过程中滑动/播放 | 每个 HTTP chunk 写入并 `flush()` 后回调 `onProgress`；仓库 `_set` 随即 `notifyListeners`，没有节流/去重。每个 `DrillMediaView._repositoryChanged()` 会检查 action eligibility 后 `setState`，不只监听自己的资源。App 设置的下载面板也监听整个仓库。 | `packages/ugk_trainer/lib/src/media/training_media_storage_native.dart:85–94`；`packages/ugk_trainer/lib/src/media/training_media_repository.dart:255–263`、`:467–474`；`packages/ugk_trainer/lib/src/media/drill_media_view.dart:158–191`；App 对应 `lib/ui/training_media_settings.dart:144–160` | 记录 chunk 频率、通知数、媒体面板/当前视频的 Rebuild 次数，以及滑动时 UI 峰值。若确认由 SDK 节流或按资源细分通知另行修复。 | 未实测 / 未修复 |
| S03 | 视频切换；预览离屏；详情反复进出 | 每次动作 id/playing 改变 `_reload` 会停旧 controller 后确保新视频；native view 新建本地 server 与 WebView。dispose 有明确 dispose 命令、解绑和关 server。静态未发现泄漏证据，但没有 viewport/route 可见性处理；播放器重建与平台视图启动可能形成动作切换峰值。 | `packages/ugk_trainer/lib/src/media/drill_media_view.dart:96–133`、`:194–215`；`packages/ugk_trainer/lib/src/media/media_view_native.dart:67–85`、`:129–148`、`:175–187` | 对比第一次/再次进入同动作，记录 WebView/server 数、退出后资源回落、首视频帧时间与 Flutter 帧。注意 Flutter FrameTiming 不包含 WebView/视频自身所有解码与合成耗时。 | 未实测 / 未修复 |
| S04 | 视频加载前封面、训练动作切换 | SDK 中 `DrillMediaView` 的占位 `Image.asset` 未指定解码尺寸。应和 App 缩略图候选分开归属。 | `packages/ugk_trainer/lib/src/media/drill_media_view.dart:237–241` | 确认封面像素/显示像素、首次加载的 decode 与 Raster 峰值；SDK 单独评估公共参数或布局内解码策略。 | 未实测 / 未修复 |
| S05 | AI 请求/计划验证同时滑动 | SDK Agent 构建上下文、估算 token、工具参数校验和 LLM 请求/响应使用当前 isolate 上的 JSON 编解码。流程较复杂，但没有 CPU 测量，不能据此断言 AI SDK 是卡顿源。SDK 不负责 App 的整聊天重建范围（A02）。 | `lib/src/agent/coach_agent.dart:584–592`、`:1192–1236`；`lib/src/llm/openai_compatible_client.dart:59` | 为 Agent 阶段/工具校验关联 Timeline 与输入上下文规模；只有确有明显 CPU 峰值再移交 SDK。 | 未实测 / 未修复 |

## 当前已经做对的措施

1. 动作库使用 `GridView.builder`，没有 `shrinkWrap` 嵌套长列表（`lib/ui/library_page.dart:99–115`）。聊天也使用 builder，已保存计划使用 `SliverList.separated`；A01 是 Widget 准备工作没有完全按需，不能称其完全没有懒布局（`lib/ui/chat/chat_home_page.dart:372–387`、`lib/ui/chat/saved_plans_drawer.dart:84`）。本轮 `lib` 搜索未找到 `shrinkWrap`。
2. 动作库和动作卡使用封面，不在列表中创建每格视频播放器（`lib/ui/library_page.dart:240`、`lib/ui/chat/action_card.dart:48`）。计划页只有一个选择动作预览，并在进入训练前 `playing: false` 释放预览（`lib/ui/plan_page.dart:143–149`、`:171–175`）。
3. 视频走 SDK `DrillMediaView`，SDK 切换动作先停旧 controller，dispose 解绑仓库和 controller，native view 发送 dispose 并关闭本地 server。当前 App `lib/core/media/*` 是遗留实现，生产 `ExerciseVideo` 引用 `package:ugk_trainer`；不要把遗留文件当运行路径修复（`lib/ui/exercise_video.dart:2`、`:70`）。
4. 训练 SDK 虽以默认 50 ms Timer 轮询，但 `_shownKey/_shownGen` 门控 `setState`，并非每 50 ms 整页重建；进度另走 `_progress`。动作变化/计数变化时的实际 rebuild 成本仍可测（SDK `packages/ugk_trainer/lib/src/ui/trainer_player.dart:392`、`:428–447`）。App 外层训练背景明确 `animate: false`（`lib/ui/player_page.dart:71–72`）。
5. 重聊天消息、计划卡主体、flyer、静态背景色场已有 `RepaintBoundary`；动画多处将静态子树放在 `AnimatedBuilder.child`（`lib/ui/chat/chat_home_page.dart:346`；`lib/ui/chat/plan_card.dart:647`、`:703`、`:817–830`；`lib/ui/theme/glass.dart:237–280`）。不能仅因重卡片就机械再包边界。
6. 星尘只在独立 CustomPainter 上刷新，约 30 Hz；后台和减少动画会停 ticker，页面覆盖时 Flutter ticker 受 TickerMode 管理（`lib/ui/chat/cosmos.dart:26–98`）。设置已有星尘开关（`lib/ui/about_page.dart:51–56`）。
7. `SfGlassField` 由静态渐变绘制，没有 blur 或 ticker（`lib/ui/theme/glass.dart:206–210`）。真实玻璃集中在 `SfGlassSurface`，有质量策略和自适应质量；首帧前预热库 shader（`lib/main.dart:74–76`、`:128–136`）。自适应质量变化会影响可比性，报告必须记录测试条件。
8. 当前 Pose-Hub 媒体不会进入旧的动态 cutout 路径：`SfCutouts.has` 排除 `source.startsWith('Pose-Hub ')`（`lib/ui/theme/media_theme.dart:36–39`），构建资产工具也注明 `cutoutsBundled: False`（`tools/media/build_on_demand_assets.py:287`）。不能把旧的动画 WebP 代码当作本版实际并行播放证据。
9. SDK 下载采用流式文件写入、校验后 rename，限制并发为 3，按 hash 去重下载任务（SDK `packages/ugk_trainer/lib/src/media/training_media_storage_native.dart:85–105`；`packages/ugk_trainer/lib/src/media/training_media_repository.dart:424–439`、`:451`、`:482–487`）。这是异步 IO，不是 `readAsBytesSync` 式阻塞；哈希 CPU 与通知成本仍见 S01/S02。
10. App 日志对媒体字节进度只每 30 秒采样；现有 RuntimeLog 有容量上限和串行合并写入（`lib/diagnostics/training_media_log.dart:29`；`lib/diagnostics/runtime_log.dart:199–212`、`:227–239`）。但该日志通道每个事件仍触发 flush，并不适合承接每帧数据。

启动目录解析另行观察：`PackSet.load`、App manifest/模板和 Coach profile JSON 都在 `runApp` 之前加载（`lib/main.dart:77–92`、`:124`；`lib/app/services.dart:249–291`；`lib/packs/drill_pack.dart:192–205`）。这些同步解析可能影响冷启动，但不能直接据此解释已进入页面后的滑动。审核起点的 App manifest 为 104,979 字节，realistic-dark 子清单为 22,981 字节；不能把它们未经测量描述为“大 JSON 卡顿”。

## 记录器场景标签的 App 接入位置建议

优先通过 App 页面生命周期/路由、已有 onTap 与已有 mediaBuilder 回调标记，不改 SDK。页面基底和短交互标签要分层；交互结束后回到当前页面基底，路由弹出恢复上一页。不要把每次 build 都当成新场景或清空统计。

| 标签建议 | App 公开接入点 | 结束/恢复规则 |
| --- | --- | --- |
| `chat` / `chat_scroll` | `ChatHomePage` route 可见性；`_messages()` 内 ListView 外监听 `ScrollNotification`（`lib/ui/chat/chat_home_page.dart:369–387`） | `ScrollEndNotification` 恢复 chat；进入其他页面时 route 栈恢复规则生效。 |
| `library` / `library_scroll` | `LibraryPage` 生命周期/路由；`_grid` 的 builder 网格外监听滚动（`lib/ui/library_page.dart:86–115`） | 结束滚动回 library。只给命名固定枚举，不把动作名/用户消息作为 key。 |
| `library_filter` | 类别 chip 的 `onTap`（`lib/ui/library_page.dart:49`、`:59`），覆盖 AnimatedSwitcher 过渡 | 以转场结束或固定、明确的过渡窗口结束，回 library；快速连续点击要延长同一窗口，不能短窗口相互错误覆盖。 |
| `exercise_details` / `exercise_details_transition` | `showExerciseDetails` Future 外层与 bottom sheet builder（`lib/ui/library_page.dart:123–178`） | 覆盖入场和退场；Future 完成恢复原页面。详情自身可滚动，可分 `exercise_details_scroll`。 |
| `plan_expand` | `PlanCard._toggle()` 和 `_onStatus(AnimationStatus)`（`lib/ui/chat/plan_card.dart:363–365`、`:394–405`） | 动画 completed/dismissed 时结束交互标签，恢复 chat；不要修改动画或图片预热行为。 |
| `plan_details` / `plan_details_scroll` | `PlanPage` 生命周期和 body（`lib/ui/plan_page.dart:154`） | 路由 pop 恢复 chat，预览仍按原行为播放，首包不顺便“优化”。 |
| `training` / `training_action_switch` | `PlayerPage` 生命周期；现有 `TrainerPlayer.mediaBuilder` 中比较 `request.drill.id`（`lib/ui/player_page.dart:118–130`） | 仅 id 变化时标短转换窗口；普通计时 rebuild 不重复打点。route 关闭恢复前页。此点可观察当前视频动作，不能完整观察 SDK 内所有 prep/rest/phase；报告应注明该边界。 |
| `settings` | `AboutPage` route（`lib/ui/about_page.dart:16–33`） | 由路由栈恢复；导出自身不计入任何业务场景的对比。 |
| `media_download`（并行上下文） | 通过 App 对 `TrainingMediaRepository` 的只读 listener 或原 `TrainingMediaSettings._download` 开始/结束回调（`lib/ui/training_media_settings.dart:37–93`） | 下载会跨路由持续，不能仅因设置页 dispose 就标结束。作为并行上下文与 `library_scroll`/`chat_scroll` 组合保留，避免覆盖真实页面。 |
| `media_verification` | SDK 目前没有公开独立校验 phase；App 可以标 `ensureVideo`/package 下载总窗口，无法精确拆分校验 | 首包导出须明确“下载窗口包含校验，暂无独立校验边界”；后续 DevTools 或 SDK 另行加 Timeline 标记才能精确归因。不得通过改 SDK 来补这个标签。 |

## 帧数据与验收记录

本次静态审核不填写模拟帧数据，也不把普通测试通过写成性能通过。以下七个场景均等待相同条件的基线与修复后报告：动作库快速滑动、筛选切换、动作详情进出、长聊天滑动、计划卡展开、训练切动作、下载/校验中滑动。

每个报告应分别保留 UI build 与 Raster 的平均、P90、P99、最差耗时和超预算帧数，并给出帧样本数、采样窗口、设备型号、系统版本、刷新率、App/构建版本、实际图形后端、主题、星尘开关、玻璃质量和资料规模。掉帧定义应固定为当前刷新周期的超预算帧，说明是“超预算帧数”还是“估算错过的 vsync 数”；两者不能混称。UI/Raster 是流水线两个阶段，不能直接相加认作每帧显示时长。

内测帧记录器只在内存累加有界统计，在用户导出时才生成 JSON 和分享文件；不要每帧通知页面或写 RuntimeLog。分组与百分位计算方式需在报告 schema 说明（若采用有界直方图，注明精度）。生产版应以编译条件排除记录器与导出入口。

取得 baseline 后，按 UI 与 Raster 峰值挑选上述候选做最小修复，保留同场景原始报告；SDK 项独立交给 SDK。外观变化要先提供开关、同场景开/关截图，再由开哥选择。通过现有测试与内测体验后，仍需开哥明确同意才合入 main 并推送。
