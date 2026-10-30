# +49 标准水平滑动训练路由（2026-10-30）

本记录取代此前的训练转场方案。基线为3934da7，版本0.1.0+49 / internal arm64 2049；分支codex/trainer-transition。SDK三包及coach override已统一升级至 `66dd98a549c1ff5fedecb626a7c88583090a1440`，公开补充接口已接入动作库及推荐入口。相对3934da7的锁文件仅三包ref/resolved-ref六个值升级，版本约束、标量引号和非SDK依赖保持。已提交的上一份性能候选通过后续提交撤回并替换，不改写Git历史；最初工作树干净，没有未提交改动需要丢弃。

本轮代码已完成5个逻辑入口的统一接入：对话计划卡（收起/展开）、我的计划、图文详情、动作库、推荐。动作库/推荐继续使用SDK预览和开始训练语义，路由与媒体进入宿主统一门禁；不复制SDK UI。候选不合并、不推送main、不打tag；release/1.0与SDK源码不动。本轮固定源码全量 **843/843通过，0失败/跳过；flutter analyze 0问题**。release/profile新包均完成同签名、16KB及JNI验证。真机全程无闪烁、录屏与帧耗时仍待开哥反馈；本次结果取自新回执，不继承旧包。

## 删除内容

删除training_transition.dart、training_entry_placeholder.dart、training_poster_flight.dart与chat/expand_route.dart。TrainingRoute整体替换：移除TrainingTransitionSource、OverlayEntry、Rect插值、圆角动画、整页缩放、独立回程与visualCompleted；PlayerPage不再传chromeAnimation，删除IssueMotion和完成页退场海报层。卡片不再测量/隐藏配图，图文页删除mediaOpacity和origin捕获。SDK计划卡自身展开/收起不受影响。

删除旧trainer_transition_test/training_route_test及旧三份专用转场文档、两份台账，移除主文档旧方案段落。保留finished行初次布局高度0、sessionId去重、240ms完成记录入场与300ms滚动的列表修复；新测试验证标准滑动，不保留旧动画开关。

## 唯一入口与保留状态

宿主只在 `lib/ui/open_training.dart::openTraining` 构造TrainingRoute并push；计划使用plan载荷，SDK单练使用practice载荷。5个逻辑入口共用每个Navigator的一把锁，覆盖预热、会话开始记录、整个训练/预览页、滑出和最终dispose，重复或跨入口点击不push第二次。对话的收起与展开计作同一逻辑入口，均走同一函数。

| 逻辑入口 / sourceEntry | App调用位置与调用链 | 返回保留 |
| --- | --- | --- |
| 对话计划卡：收起/展开 / chat | `lib/ui/chat/chat_home_page.dart::_start`：PlanCard/ValidatedPlanCard → openTraining(chat) | 同一页面与SDK卡片State、展开状态、滚动位置、主题 |
| 我的计划：收起/展开直接播放 / saved_plan | `lib/ui/chat/saved_plans_page.dart::_start`传本页context → `chat_home_page.dart::_start` → openTraining(saved_plan) | 不先pop保存列表；保留列表Element、展开条目、offset |
| 图文详情前往训练 / guide | `lib/ui/plan_page.dart::_startTraining` → openTraining(guide) | 包括对话详情、我的计划详情、自定义计划；文章Element/offset保留，预览可恢复但不自动播放 |
| 动作库单练 / action_library | `lib/ui/posehub_library_page.dart::build`：PoseHubActionBrowser.onOpenPractice → openTraining(action_library, practice) → SinglePracticePage | 原SDK action/theme/startMode及回调载荷；来源浏览器、筛选与滚动状态保留 |
| 推荐动作单练 / recommendation | `lib/ui/chat/chat_home_page.dart`推荐卡onOpenAction → `lib/ui/library_page.dart::showExerciseDetails` → openTraining(recommendation, practice) → SinglePracticePage | 保留推荐来源和SDK preview语义；默认仍由SDK“开始训练”按钮切入训练 |

`LibraryPage`中的旧目录推荐渲染也复用showExerciseDetails；没有SDK动作模型时仍展示原示范底部页，该分支不打开SDK训练页。所有实际SDK训练/单练页面均由上述唯一入口打开。

## 防闪烁实现与回归

下表列出的自动化用例已随本轮固定源码全量通过。软件用例和关键帧不替代手机原生播放、全程无闪烁或帧耗时验收。

