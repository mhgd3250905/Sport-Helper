# SDK tag 升级与共享聊天 UI（2026-10-24，待批准）

SmartFit 开发分支 `feat/sdk-coach-ui-20261024` 基于 main `f5332bfe3746ecbf69d3f5e48c71ba5c90812499`。SDK 分支 `feat/coach-ui-smartfit-20261024` 已保存为 `f0ea0647586913b205fc6dbb75fc9f97cedc55ce`。两个 main 尚未合入或推送，新 tag 尚未在 SDK 原仓库创建或发布。`release/1.0` 保持 `6c786c08450d5a988db32af025ef0a1f8f5ae331`，未修改其工作树。App 版本仍为 `0.1.0+22`，不是商店发布候选。

## 依赖与 SHA

| 依赖 tag | 完整 SHA | 状态 |
| --- | --- | --- |
| `ugk_coach-v0.4.1` | `88da65ab4e7d6753ab548d779f4168f023dbf9f8` | 已有正式 tag，未修改 coach |
| `ugk_trainer-v0.2.1` | `f0ea0647586913b205fc6dbb75fc9f97cedc55ce` | 本轮待批准 tag |
| `ugk_coach_ui-v0.1.0` | `f0ea0647586913b205fc6dbb75fc9f97cedc55ce` | 本轮待批准 tag |

原目标 trainer `ugk_trainer-v0.2.0` 同样指向 `88da65a`，但其相对 `ugk_coach: path: ../..` 被 Pub 转成提交 ref，与宿主显式 `ugk_coach-v0.4.1` 的 Git 来源冲突，真实解析失败。因此仅将 trainer 的依赖声明改成 coach 正式 tag，并升补丁版 0.2.1；trainer 运行代码保持 0.2.0。SmartFit 三项依赖均锁 tag 及精确版本，不提交本地路径 override。

## 完成行为

`CoachAgent` 保持 App 生命周期会话；只在 `send()` 返回后，把 `result.question` 显示为一条询问气泡，不重复显示相同正文。支持文字、单选和多选，答案继续发送给同一个 agent，直至生成通过门禁的套路。旧问题、恢复历史和进行中的回答禁止重复提交，新对话清除待答状态；模型选项不会被当作 App 命令执行。

`ChatMessage` 保存已校验问题、答题状态和选中项，恢复时重新经过 `AskUserGate`。历史问题只读，因为历史 JSON 不代表仍持有 SDK 的活跃对话。无 Key 时继续使用本地引擎，并隐藏 AI 记忆设置和 AI 服务文案。网络请求、设备身份、Key、持久化、结果门禁及训练导航继续归 App 所有。

App 计划适配保留 SDK 的 `PlanSegment`，不会在保存、恢复、复制或交给 trainer 时丢段。校验、未知动作保护和媒体预取包含所有分段动作；无节奏次数动作按 trainer 0.2 的缺省节奏自动计数。新增播放器操作开关保持原默认值。

## UI 包与 HipLab / Flare 接入

SDK 新包 `packages/ugk_coach_ui` 仅依赖 Flutter。现有聊天列表、消息/选项/等待气泡、询问气泡，以及约 1,900 行套路卡布局和展开动画已真实迁入；SmartFit 留下主题、受信动作目录、素材和导航适配。包源码无 SmartFit import、接口地址、HTTP client 或 Key 字段。

公开接口包括：

- `CoachChatList`、`CoachChatEntry`：聊天列表、稳定行标识和进入动画。
- `CoachMessageBubble`、`CoachBubbleData`、`CoachOptionPill`：消息及选项。
- `CoachQuestionBubble`、`CoachQuestionData`、`CoachQuestionMode`：文字、单选及多选，异步答案回调。
- `CoachPlanCard`、`CoachRoutine`、`CoachRoutineItem`、`CoachExerciseLibrary`、`CoachExercise`、`CoachMediaPalette`：套路和受信素材展示；保存、查看和开始由回调执行。
- `CoachUiTheme`、`CoachUiStyle`、`CoachUiColors`、`CoachUiTypography`、`CoachUiStrings`、`CoachUiBuilders`：颜色、字体、文案和产品控件注入。
- `CoachGreetingBlock`、`CoachTimeMark`、`CoachTypingBubble`、`CoachAppear`、`CoachOriginRect`、`coachRectOf`：配套呈现和转场位置接口。

完整参数与可编译接入示例见 SDK 的 `packages/ugk_coach_ui/README.md` 和 `example/lib/host_conversation.dart`。宿主必须先完成 coach 门禁校验，再映射呈现 DTO；UI 包不把 DTO 当作已接纳的训练计划。

## 验证与边界

已通过 SDK UI 包 8 项组件测试和静态分析、trainer 207 项测试和静态分析。SmartFit 从原始 main `f5332bf` 导出独立基准，迁移后深浅色计划卡及聊天截图均通过逐像素 golden 比对；原展开动画、窄屏、大字体和控件行为回归继续保留。Web release 编译通过。

最终使用 Git tag 来源锁文件运行 SmartFit 全套：**452 通过、13 个既有条件跳过、0 失败**；分析无问题。AI 引擎文件 54 项全通过，覆盖文字→多选→套路、事件/结果去重、旧题和恢复历史只读、双击、取消、新对话、可信本地导航，以及超长答案重试。询问气泡还通过真实聊天页的组件交互测试。首轮全套发现 4 项测试仍查找旧 trainer 控件，已适配新环形进度绘制器和数字组件，保留原计时/暂停/固定位置断言后全套通过。

Android `flutter build apk --debug --flavor internal --no-pub` 编译通过，产物为 `build/app/outputs/flutter-apk/app-internal-debug.apk`，仅用于编译验证，未安装或上传。相关文档 104 个相对链接检查无缺失，Git diff 检查通过。独立复核确认询问边界、UI 包隔离与分段适配无阻断。

`flutter pub get --offline --enforce-lockfile` 通过；三项 SDK 依赖均为 Git URL、tag、完整 `resolved-ref`，无路径 override。新 tag 尚未获准发布，故此处从与 SDK 待审提交字节一致的隔离 Git 镜像解析候选 tag。Windows 本机 ANSI 936 会误解码 `git show` 的 UTF-8 中文包描述，Pub 验证采用仅当前进程可见的输出转码包装器；未改原仓库的 SDK blob、系统设置或共享 Pub 缓存内的 SDK 源码。最终锁文件中的地址仍为正式 GitHub 仓库。

本轮 AI 验证使用 fake client 和真实 SDK agent，不读取或注入在线 Key。未声称真实模型服务、多设备、iOS、长时锁屏或手机帧率通过；没有安装 APK、修改手机或操作商店。完整本机日志、基准截图和待发布 tag 的隔离验证镜像位于项目根 `deliveries/sdk-coach-ui-review-20261024/`。

## 批准后的顺序

1. 核对远端未发生新改动，以审核提交快进合入 SDK main，创建并推送上表两个新 tag 及 main。
2. 从正式远端再次验证 SmartFit tag 锁文件，快进合入并推送 SmartFit main。
3. 回报实际远端 SHA；若远端有新提交或代码需要调整，则重新验证差异，不能绕过批准直接覆盖。

在批准前，隔离 Git 镜像中的候选 tag 只用于验证解析；它们不代表原仓库已发布。Cockpit 保持非终态工作会话。
