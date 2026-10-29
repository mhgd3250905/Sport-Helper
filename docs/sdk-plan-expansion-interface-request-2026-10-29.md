# 我的计划原地展开：所需 SDK 接口

后续状态：用户已授权，SDK侧已实现并发布 `475a5d84b5d0fce839d9d4475da22a6d1ce2df19`，公开名为 `CoachPlanExpanded`。App已统一更新三包锁定，按[两项补齐记录](ui-polish-1-plus41-plan-expand-2026-10-29.md)接入；下文保留为488基线时的接口请求历史，不再表示接口仍缺失。

当前三包固定 `488ce82b9dc7031925ba12c18f252b4e596e7776`，本次只读核对 SDK 本地和远端 main 均为该提交。SDK 仓库、缓存源码和依赖锁定尚未修改。

`packages/ugk_coach_ui/lib/src/plan_card.dart` 的公开 `CoachPlanCard` 没有受控展开、初始展开、展开通知或动画参数。展开状态、切换方法、`_Header`、`_Details` 和 `_MoveRow` 都是私有实现；内部展开/收起时长为550/450ms。公开主题 builders 只提供外观与控件 hook，不提供展开内容。因此不能同时遵守“不改SDK、锁488”“直接复用展开态、禁止另写一份”并实现单条展开及280ms动画。

建议只为 SDK 增加一个公开的展开内容组件，例如 `CoachPlanExpandedContent`，接收 plan、library、onCollapse、onStart 和 footerLeadingAction。它从现有详情实现提取，SDK 对话计划卡内部也必须调用同一个实现，继续沿用 SDK 媒体、序号、缩略图、名称、剂量、开始控件与主题；不要在 App 复制私有实现，也不要访问 SDK 私有 State 或遍历 Element 调用内部回调。

该接口具备后，App 负责唯一 expandedId、收起条目的原样式、280ms easeOutCubic 高度动画与前180ms淡入、动画后需要时 ensureVisible（240ms easeOutCubic），以及将保存位置替换成14sp主色“查看详情”并导航现有 PlanPage。菜单里的“点一下在对话里调出”、重命名、删除和原▶训练入口继续工作。

需要用户明确授权最小 SDK 接口改动及更新本次 +41 的锁定提交后再实施；本文件是可审阅的接口需求，不表示该接口已实现或第一项已完成。SDK 推荐动作卡和训练页样式不属于这次接口变更。