| 要求 | 实现 | 对应测试 |
| --- | --- | --- |
| 首帧完整 | SDK TrainerPlayer或原SDK单练UI从第一帧挂载，chromeAnimation不传，全部控件处于该SDK模式的完整状态；转场没有入口占位页、整页Opacity或控件延迟挂载 | training_entry_matrix_test与training_practice_entries_test：5逻辑入口（含对话展开/收起）×浅深，在0/150/300ms核对真实SDK控件、海报像素及无loading |
| 预解码 | 入口可见即预热；屏宽×DPR的ResizeImage与训练海报同键；点击最多等150ms。未完成则不push，保持原页面并提示再次点击，后台预热继续 | 入口矩阵预热/首帧像素；慢解码门禁回归 |
| 背景与系统栏 | opaque=true、allowSnapshotting=false；训练Scaffold/宿主底色一致，AnnotatedRegion按主题同步状态栏/导航栏与图标；不使用MaterialPageRoute默认训练效果 | training_slide_route_test浅深背景/系统栏与位移 |
| 视频接管 | startGate只在300ms路由completed后的完整帧末开放；进入中仅海报。整套计划由PlayerPage承接，动作库/推荐由SinglePracticePage的公共mediaBuilder承接；后者合并调用方startGate与路由门禁，并用宿主canPlay阻止preview提前挂视频。ExerciseVideo/SDK公共媒体与海报保持同位置/裁切/尺寸，真实出帧后才200ms淡出；无视频保持图片 | training_slide_player_test、training_single_practice_test与training_practice_entries_test：门禁、原始载荷、海报像素/尺寸、出帧后揭开；图片模式与无宿主动作模型的SDK公共媒体回落 |
| 立即退出与保存并行 | onExitStarted同帧驱动本Route的controller.reverse，SDK仍保存/ack；beforeExitPop等待同一280ms future。滑出前只暂停现有视频，280ms完成后退役，保存成功后SDK正常pop；正常提前结束不显示完成页 | real SDK浅深×关闭/系统返回、慢保存先滑出、保存一次/receipt一次；自然完成使用同一退场 |
| 失败与迟到pop | 保存失败恢复SDK完整重试页并刷新ModalRoute指针状态。重试按钮只保存；用户完成后再离开。透明静态输入shield阻挡慢保存期间底页另开路由，不绘制任何暗层 | route快慢保存及底页真实点击；player快速失败恢复、retry与完成后仅一条记录 |
| 来源页不动 | 短转场activity缓冲store/chat通知，source保留RepaintBoundary；保存列表缓冲自有listener并停reveal；finished只在route.completed后插入，首帧零高度，随后平滑滚动 | 入口矩阵Element/展开/offset；saved_plans_expand、chat_training_return、app_flow、plan_article回归 |
| 返回与移除动画 | 只有SlideTransition；300ms easeOutCubic进入、280ms物理easeInCubic退出。系统移除动画为0ms；无边缘右滑手势，SDK确认仍适用于系统返回 | route位移逐段断言、zero-duration、进入中返回/后台/移除无残留 |

Flutter反向tween需要reverseCurve=easeInCubic.flipped，使实际右移位移为easeInCubic(elapsed)；用例按实际offset断言，不只比较枚举。精确300/280ms时先核对终点，另推进1μs派发Flutter的completed状态；没有改变规格时长。

当保存比280ms更慢，画面已退出、视频已退役，SDK实例与训练导航锁保留到持久化完成，避免丢记录和迟到pop弹错页。若保存失败，完整重试页滑回；不提前伪造成功。SDK原生视图、计时、语音、记录及确认逻辑仍由SDK管理。

海报、视频覆盖图、透明视频背后的舞台使用同一个 `TrainerMediaRequest.theme.mediaStage`，避免App媒体token与SDK舞台默认值不同导致接管时底色变化。`ExerciseVideo.stageColor`仅由训练适配传入，其它图文/示范仍沿用原主题。保存重试和重练的receipt回调不会触发路由滑出；只有确认退出与最终beforeExitPop驱动退出。

## 内部帧耗时与手机步骤

入口：设置 → 内测工具·正式版不显示 → 训练进出帧耗时。仅internal启用SchedulerBinding.addTimingsCallback与入口；正式flavor关闭。每条记录帧数、build/raster最大值及P90、严格>16ms帧数、入口、主题、源码/SDK、实际后端与首次标记；最多最近10次，异步保存Application Support，复制/系统分享输出同一JSON。分享复用现有FileProvider与Android chooser，由用户选飞书；打开chooser不等于发送成功。

