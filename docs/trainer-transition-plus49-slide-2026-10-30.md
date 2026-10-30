# +49 标准水平滑动训练路由（2026-10-30）

本记录取代此前的训练转场方案。基线为3934da7，版本0.1.0+49 / internal arm64 2049；分支codex/trainer-transition，SDK三包及override保持c97a79a5f03ba1f46f017b995f7f8d97fb3016a9。已提交的上一份性能候选通过后续提交撤回并替换，不改写Git历史；最初工作树干净，没有未提交改动需要丢弃。

本轮范围按开哥补充明确：**保持SDK pin，先交付宿主可控入口，单列待SDK接入项**。候选不合并、不推送main、不打tag；release/1.0与SDK源码不动。最终源码、测试、APK大小及签名门禁以交付目录本次新回执为准，不继承旧包通过结果。

## 删除内容

删除training_transition.dart、training_entry_placeholder.dart、training_poster_flight.dart与chat/expand_route.dart。TrainingRoute整体替换：移除TrainingTransitionSource、OverlayEntry、Rect插值、圆角动画、整页缩放、独立回程与visualCompleted；PlayerPage不再传chromeAnimation，删除IssueMotion和完成页退场海报层。卡片不再测量/隐藏配图，图文页删除mediaOpacity和origin捕获。SDK计划卡自身展开/收起不受影响。

删除旧trainer_transition_test/training_route_test及旧三份专用转场文档、两份台账，移除主文档旧方案段落。保留finished行初次布局高度0、sessionId去重、240ms完成记录入场与300ms滚动的列表修复；新测试验证标准滑动，不保留旧动画开关。

## 唯一入口与保留状态

宿主只在lib/ui/open_training.dart构造TrainingRoute并push。每个Navigator的入口锁覆盖预热、会话开始记录、整个训练页及最终dispose，重复点击不push第二次。

| 来源 | 调用链 | 返回保留 |
| --- | --- | --- |
| 对话AI/普通/保存展示计划卡，收起与展开 | PlanCard/ValidatedPlanCard → ChatHomePage._start → openTraining(chat) | 同一页面与SDK卡片State、展开状态、滚动位置、主题 |
| 我的计划直接播放，收起与展开 | SavedPlansPage._start携带本页context → ChatHomePage._start → openTraining(saved_plan) | 不先pop保存列表；保留列表Element、展开条目、offset |
| 图文详情的前往训练按钮 | PlanPage._startTraining → openTraining(guide) | 来源包括对话详情、我的计划详情、自定义计划；保留文章Element/offset，预览可恢复但不自动播放 |

## 防闪烁实现与回归

| 要求 | 实现 | 对应测试 |
| --- | --- | --- |
| 首帧完整 | SDK TrainerPlayer从第一帧挂载，chromeAnimation不传，全部控件处于完整状态；转场没有入口占位页、整页Opacity或控件延迟挂载 | training_entry_matrix_test：三个入口及对话展开/收起×浅深，在0/150/300ms核对真实SDK控件、RawImage像素及无loading |
| 预解码 | 入口可见即预热；屏宽×DPR的ResizeImage与训练海报同键；点击最多等150ms。未完成则不push，保持原页面并提示再次点击，后台预热继续 | 入口矩阵预热/首帧像素；慢解码门禁回归 |
| 背景与系统栏 | opaque=true、allowSnapshotting=false；训练Scaffold/宿主底色一致，AnnotatedRegion按主题同步状态栏/导航栏与图标；不使用MaterialPageRoute默认训练效果 | training_slide_route_test浅深背景/系统栏与位移 |
| 视频接管 | startGate只在300ms路由completed后的完整帧末开放；进入中仅海报。ExerciseVideo和首帧海报同位置/裁切/尺寸；真正绘制first-frame且position>0后200ms淡出覆盖图；无视频则保持图片 | training_slide_player_test核对门禁、像素、尺寸、绘制后才揭开；解码失败后图片模式可完整计时完成 |
| 立即退出与保存并行 | onExitStarted同帧驱动本Route的controller.reverse，SDK仍保存/ack；beforeExitPop等待同一280ms future。滑出前只暂停现有视频，280ms完成后退役，保存成功后SDK正常pop；正常提前结束不显示完成页 | real SDK浅深×关闭/系统返回、慢保存先滑出、保存一次/receipt一次；自然完成使用同一退场 |
| 失败与迟到pop | 保存失败恢复SDK完整重试页并刷新ModalRoute指针状态。重试按钮只保存；用户完成后再离开。透明静态输入shield阻挡慢保存期间底页另开路由，不绘制任何暗层 | route快慢保存及底页真实点击；player快速失败恢复、retry与完成后仅一条记录 |
| 来源页不动 | 短转场activity缓冲store/chat通知，source保留RepaintBoundary；保存列表缓冲自有listener并停reveal；finished只在route.completed后插入，首帧零高度，随后平滑滚动 | 入口矩阵Element/展开/offset；saved_plans_expand、chat_training_return、app_flow、plan_article回归 |
| 返回与移除动画 | 只有SlideTransition；300ms easeOutCubic进入、280ms物理easeInCubic退出。系统移除动画为0ms；无边缘右滑手势，SDK确认仍适用于系统返回 | route位移逐段断言、zero-duration、进入中返回/后台/移除无残留 |

