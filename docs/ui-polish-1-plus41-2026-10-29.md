# SmartFit 界面体验修复第一批 / +41

2026-10-29（Asia/Shanghai），分支 `codex/ui-polish-1`，独立工作树 `Sport-Helper-ui-polish-1`。开哥明确反馈 +40 已真机确认通过，并授权将 `codex/coach-v2` 合入 main、推送。已核对 `428c5f3..adc79ab` 仅包含 8 份文档收束；main 从 `7344df2` 快进到 `adc79abef2b7195872e589f6225486e944b66644` 并推送，远端 SHA 已核实。本候选以该新 main 为基线。`release/1.0` 未操作。

App 为 `0.1.0+41`，internal arm64 Android 构建号应为 `2041`，实际身份以 APK aapt 回执为准。SDK 三包及传递 override 仍固定 `1532f0825b93777139be0e92e715ebec144a73b9`，未改 SDK、未换依赖、未复制 SDK 组件，也未操作 SDK 缓存。

## 已实现与明确未完成项

| 项目 | App 已实现 | SDK 限制 / 未完成 |
| --- | --- | --- |
| 〇公共卡面 | `SfPolishCard` / `SfCardTokens`：圆角20，描边1，浅色白底 / #E3E8E6，深色 #1A2324 / 白色8%，无阴影，默认内边距12。生成卡、我的计划、App fallback动作卡与 SDK 外层 surface hook 复用。主色沿用现有青绿。 | SDK 推荐动作内层和正式动作库自行绘制卡面，不能完整套用 App 公共组件；SDK 内部卡面 padding 仍由其布局决定。 |
| 一生成过程卡 | SDK 当前轮 task / params / picks 驱动已定稿标题、状态句和来源标签，原始 stamp 与内部词不展示。56区、弧线2/90度/1200ms、6px跳点/120ms错开、缩略图900+250ms、四段3px/r2/gap4/400ms、状态220ms/上下8、微光1600ms、标签26/r13/12sp/pad10/200+60ms、完成300ms交叉淡入与高度变化。取消44触区，减少动态时静止。 | 无 App 范围的已知缺项；微光强度及未指定的跳点幅度复用主题值，全部数值集中在主题文件。 |
| 二计划卡 | 展开/收起共用 App 按钮 face：高32/pad12/r16/13sp，保留原 SDK 的语义、键盘激活和触感；外层 ClipRRect20，surfaceTopInset=0。 | SDK 仍固定44外槽、两态位置和58dp upright overhang；无法保证距卡面上/右12且两态同位，外层 clip 不能等同实际绘制卡面边界，人物出框问题未完整解决。 |
| 三输入遮罩 | 从实际输入框上方72至输入框底，随1–4行输入和键盘/面板变化重新测量；色标0/35/70/100%，透明度0/18/72/100%，与功能区同一背景 token，底边无描边。 | 无。 |
| 四动作库 | App fallback 使用 `SfActionTile` 公共卡面，图片区1:1，标题15/w600/1.35固定两行，12sp次要标签底对齐，网格双向间距12，窄屏和大字等高。推荐卡通过公开主题传入相同标题/标签字样式。 | 正式入口实际转 SDK `PoseHubActionBrowser`；其圆角22、图片区渐变、文本padding、标签行和 SDK推荐内层圆角16/渐变/标题高度无法从 App 接口覆盖，故正式动作库统一样式未完成。 |
| 五我的计划 | 收起条目复用公共卡面及统一时长，副标题 `{N} 套`，`…` 增加“点一下在对话里调出”，右侧开练保留。 | `CoachPlanCard` 无受控展开或展开回调，展开列表组件私有；不能按要求复用现成展开态、只开一个、280ms或替换展开态保存为查看详情。本批没有另写展开列表，条目点击仍调回聊天，原地展开未完成。 |
| 六图文详情 | 协议分段名称映射中文（未知英文按已知block语义回退，不显示原值），空/同名安排说明整段隐藏；卡片/详情/保存条目均调用 `planDurationLabel`，按实际可执行训练时长计算；前往训练为主色，底部保留按钮高度、实际悬浮偏移与24px净距。 | 无。 |

