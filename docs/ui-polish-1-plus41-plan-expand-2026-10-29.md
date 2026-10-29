# +41 两项体验补齐

本轮继续在 `codex/ui-polish-1`，版本保持 `0.1.0+41`、internal arm64原生构建号2041。菜单实现先保存于 `826ea92c7b1126bb2e8639e2ab1464411aa91028`，其607项测试、分析与菜单候选APK完整保留在 `../../deliveries/ui-polish-1-plus41-supplement/`，属于中间检查点。两项合并后的交付与源码回执另存于 `../../deliveries/ui-polish-1-plus41-plan-expand/`。

## SDK 与实现归属

用户已明确授权在SDK公开计划展开内容并于SDK发布后更新三包。SDK远端main核实已为 `475a5d84b5d0fce839d9d4475da22a6d1ce2df19`；App三包声明、coach传递override及锁文件的ref/resolved-ref均统一该完整提交，包版本仍为coach0.8.0、coach_ui0.4.0、trainer0.6.0。逐包锁文件审计确认非SDK依赖没有改变，离线严格锁解析通过。

公开 `CoachPlanExpanded` 的合同见SDK `packages/ugk_coach_ui/docs/plan-expanded.md`。该组件与对话计划卡共用既有序号、缩略图、名称、完整剂量、收起和开始控件；独立受控实例自带280ms easeOutCubic高度与前180ms淡入。App直接调用该组件，不复制SDK行、header、footer布局或私有状态，不修改SDK仓库及缓存源码。

“查看详情”通过公开actionIcon/actionLabel/onAction传入。仅在保存计划展开组件的局部theme scope复用既有14sp `SfTextAction`并映射既有主色；其余主题和builders沿用原计划卡。推荐动作卡继续使用SDK默认scope，训练页和完成页未增加任何SF样式覆盖。

## 我的计划原地展开

页面只持有一个expandedId，同帧展开新条目并收起旧条目。SDK组件保持同key从expanded:false切换，保证首次点击也经过内置动画；收起行保留child，同步280ms高度与180ms淡出，隐藏时排除点击、焦点和语义。收起卡面沿用共用SfPolishCard。

底部左侧为图标加14sp主色“查看详情”，进入现有PlanPage；展示副本保留原计划ID、剂量和其他数据，只将标题映射为保存/重命名后的名称，原计划不回写。右下▶继续原onStart合同。副标题保持“{N} 套”，“点一下在对话里调出”、重命名和删除保留在收起条目右上的…菜单；展开态直接使用SDK自带的收起控件。

展开280ms结束后再等本帧布局完成，只有条目底部超出可视范围时才调用Scrollable.ensureVisible，以240ms easeOutCubic滚动。nonce、mounted和当前ID校验取消过期请求；切换、收起、删除、打开详情或开始训练会取消待执行请求，并停止仍在执行的自发滚动，不强拉到其他位置。

新增重命名回归同时修正原对话框控制器释放过早的问题：由对话框自己的State持有，在实际卸载后dispose，避免关闭动画期间已挂载TextField访问被释放控制器。文案、字段和按钮保持原交互。

## 菜单修复

复用已验证的菜单实现：一个240ms控制器，展开easeOutCubic、收起easeInCubic，ClipRect与SizeTransition顶边对齐、FadeTransition、下方8px平移；输入框随Column高度自然移动。Flutter3.44使用 `alignment: AlignmentDirectional.topStart` 等价替代已弃用的垂直 `axisAlignment:-1`。

菜单高度由现有内容与主题配置固定计算，不在动画中测量。键盘与菜单共用底部占位，同高交换保持输入坐标；键盘变矮或没有IME时同一控制器平滑收回余量，中途重开延续当前可见高度。对话和输入各有独立RepaintBoundary，局部视口更新缓存消息子树，不再逐帧setState重建主页。用户离开底部阅读时不强拉回底部。

## 验证与回执

最终计划列表实现、测试结果、APK身份、源码与SHA256以本轮交付回执为准；本文件在最终构建后补齐实际结果。旧菜单候选的607测试不替代SDK475和两项合并后的全量验证。

前图仍为本次补项前的 `d6bd79cd8dc6c5439f67779bd6e894af7981faa3`，使用同一真实App入口、390×844逻辑视口与字体/素材；菜单候选中途图继续保留。最终后图在最终功能提交后重采，并记录首次展开、互斥切换、详情入口和需要滚动的展开项。软件截图证明外观和实际导航，不证明真机帧耗时。

用户明确本机无真机、禁止启动模拟器，由用户远程安装验收。本轮没有设备操作、真机录屏或“全部帧≤16ms”的通过结论；两个版本号保持不变。App main与release/1.0不动，等待用户远程确认后再决定合main。