Flutter反向tween需要reverseCurve=easeInCubic.flipped，使实际右移位移为easeInCubic(elapsed)；测试验证实际offset而非只比较枚举。精确300/280ms时先核对终点，另推进1μs派发Flutter的completed状态；没有改变规格时长。

当保存比280ms更慢，画面已退出、视频已退役，SDK实例与训练导航锁保留到持久化完成，避免丢记录和迟到pop弹错页。若保存失败，完整重试页滑回；不提前伪造成功。SDK原生视图、计时、语音、记录及确认逻辑仍由SDK管理。

## 内部帧耗时与手机步骤

入口：设置 → 内测工具·正式版不显示 → 训练进出帧耗时。仅internal启用SchedulerBinding.addTimingsCallback与入口；正式flavor关闭。每条记录帧数、build/raster最大值及P90、严格>16ms帧数、入口、主题、源码/SDK、实际后端与首次标记；最多最近10次，异步保存Application Support，复制/系统分享输出同一JSON。分享复用现有FileProvider与Android chooser，由用户选飞书；打开chooser不等于发送成功。

1. 安装本轮profile包，保留数据。系统动画为1×。
2. 对话计划卡、我的计划、图文详情，分别用浅色/深色，共6组。每组进出3次，覆盖提前结束、自然完成、Android系统返回，并用手机录屏。
3. **每组3次后立即复制或分享一次**，备注入口/主题，再继续下一组。最近10条会滚动覆盖，不能18轮做完才导出。未连电脑也可在系统分享面板选择飞书，或把JSON复制回会话。

本机无连接真机；测试/软件截图/APK门禁不能替代手机全程无闪烁验收，不填造帧耗时或设备后端。

## SDK待接入（本轮明确保留，不改pin或源码）

SDK packages/ugk_trainer/lib/src/pose_hub/pose_hub_action_browser.dart:282–295 的私有onTap仍自行push MaterialPageRoute；App入口为lib/ui/posehub_library_page.dart。该浏览器公开构造器没有onOpenAction/routeBuilder，宿主不能通过公共接口替换它的路由。

同文件PoseHubSinglePracticePage:557–577没有startGate/mediaBuilder/onExitStarted/beforeExitPop，:640–675没有透传。App的lib/ui/library_page.dart中showExerciseDetails用于推荐动作/旧目录详情，仍保留此SDK预览。TrainerPlayer目前仅training模式遵守startGate，preview仍会准备和启动默认视频。

建议SDK新增可选onOpenAction(BuildContext, PoseHubPackAction)或practiceRouteBuilder；单练封装透传startGate、mediaBuilder、onExitStarted、beforeExitPop，并让preview媒体也遵守门禁。之后再接入唯一openTraining。没有用observer事后换路由、复制SDK私有控件或操作私有State绕过这些接口。
