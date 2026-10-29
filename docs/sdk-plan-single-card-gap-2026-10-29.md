# +41 我的计划：同一张卡变形的 SDK 接口缺口

**同日后续：SDK71 已发布 header / collapsedSummary / onToggle，技术缺口已补齐。** App 已于 `31fd3f0b0741175536b0a72ff2e0fc4f71b18f9f` 接入并重新打包，同一 +41/2041，软件检查通过，仍待开哥远程验收。见[新候选](ui-polish-1-plus41-single-card-2026-10-29.md)。以下为 SDK475 时的原始阻断记录，保留历史来源。

核对时间：2026-10-29（Asia/Shanghai）。App 分支 `codex/ui-polish-1`，HEAD `4047072ba71838b2782180a2cd2d486ab0df8c8c`；现有修复候选 APK 源 `9777eb4a2eed52dda173bd31e2e7f3f69d413b83`。SDK 声明、解析、本地 HEAD 与远端 main 均核实为 `475a5d84b5d0fce839d9d4475da22a6d1ce2df19`。

**第一项暂停。当前接口不能满足单卡变形，不能把现有 +41 当作该项已验收，也不生成另一个假称修好的 release APK。** 本轮未改 App/SDK 代码，不再增加收起卡或 App 动画。

## 已确认的问题

App 的 `saved_plans_page.dart:178` 同时放置 `_CollapsedSavedRow(_SavedTile(...))` 和 `CoachPlanExpanded`。前者自建了高度、淡入控制器（同文件约374行），后者内部另有自己的卡面和动画。这确实是两个卡面交替，不符合本次要求；稳定的展开实例 Key 并不能令两张卡变成一张卡。

SDK `packages/ugk_coach_ui/lib/src/plan_expanded.dart:217` 把整卡包在 `heightFactor: _height.value` 下，234行附近又把 `CoachCardSurface`、标题及所有控件一起包在 FadeTransition 中。`expanded:false` 会把整张卡收成零高度，并排除点击、焦点、语义。它没有可见的收起条目或可点展开区域。

## 最小必须补齐的合同

| 缺口 | SDK 需要提供的能力 |
| --- | --- |
| 常驻标题/收起摘要行 | 增加能承载现有“我的计划”收起行的固定头部/摘要插槽，或等价的 SDK 内置收起呈现。参数名由 SDK 决定，例如 persistentHeader/headerBuilder；本报告不指定新视觉数值。内容包括现有缩略图、标题、元信息、开练和更多菜单。 |
| 从收起态请求展开 | 若头部插槽允许 App 保留原点击回调，App 可只切换既有 expanded，不必额外加 controller；若头部由 SDK 绘制，则需 onExpand 或 onExpandedChanged 之一。 |
| 原条目右上更多入口 | 该入口可以包含在上述常驻头部插槽中，App 继续负责调回对话/重命名/删除；无需另造菜单数据模型，也不移到 AppBar。 |

**仅加参数不够，还必须调整组件内部结构：** 每个条目的一张 `CoachCardSurface` 与标题/摘要行应留在内容高度动画及淡入之外，保持同一实例/Element/Key；只让下面的现有详情内容伸缩、淡入。头部插槽只传静态行内容，不能把带有独立 `SfPolishCard` 的整个 `_SavedTile` 再塞进去，否则仍会产生双卡。提供自定义头部后，应避免 SDK 再重复绘制一个标题。不能仍把常驻头部放进整卡 heightFactor=0 的子树。

可选但非上述变形根因：公开展开/收起完成通知，可让现有 `ensureVisible` 精确在内容动画结束后触发并取消旧请求。当前 SDK 没有 onEnd，App 只能用280ms延时加post-frame测量；是否补该通知由 SDK/Hark 决定。

## 已有参数，不必重加

公开构造 `plan_expanded.dart:16` 已有 key、plan、library、expanded、onCollapse、actionIcon、actionLabel、onAction、onStart；计划数据、完整剂量与可信缩略图均已齐备。查看详情/开练的页脚合同无需再设计。

公开组件内部已实现280ms easeOutCubic高度和前180ms淡入（约88行）；缺的是动画作用区域和收起呈现，而不是再加一组时长参数或 App AnimationController。SF 后续应保留一个同 Key 的 CoachPlanExpanded，只切 expanded，旧项收起/新项展开在同次状态更新中触发。

## 对话卡路径与公开路径的区别

对话 `CoachPlanCard` 通过私有 `CoachPlanExpanded._dialog` 注入现有布局及飞图投影（`plan_card.dart:945`）；其原时间线仍为550ms展开/450ms收起（约161行）。公开 standalone 路径是280/180ms且整卡归零。两者共享详情行不等于外壳和动画已经完全相同。本次以用户明确指定的280ms及常驻外壳合同为准；不自行把任一路径的数值改到另一条路径。

## 恢复第一项工作的条件

由 SDK 补齐上述呈现/事件合同并发布受验的新提交后，再统一锁定三包，移除 App `_CollapsedSavedRow`/独立 `_SavedTile` 动画，只保留该单一组件。届时重新完成测试、analyze、同一 +41/2041 release APK 和展开/切换/收起录屏。本轮为全 App 摸排准备的 profile 采集包保留当前功能，用于记录基线，不是该修复的交付。