SDK 定位依据为已解析的 `ugk_coach_ui/lib/src/plan_card.dart`、`recommend_card.dart`、`theme.dart` 与 `ugk_trainer/lib/src/pose_hub/pose_hub_action_browser.dart`；App 入口为 `lib/ui/chat/plan_card.dart`、`lib/ui/posehub_library_page.dart`、`lib/ui/chat/saved_plans_page.dart`。不得通过 Element/私有 State 控制 SDK 展开，或用 App 复制一份 SDK 卡片规避约束。

## 验证和截图

固定 Flutter 3.44.7 / Dart 3.12.2，官方 pub.dev 源和现有离线缓存。全量开启 `SMARTFIT_CATALOG_TEST_PACK` 和匿名 HTTPS smoke，使用 `flutter test --no-pub --flavor internal --concurrency=1 --reporter expanded`；静态分析为 `flutter analyze --no-pub`；严格锁文件为 `pub get --offline --enforce-lockfile`。最终结果及源码绑定见交付目录 `validation/` 和 `release-apk.json`。

最终全量 **586/586通过、0跳过**，静态分析 **0 issue**，严格锁文件通过。首轮6条失败均为旧展示契约断言（内部stamp、旧标题和推荐样式hook），按本批产品要求更新，保留并增强了原控制器状态、取消、重试及迟到事件验证；没有跳过测试或削弱分析配置。复核发现的两项当前轮/新对话边界已补回归并计入最终全量。训练继续按钮的珊瑚色也通过 App `TrainerTheme` 映射到现有青绿，SDK源码不变。

最终尺寸复核补齐了 App fallback 动作卡图片区上/左12内边距、图片区宽=卡宽-24且1:1的精确断言，空的“我的计划”副标题统一为0套；修正后再次全量586/586、零跳过、分析零问题，20张改后图重采与既有哈希完全一致。首轮 `f3871b6` 构建及原始回执按字节保存在交付目录 `attempts/f3871b6/`，仅供审计；最终交付以根目录新 `release-apk.json` 指向的 APK 为准。

改前以 `adc79ab` 独立 detached 工作树渲染，改后使用本候选。相同数据、字体、视口、素材、截图入口，共40张真实 Flutter App/SDK 软件原图；含0–6浅深，以及计划两态、我的计划点击后、详情顶部和真实底部。所有原图、像素/哈希清单、对照页见 [完整截图对照](../../deliveries/ui-polish-1-plus41/screenshots/index.html) 和 [原图索引](../../deliveries/ui-polish-1-plus41/screenshots/README.md)。SDK 限制项保持真实界面，“我的计划点击后”仍收起，不冒充展开已实现。

新增回归覆盖来源标签、真实节点与旧stamp隔离、取消/重试/迟到事件、32px按钮面及语义、输入遮罩两主题与多行精确锚点、300ms高度和淡入同时进行、交付时条目 State 保留。复核补上“生成中开启新对话”欢迎页关联，以及新轮准备窗口不得读取上轮已完成 SDK 账本的回归。

## 构建与交接

交付目录 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41/`。构建脚本仅对干净提交执行，沿用既有私有配置并脱敏；绑定源码指纹、完整 SHA、SDK和素材，校验同签名、ZIP/ELF 16KB、存储JNI及实际APK身份。具体 APK 路径、大小、SHA-256和打包源码取 `release-apk.json`，不以文档提交替换打包源码。

+41 只供开哥内部真机确认。本轮没有自动安装、真实模型新调用、设备性能、长训练或iOS验收。+41 尚未合 main / 未推送 / 未打 tag，等待开哥确认及安排；+40 已被用户确认并进入 main 的事实与 +41 待验边界分别记录。