1. 安装本轮profile包，保留数据。系统动画为1×。
2. 对话计划卡（同时检查收起/展开）、我的计划、图文详情、动作库、推荐，分别用浅色/深色，共10组。每组进出3次，覆盖提前结束、自然完成、Android系统返回，并用手机录屏。动作库/推荐先保留SDK preview，再按SDK“开始训练”进入训练以执行结束路径；直接关闭未开始的preview不应写训练记录。
3. **每组3次后立即复制或分享一次**，备注入口/主题，再继续下一组。最近10条会滚动覆盖，不能全部30轮做完才导出。JSON包含chat/saved_plan/guide/action_library/recommendation入口标识，便于分组。未连电脑也可在系统分享面板选择飞书，或把JSON复制回会话。

本机无连接真机；测试/软件截图/APK门禁不能替代手机全程无闪烁验收，不填造帧耗时或设备后端。

## SDK补充已接入与兼容fallback边界

SDK `66dd98a549c1ff5fedecb626a7c88583090a1440` 提供公开 `PoseHubActionBrowser.onOpenPractice`，交给宿主完整配置的PoseHubSinglePracticePage载荷；单练页透传startGate、mediaBuilder、onExitStarted、beforeExitPop。App动作库在 `lib/ui/posehub_library_page.dart` 传入onOpenPractice并调用唯一openTraining；推荐动作在 `lib/ui/library_page.dart::showExerciseDetails` 用同一入口承接公开SDK单练页。

`lib/ui/single_practice_page.dart`只组合公开路由/媒体hooks，保留action、theme、voice、startMode及onFinished/onStartTraining/onCompleted等回调语义，继续渲染SDK PoseHubSinglePracticePage/TrainerPlayer。preview不被宿主改成自动training；其媒体由宿主路由canPlay门禁限制，训练开始与剂量、计时、语音、记录仍由SDK负责。training同时等待原调用方startGate与宿主门禁；preview按SDK语义忽略原gate，但其媒体挂载和预取仍须等宿主路由门禁。没有复制SDK UI、访问私有State或观察pop后偷换路由。

SDK源码保留未传onOpenPractice时的legacy MaterialPageRoute fallback以兼容其它调用者；本候选App的所有PoseHubActionBrowser调用点均传入非空onOpenPractice，SDK `_openPractice`先回调并return，因此该fallback在App训练路径不可达。它仍存在于固定SDK源码，不把它误报为App删除的代码。

对应自动化用例已加入training_practice_entries_test、training_single_practice_test以及相关SDK样式/动作库回归：覆盖SDK preview原始字段和开始按钮、进入门禁、共享导航锁、0/150/300ms完整画面、来源页保留、预览退出不记训练、训练保存/失败重试及无宿主动作模型的公共SDK媒体。这些用例已包含在本轮全量通过数量内。

## 最终软件验证与交付

构建/测试源码：`ca246228922dd3a2371180657609cb733537e69a`；SDK三包及coach override：`66dd98a549c1ff5fedecb626a7c88583090a1440`。后续仅README/docs收束；最终分支HEAD由交付目录 `final-closeout.json` 记录。版本为0.1.0+49，internal arm64 versionCode=2049。

Flutter 3.44.7：全量 **843/843通过，0失败/跳过**；`flutter analyze --no-pub` 0问题；严格离线lock通过。锁文件只更新三包ref/resolved-ref六个值，非SDK依赖逐字保持。真实v3媒体HTTPS样本校验通过。包装辅助脚本另有33/33通过，不计入Flutter数量。

| arm64 internal产物 | 大小（十进制MB） | APK路径 |
| --- | --- | --- |
| release | 42.656 MB / 42,655,670B | `E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-slide\SmartFit-trainer-transition-0.1.0+49-ca24622-internal-arm64-v8a-release.apk` |
| profile | 53.609 MB / 53,609,054B | `E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-slide\SmartFit-trainer-transition-0.1.0+49-ca24622-internal-arm64-v8a-profile.apk` |

两包均同原签名，ZIP/ELF 16KB、JNI导出门禁通过；release小于45,000,000B，AssetManifest及ZIP无mp4，原Noto字体和必要静态/音频资源保留。profile官方VM service的原始JAR→merged→stripped→APK来源链已校验。逐包SHA及门禁见[机器台账](reports/trainer-transition-plus49-slide.json)和交付目录 `validation-release.json`、`validation-profile.json`。

软件关键帧30张位于交付目录 `software-frames/`，包含三个计划入口×浅深，进入0/150/300ms、退出140/280ms；8项实际计划入口矩阵（另含对话展开）通过，SDK动作库/推荐入口另有4项浅深矩阵。它们是软件渲染证据，不能据此填写真机帧耗时或无闪烁通过。

候选保留 `codex/trainer-transition`，未合并、未推送、未打tag；main、release/1.0与SDK源码保持。开哥按上方10组手机步骤录屏并分享JSON后，再做真机结论。
