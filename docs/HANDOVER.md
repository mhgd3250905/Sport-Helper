# 智能健身助手（SmartFit）交接说明

## 当前 +48 视觉重做状态（2026-10-30）

旧 `c0a0fc0` 候选未获视觉验收，按卡片展开/收回的新设计重做。只读核查确认 SDK 652 缺少延迟启动、控件分块包装与结束展示阶段接口；按用户要求先交[原因及 SDK 接口报告](trainer-transition-plus48-redesign-audit-2026-10-30.md)，不以遮罩或复制控件绕过。已有20项诊断回归通过，未改运行代码/SDK、未出新版包或录屏。用户已确认进入总长560ms：分层于280/300/320/340ms开始，暂停按钮最后在560ms完成，此时才启动视频、计时和语音；退出数值保持原规范，手机动画均为1×。下方773项及APK只属于原候选；main/release保持，等SDK接口和用户指定新pin后继续。

## +48 训练过渡候选（2026-10-30）

本候选为 **0.1.0+48 / internal arm64 2048**，分支 `codex/trainer-transition`，基于 +47 main `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`。SDK 三包及 override 升级并锁定 `652135f532bac1a06fbf133dc497692d6b44c78a`。进入/退出为 320/260ms，进入结束前不启动训练计时、语音或视频；提前结束保存和回退由新版 SDK 管理。最终源码、测试、构建与真机待验边界见[+48 记录](trainer-transition-plus48-2026-10-30.md)。**等待开哥真机确认后再合入并推送 main**；release/1.0 和 SDK 源码不动，不打 tag。

全量 **773/773、0 跳过/失败**，`flutter analyze` **0 问题**。release **42,602,114B（42.60MB）**、profile **53,506,134B（53.51MB）**，同签名、ZIP/ELF 16KB、存储 JNI、原 Noto 和无 MP4 门禁通过。APK/测试源码固定 `c0a0fc0bf26a4955cc1bfe4e7f943e1a487594db`，其后仅 README/docs 收束；真机 UI/Raster 最大帧耗时待远程采集。

下方 +47 是已合入 main 的基线记录，不代表本候选已经合并。

## 当前 +47 主线整合（2026-10-30）

当前版本 **0.1.0+47 / internal arm64 2047**，已在 `codex/main-integration-plus47` 审核整合 +44 guide-lite、+45 task-bubble-v2、+46 slim-assets，修复播放过渡、连续替换与缓存超额三项问题。全量 764/764、0 跳过/失败，analyze 0；42,598,106B 实包、同签名、ZIP/ELF 16KB、JNI 及无 MP4 门禁通过。

APK/测试/软件截图源码为 `ee6b83ea46b3d0ae9eccaf875b30a968087105c6`。本次 README/docs-only 收束提交用于按用户授权快进并推送 main；后续读取 `deliveries/main-integration-plus47/git-scope-observation-post-main.json` 与 `delivery-status-post-main.json` 核对最终主线完整 SHA，不能把文档收束 SHA 改称 APK 编译源码。具体路径和哈希见[本批记录](main-integration-plus47-2026-10-30.md)及[精确台账](reports/main-integration-plus47.json)。

原分支/工作树/产物保留，SDK 三包保持 b490eec、整份锁文件不变，release/1.0 不动，不打 tag。原 Noto 保留。新截图仅软件证据，本轮没有设备操作或原生性能验收。

以下内容保留各原时点记录，其中旧 main、版本及候选合并状态不代表本批最终状态。

## 历史 +46 资源瘦身候选（2026-10-30 原时点）

接手 `codex/slim-assets` / +46（internal arm64 2046），独立基于已验收 +43 的 main `94e924fe`。SDK 三包、override 和整份锁文件保持 b490eec；+44/+45 不依赖、不合并。全量 705/705、analyze 0 问题；按需媒体、跨版本缓存与边界见[本轮记录](slim-assets-plus46-2026-10-30.md)。完整提交和 APK 实数以最终回执为准；字体等待用户选择，当前 Noto 保留。main、release/1.0、SDK 保持原状，未推送、打 tag 或操作设备。

以下为各原时点交接快照；“当前”“待验收”“未合并”和旧 main SHA 都只适用于对应日期。+43 现已验收并合入上述 main。

## 历史 +43 计划讨论候选（2026-10-29 原时点）

本轮在 `codex/plan-focus`，从未合并的 +42 d900549 开始，三包锁 SDK `b490eec43b408a8a35ce81a7830833bc6a3ff278`。已保存计划导入、SDK focus 标签、重启恢复、新版更新/另存与版本迁移见[实施记录](plan-focus-plus43-2026-10-29.md)。最终源码 SHA、APK2043 与验证回执位于 `E:/AII-3D/3D-Sport-AI/deliveries/plan-focus-plus43/`；三轮真实接口和软件截图分别保留原始证据。候选交开哥真机验收，保持未合并、未推送，release/1.0 与 SDK 仓库不动。以下为历史接手记录。

## 当前 +41 验收更正与流畅度摸排（2026-10-29）

开哥确认“我的计划”两卡切换不合格；SDK475收起整卡高度为零，单卡修复按指令暂停，接口缺口已列明，不在App另写动画、不出冒称修复的release包。全App本轮只读报告，应用/SDK/测试代码未改；profile采集包源4047072、同+41/2041已备，开哥远程回传原始JSON和录屏后补实测最大值/超16ms帧数与排序。见[当前报告](ui-motion-audit-2026-10-29.md)及其接口缺口、采集步骤。下方原包测试/“已补齐”记录属于当时检查点，不代表本次单卡验收通过；App main与release/1.0不动，+42待Hark定案且+41合main后再从新main开展。

## 当前 +41 两项补齐 / SDK475（2026-10-29）

最终打包源 `9777eb4a2eed52dda173bd31e2e7f3f69d413b83`；全量611/611、0跳过，分析0问题，实际2041、同签名/16KB/JNI通过，APK143,599,186B / 136.95MiB。26张浅深原图及交互回执已核对，截图8092与打包源仅测试正文差异有Git证据。当前仅待用户远程真机确认，未合入或推送App main。

SDK远端main已核实发布475a5d8，用户授权后三包及coach传递override统一锁定完整SHA。计划列表直接接入公开CoachPlanExpanded，菜单修复沿用826ea92；同一+41/2041的最终源码、测试、APK和截图见[本轮记录](ui-polish-1-plus41-plan-expand-2026-10-29.md)与独立目录 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-plan-expand/`。下方826菜单候选、488初包及更早记录均属历史。没有真机/模拟器操作，最终等待用户远程安装确认；App main、release/1.0不动。

## 当前 +41 菜单补项（2026-10-29）

同一 `codex/ui-polish-1 / +41 / 2041` 继续修复菜单：单240ms控制器、固定面板、键盘共用占位及独立重绘边界。我的计划原地展开仍等待SDK最小公开接口授权，不能记为完成。用户无真机且明确不启动模拟器，由用户远程安装验收；当前软件验证与新APK回执见[本轮记录](ui-polish-1-plus41-menu-supplement-2026-10-29.md)。新交付独立位于 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-supplement/`；下方SDK488初包及其他旧验证均保留为历史。

## 当前接手入口（2026-10-29，同一+41 / SDK488）

当前 `codex/ui-polish-1` 在原+41上继续接入SDK main `488ce82b9dc7031925ba12c18f252b4e596e7776`，三包与锁文件一致，版本仍+41/2041。单动作preview，整套training；完成页感受仅写本地记录与日志，SDK推荐/训练/正式库样式不由SF重写。先读 [SDK488补充记录](ui-polish-1-plus41-sdk488-2026-10-29.md)，最新包/源码/验证位于 `../deliveries/ui-polish-1-plus41-sdk488/`（相对App树）。二/五项SDK接口待办仍在；+41待真机确认，main与release/1.0不动。

最终打包源 `c8c64e3868849cf24e6a917a963d50cc63a0195c`，+41/2041 APK143,533,650B，598项全过/分析0问题/同签名/16KB/JNI通过，58图及回执齐全。接手时使用新sdk488目录APK；旧c636包和此前40张图仅为历史，未经新指令不安装、合main、推送或改SDK。

## 历史接手入口（2026-10-29，+41首包）

`codex/ui-polish-1` / `0.1.0+41`，独立工作树 `Sport-Helper-ui-polish-1`，以已推送的 main `adc79ab` 为基线。用户明确确认 +40 真机通过并授权此次 main 合并/推送；+41 的验收与主线准入仍等待用户下一步。`release/1.0` 未操作。先读[本批逐项状态及SDK限制](ui-polish-1-plus41-2026-10-29.md)和[版本台账](version-management.md)。不得把SDK正式动作库或原地展开未完成项当成已通过，也不得把软件截图冒充真机验收。

最终+41打包源码为 `c6369c44c0a048d3c0ad56f4a2acbbddbc59048a`，APK和回执均在 `../deliveries/ui-polish-1-plus41/`（相对App工作树）；全量586、分析0问题，包签名/16KB/JNI通过，40张图齐全。仅补交付记录的后续提交不改变此包的源码绑定。下一步等待开哥真机反馈；SDK第二/四/五项具体待办按本批说明继续处理，未经新指令不修改SDK。

下文保留2026-10-28及更早历史；旧的main冻结/未推送说法仅属于其原日期。

> 2026-10-28 最新状态：当前分支 `codex/coach-v2`，+40 运行源码 `428c5f3db4a90907889a2fa3e0eb9633b38a48b0`。开发者日志与 SDK 场景澄清修复已接通，本机验证及内测 APK 已交付；开哥认可基础功能已调通。main / release/1.0 保持不动、未推送；本轮未装机。当前事实见[版本台账](version-management.md)、[本轮阶段说明](coach-v2-plus40-2026-10-28.md)、[验收记录](acceptance.md)与[开发者日志说明](developer-logging-2026-10-28.md)。

## 当前交接：+40（2026-10-28）

+39 基线为 `43f8ff17faa5098a0ff00107040f7ca56e38d5f2`；本阶段日志提交为 `5a1e25405f799bc8835a2d54fc9225dde6d45dfc`，+40 / SDK 接入提交为 `428c5f3db4a90907889a2fa3e0eb9633b38a48b0`。三包 `ugk_coach`、`ugk_coach_ui`、`ugk_trainer` 统一固定 SDK commit `1532f0825b93777139be0e92e715ebec144a73b9`，当前仍是候选 commit 依赖。

本阶段开发者日志读取真实版本与构建号，工具记录沿用 SDK 事件名并带参数和结果摘要；`set_params` 完整保留 `name/value/source/quote`。每轮保存用户原话，点“新对话”前另存 `exportSession` 快照，最近 5 份轮转。以上只写开发者日志，API Key 和请求头不写入，具体见[开发者日志说明](developer-logging-2026-10-28.md)。

| 验证 / 交付 | 本会话已确认事实 |
| --- | --- |
| 自动化 | 全量 571 项通过、0 跳过；静态分析 0 问题；严格锁文件检查通过 |
| APK | `SmartFit-coach-v2-0.1.0+40-428c5f3-internal-arm64-v8a-release.apk`；143,468,166 B（136.82 MiB），internal arm64 release |
| SHA-256 | `6b634f1292363ce798738667aa9a7dcd1a08e3854c2f6bfa8a032e2bf308d74c` |
| 版本 / 包检查 | 实际 APK aapt：`0.1.0` / `2040`；签名同 +39，16KB 对齐、native ELF 与存储 JNI 检查通过 |
| 真实模型 | 首轮显示“想在哪拉伸臀部？家里、办公室还是健身房？”，5,808 ms / 2 次调用；回答“在家”后推荐，4,885 ms / 3 次调用；合计 10,693 ms / 5 次调用，无错；scene 为 `home/user/在家` |

上述执行结果沿用本会话先前记录，本次文档收尾未重跑、未重读原始日志、APK 或密钥。本机模型测试版本来自 `apk_aapt`，不是设备日志。本轮无可用 ADB 设备，未执行保留数据覆盖安装，未新增浅深 Raster P99、长时间训练或 iOS 验证。

开哥最新反馈“很好我觉得基础版本功能可用了 算是调通了”，记为基础功能认可；不扩大为真机性能通过或合并、推送、上架授权。main 保持 `7344df22744feb2550f8d989bebd154c6d1ec9c5`，release/1.0 保持 `6c786c08450d5a988db32af025ef0a1f8f5ae331`；后续继续等开哥安排。

## 当前角色与约束

- 本机维护主线，负责 Android 开发、版本决策与交付；合并、推送和发布仍以用户本次明确授权为准。云端 Hark 只在明确指派时辅助，走 feature 分支与 PR，不直接推 main。
- 参考仓库 `mhgd3250905/3D-Pose-Hub`、`mhgd3250905/HipLab` 只读，禁止写入、push 或开 PR / issue；本阶段不修改 SDK。
- 保留 Blender Studio Snow（CC BY 4.0）素材署名。公开仓库不提交密钥、token、keystore、`local.properties`、APK / build 产物。
- 当前明确指定的 `codex/coach-v2` 及 main / release/1.0 冻结约束，优先于下方旧交接中的 `feat/*`、每里程碑打 tag 等一般规则；这些旧规则不构成本次合并、推送或打 tag 授权。

## +34 下载接入记录（2026-10-26，历史）

2026-10-26 的阶段状态：+32 扁平 main（06ea39d）保持不动；独立分支 +34 已接通 SDK v3 与按动作下载，内测出包及边界见[当时记录](posehub-on-demand-v3-2026-10-26.md)。以下为 +32 阶段及更早历史，状态和数字只适用于各自时点；持续有效的角色、署名和敏感物约束以顶部说明为准。

## 历史扁平候选（2026-10-26，当时待真机验收）

- App 候选为 `0.1.0+32`，分支 `feat/solid-surfaces-20261026`；扁平视觉基线为 `353f146b42a434d999e83912fe3e1147422a787e`。
- 正式依赖：`ugk_trainer-v0.3.1` 与 `ugk_coach_ui-v0.2.1`，均指向 `c6e261e75dc8647ccc2767bc253af664957c516b`；coach 保持 `ugk_coach-v0.5.0`。
- 保留页面结构、功能、星尘、A2 青绿以及透明人物出框；卡片、顶栏、底栏、输入、建议、弹层使用三档不透明实色表面。
- `packed_alpha.frag` 及其透明视频合成路径是播放功能，必须保留；本轮不接入或替换 219 素材。
- 本轮不改 App `main` 或 `release/1.0`；原有聊天、保存计划、训练记录、设备身份及其他用户数据不清空。
- 全库 `flutter analyze --no-pub` 为 0 问题；截图测试通过，已生成[首页/对话浅深预览与底部细节](../../deliveries/flat-release-20261026/screenshots-v2)。这些图来自实际 Flutter widget 渲染，不是真机截图，不证明安装、性能或设备验收已完成。
- 当前指定红米不可连接；安装、真机 Raster P99 与持续训练待实际采集。包体及对照变化以 `deliveries/flat-release-20261026/release-apk.json` 构建回执为准，旧 APK 的历史数字不代表本候选。
- 最终按 120Hz 的 8.33ms 预算检验计划卡滚动、长聊天、进页、底部切换与训练播放，浅深分别采集；逐帧原始整数微秒计算 P99，并报告超预算帧数。

退役的实验文档、报告和旧图已按原字节移出候选，原文与 SHA-256 见 [历史证据归档清单](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。下方历史记录只描述各自时点，不代表本候选重新通过了那些检查。

## 历史主线接入（2026-10-24，已批准合入并推送）

开哥已批准功能源码 `7f3458dabbf8db4d5c65297d72bccc77eeed8c86` 合入并推送 main：coach 0.4.1 / trainer 0.2.1 正式 tag、询问气泡与 `ugk_coach_ui 0.1.0` 迁移完成。先发布 SDK 两个 tag（均固定 `f0ea064`），再从正式 GitHub 远端以全新 Git 缓存验证 App 严格锁文件，最后合入 App。后续只改发布状态文档。`release/1.0` 保持 `6c786c0`；App 版本不变，未安装或上传新包。接口与验证见[本轮记录](coach-ui-integration-2026-10-24.md)。以下为历史交付快照。

## 历史交接入口（2026-10-23，+15 用户确认通过并保存）

开哥已反馈本次 +15 测试通过，并要求先保存版本、对齐文档和台账。运行源码固定 `15079e6fc57be7c1e0d5b6c5f876784f183ce63e`；保存标签为本地 `smartfit-v0.1.0+15-internal-verified`，分支 `feat/voice-aac-comparison`。internal arm64 APK 49,384,327B，SHA-256 `6ecdc72d0fb48c8b179e288009cfe8279a50be4bef1391ee7dfdedebf48249fb`；本次核对文件身份，沿用该源码的 298 测试、3 项 Python 测试及三 ABI JNI 门禁结果，不重建用户已测包。详见[本轮验收](acceptance.md)、[版本台账](version-management.md)及[版本保存记录](reports/version-save-0.1.0+15-2026-10-23.json)。

该版本包含全量 AAC-LC、内测运行日志、Android 存储 JNI 与失败写入缓存修复；旧 +13/+14 存储缺陷证据见 [Android 存储修复](android-storage-jni-fix-2026-10-23.md)。App 两项依赖仍固定 SDK `f684e02f38e652633c23fa8946a53d02b6aa3ea2`（coach 0.3.3 / trainer 0.1.6），不把它写成 SDK 当前主线 HEAD。本次只完成本地版本保存，App 本地 main 仍为 `94d78cee9550dfbf470c7140e3729260d9b79f2d` / +12，未合并或推送。连续 >20 分钟训练和 iOS 验收仍单列待办；用户的一般通过反馈不补写量化测试数据。

## +14 运行日志阶段（2026-10-23，历史，已由 +15 替代）

`feat/voice-aac-comparison` 已完成全量 695 段 AAC-LC 与 `0.1.0+14` 内测运行日志：设置里可保存 JSON 到手机文件；记录 AI/本地路由、请求与回退、素材、训练和语音关键节点。arm64 internal release 为 49,384,327B。全量 291 测试通过，后续日志关联修正的相关 29 项通过，分析 0 issue；网页实际生成 AI 计划并导出日志通过。没有手机可继续验收，Android 实际保存/iOS 与 20 分钟训练仍待验。详见 [运行日志交付](internal-runtime-logs-2026-10-23.md) 与 [语音交付](voice-lc32-release-2026-10-22.md)。本分支尚未合并/推送，等待开哥确认；下方为历史阶段记录。

## PR #5 交接记录（2026-10-22，历史，已修复审核并合 main）

计划卡展开精简与共享元素动画已合 main：最终已测 head `f92cbc936a123b77bc43d2a23987d928596eaefd`，合并提交 `172366c6527d999b7817d97fe386e442f70f0e20`，两者文件树完全一致。标题按收起按钮实际宽度让位，隐藏卡片隔离键盘焦点；253 项测试、分析 0 issue、严格锁文件、Web release / Android debug 构建及正式浏览器交互通过。GitHub review 为 APPROVED。保持 SDK 0.3.3 与无顶部栏界面，没有新交付 APK、设备安装或 Worker 请求；先前交付包不包含本次计划卡优化。下一步等待开哥安排，证据见 [PR #5 审核记录](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。

## SDK 0.3.3 接入（2026-10-21，历史交付）

`feat/coach-033-speed@3388bd1` 已经开哥批准，以 `f80db2804d6cb9791817463cd1cd5250b32a0e84` 合入并推送 App main，合并树与验收分支相同。SDK ref 固定 main `fc5e456c44d76b872eb812597ffb5f67bc66bce3`，版本按新任务为 `0.1.0+9`，包含无顶部栏界面。运行源码 `158f4ac0d2cf7bfed0ac37d63ec6bd66eb0e5537`；完整 237 项测试、分析 0 问题。SDK 已在 SmartFit 实际 AI 链路完成的完整六条经源码和原始哈希核验后复用，180.430 秒、74,130 token、无回落。逐条记录、源码适用边界与日志见 [0.3.3 报告](coach-033-smoke-2026-10-21.md)。合并后仅同步文档，不重复冒烟或构建；本次未将真机已装的 `+10` 降级。

## PR #4 界面主线（2026-10-21，0.1.0+9，历史交付）

[PR #4](https://github.com/mhgd3250905/Sport-Helper/pull/4) 已按开哥授权审核、修复并以 `561ea8cc69efa38d07c03169c257e8fa4116bc72` 合入 main；合并树与最终 PR head `67d1a731281ea5b865e6d5fd2fb2253e0a464795` 完全一致。已测运行源码 `829381ffa19b737a6c146c8c73b33394937665b1`，237 测试、分析 0 issue、Web/Android 构建及浏览器深浅色交互通过，APK 为 `0.1.0+9`。保留 SDK 0.3.2 门禁、取消/进度、记忆存储和 `TrainerPlayer`，旧本地播放器原型未搬回。大字体溢出已修复，设备帧率/热量未新增实测。包身份及截图见 [审核记录](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)；后续可安装 +9 APK 体验。

## SDK 0.3.2 接入阶段（0.1.0+8，历史）

2026-10-21 开哥明确批准后，`feat/smartfit-coach-032@f0ebafc6257347e62533d98fb5d57f0706ddf6e9` 已以 `ebb0840f479acdf0bdc8a46e41f30eff055a0c1b` 合入 main，版本 `0.1.0+8`，合并树与审核分支一致；已推送 origin/main 并核对远端一致。两项 SDK ref 保持 `b26e4fda807b6ef3db15a61ba30c67fb51dce5e1`，运行源码、224 项测试与 APK 仍绑定 `b39304488e964b22a65501363a15140b5d0ca235`。六条新交互及独立严格动作卡补验通过，原臀桥合法文字导致的脚本断言失败 / exit 1 保留；本次不重新冒烟或改写数据。详见 [0.3.2 记录](coach-032-smoke-2026-10-21.md)。

SDK 默认 100 步、单次 60 秒、整轮 360 秒、每步最多 4 次重试、30 秒慢提示；客户端 `maxRetries=0`，App 外保护 390 秒。新增 `retrying` 序号进度、`contextTooLong` 的整理上下文提示和 `slow`「还在想…」。最终回落区分 `AgentFailureKind` 三类和 `AgentStalled`，保留「预设方案」与 typed 卡片门禁，内部异常不显示。

记忆逐条等待持久化成功后才确认，已确认事实在之后取消/reset 时保留；未确认的迟到保存由 SDK 补偿。`clearMemory()` 保存失败会抛错，不能先提示已清除。关闭和清除保留当前聊天，隔离验证须新对话。六条指定问题和补充卡片证据已独立完成，并已获准合入 App main；已核对远端 main 合并结果。版本和包身份由 [版本台账](version-management.md) 与 [验收记录](acceptance.md) 维护。

## 上一阶段 Skill Agent（0.1.0+7，未单独合并，功能随 +8 入主线）

以下保留 `+7` 当时的源码、参数与验收，不描述当前 `+8`。其中「SDK 待合 main」和 App 待审批均是历史时点；`+7` 未独立合并，其功能已随 `+8` 进入 main。

当前开发分支 `feat/smartfit-skill-agent`，功能开发版本 `0.1.0+7`，接入基线为 SDK main `1f8be6e` 的 `ugk_coach 0.3.0`。`AiChatEngine` 将长期会话入口从 `CoachSession` 换为 `CoachAgent`，保留 `CoachTurnResult` 和 typed 卡片交付；SDK 内部按需读取 skill 文件，调用 `check_plan` 后经门禁交付 `show_actions` / `show_plan`。`maxSteps` 使用默认 10，记账穷举处理新增的 `CallOutcome.toolStep`。

BaseURL、模型、App Key 与设备标识规则沿用上一阶段：`https://api.uuugk.win/v1`、`deepseek-v4-flash-0731`，只发送 `X-App-Key` / `X-Device-Id`，无 `Authorization`；密钥仅由 `--dart-define=SMARTFIT_AI_TOKEN` 注入。每次 HTTP 超时 120 秒且不重试，门禁最多重交 2 次；整轮保护超时提高到 1230 秒，以容纳多步请求。等待时禁用重复发送、可取消，并按 `agent.events` 的 `reading` / `checking` 分别显示「正在查动作库」/「正在核对计划」。取消结果不显示，关闭界面保留会话，「新对话」取消并 `reset()`。

本机记忆由 App 的 `LocalUserMemoryStore` 实现 `UserMemoryStore.load/save`，整表保存在独立键 `smartfit.ai-memory.v1`，不与设备 UUID、聊天和计划混存。`enableUserMemory` 默认开；设置页「AI 记忆」开关持久化并即时同步 Agent，关闭后不再读取或新增记忆，原记忆保留。「清除记忆」调用 SDK `clearMemory()` 后复读本机存储确认已空；保存或清除失败须提示重试，不能假称成功。开关和清除保留当前聊天与已保存计划；验证关闭后不再引用本机记忆时，先开「新对话」隔离旧消息与 App 已解析条件。记忆开启时，其摘要会随 AI 请求发送。

纯文字使用 SDK 接纳后的文字结果显示气泡，动作卡和计划卡分别只接 `ValidatedActions` / `ValidatedPlan`，保存或交给 `ugk_trainer` 的流程不变；持久化卡片恢复时重新过门禁。模型原始输出、未接纳工具参数与中间读取结果不得进入渲染层。失败继续回落原有本地模板并标「预设方案」，模板同样经门禁；每轮 `CoachContext` 继续带用户水平、时长、保护部位及场景/器械。AI 目录仍来自实际随包 93 个动作。

首次真实 Worker 暴露 SDK 的 `reasoning_content` 续传缺口及响应缺失/null 时也需空字段的协议边界，当时在 SDK 独立分支 `fix/coach-agent-reasoning-replay` 修复并推送 `43dfef637144a1e08b5eda5ed743db0671ba5a8d`。SDK coach 304 项、trainer 126 项测试和两包分析通过；App `5743073691547d44aec891ab6d4a45b5b3fa381b` 当时固定该 commit，217 项测试、分析与锁文件检查通过。App 和 pub 缓存不改 SDK 代码。六类真实 Worker 核心验证在该阶段通过（前三按关闭记忆行为等价复用，后三在 `43dfef6` 实测），记录见 [历史多步验证](coach-agent-smoke-2026-10-21.md)；当时两仓修复均待审批，现状以顶部 `+8` 入口为准。

`+7` 当时完成分组验证后等待两仓批准。现 SDK 0.3.2 已进入 main，App 的这些功能也随独立完成终验的 `+8` 合入；不把旧待办套用为当前审批状态。各历史包身份及证据继续由 [版本台账](version-management.md) 与 [验收记录](acceptance.md) 维护。

## 上一阶段工具会话接入（0.1.0+6，历史）

以下保留该阶段交接状态与验证证据，不代表 `+7` Skill Agent 已通过或已合并。

当前主线 `main`（原开发分支 `feat/smartfit-coach-tools`），功能开发版本 `0.1.0+6`。`ugk_coach 0.2.0` 与 `ugk_trainer 0.1.4` 的 git 依赖都固定到 SDK main commit `09a392bc0b736e6a23eef71d55d86108660e0e59`。App 改用 SDK README 的 `CoachSession` 工具会话接口，取代旧 `CoachAssistant.ask()` JSON 信封聊天。本轮不修改 SDK 代码或 pub 缓存，不在 App 复制、内嵌或 patch SDK。

BaseURL `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`。App Key 只通过 `--dart-define=SMARTFIT_AI_TOKEN` 注入，沿用原设备 UUID；SDK `UgkWorkerAuth` 只发送 `X-App-Key` / `X-Device-Id`，无 `Authorization`。UUIDv4 首次持久化成功才启用 AI，配置缺失或标识存储失败使用本地引擎。服务器执行每设备 30 次 / 10 分钟限流。

`AiChatEngine` 在 App 生命周期内长期持有一个 `CoachSession`；关闭 AI 界面不清会话，「新对话」取消请求并调用 `reset()`。等待时禁用发送，重复调用由 SDK 返回 `busy`；显示等待态和取消入口，用户主动取消或 reset 作废的结果不显示。首轮出计划可能 75–120 秒，单次 HTTP 超时 120 秒、HTTP 重试 0 次；门禁最多要求重交 2 次，整轮保护超时 365 秒。

纯文字进气泡，`show_actions` 仅以 `ValidatedActions` 显示动作卡并打开本地动作详情；`show_plan` 仅以 `ValidatedPlan` 显示可保存、可由 `ugk_trainer` 开练的计划卡。模型原始输出不得进渲染层，本地持久化卡片恢复时重过 SDK 门禁。断网、超时、限流或门禁最终失败回落原有 `RuleChatEngine` / `TemplatePlanGenerator` 并标「预设方案」；模板计划同样经 `admitTemplate`，不合格不显示计划卡。

profile 使用 SDK `09a392b` 的 smartfit，随包 `assets/coach/smartfit.json` 与上游一致；AI 目录由 SDK `DrillPackAdapter` 从实际 93 个随包动作构造，profile 备注中的全库 142 动作不代表 App 全部可用。每轮 `CoachContext` 带已知用户水平、时长、保护部位及场景/器械；水平和时长冲突会打回模型重交。请求发送当前输入、本轮条件、用户明确采用的当前计划与该会话模型历史（含工具调用与门禁反馈）；本地操作消息、已存计划列表和训练历史不自动上传。

本次分析、App 测试、打包及模拟器 Worker 冷烟的结果由 [版本台账](version-management.md) 与 [验收记录](acceptance.md) 记录，尚未完成的检查不能标通过。本轮用户无可用真机，不写真机通过结论；模拟器已分别完成一次 `show_actions` 和一次 `show_plan` 的 Worker 首轮冷烟；核心功能链路已验，用户后续安装 APK 做真实问答体验。旧 `+5` 等真机记录只作历史证据。2026-10-21 开哥已授权合并推送，功能以 `f83642e` 合入 `main`，合并树与已验分支完全一致。后续只需跟进用户安装 APK 后的体验反馈。

## 上一阶段 AI 接入（0.1.0+5，历史）

下列记录描述 `+5` 的旧版 JSON 信封实现与 2026-10-21 文档收束，不代表 `+6` 工具会话或 `+7` Skill Agent 的源码与验收状态。当时开发分支 `feat/smartfit-ai-replies`，待验版本 `0.1.0+5`。BaseURL `https://api.uuugk.win/v1`、模型 `deepseek-v4-flash-0731`，沿用原 App Key 与原设备 UUID，通过 `X-App-Key` / `X-Device-Id` 发送，无 `Authorization`。随包 93 个动作的计划经严格校验后可保存和开练；断网、超时、限流或最终校验失败回退本地。旧实现上传 AI 可见相关轮次与显式当前计划/训练条件，已存计划及训练历史不自动上传。随机设备标识首次持久化成功才启用 AI，服务器执行每设备 30 次 / 10 分钟限流。

`+5` 源码 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`，6 项接口/UUID/鉴权配置测试及分析通过；旧源全量 180 项本轮未重跑。debug 包已保留数据覆盖安装，签名与旧包相同，ZIP/profile 打包检查通过。新地址通用问答通过；三次计划请求分别 43,447 / 41,589 / 41,952 ms 因上游 `tencent:AbortError` 回退本地，第三次已极简为 3 动作 / 3 分钟，新接口计划生成未通过。已提示本地模板且继续可用。429 仅自动化验证不重试与提示，没有实际刷第 31 次请求。

实际 UI 已保存旧 `+4` 接口生成的「办公室肩颈放松」10 动作原始 AI 计划，从原卡开练、暂停并于 34 活动秒提前结束；重启后已存计划 2 条、历史 4 条，原 AI 计划与部分 SessionResult 保留，原设备标识未变、前台服务已释放。2026-10-20 收尾时手机已从抽屉返回原 AI 计划卡，已保存状态可见，没有活动前台服务；这不是 2026-10-21 重新读取的设备状态。该局部流程不代表完整训练、`+5` 声音实听或新地址 AI 生成链路通过。包身份见 [版本台账](version-management.md)，观察见 [验收记录](acceptance.md)；待服务器恢复生成后再验新地址，目前不申请合并，合 main / 推送等待开哥新批准。

该次收束只对齐文档与台账。阶段基线为 `main@0a40a45859378a93450c7d89cd355909613f99d5`，收束前 HEAD 为 `4cbadb0c5be786d16694ff1e7fbd2f3cb453925c`；当时已测运行源码与 APK 仍绑定 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`，两者之间仅文档变化。验证命令与适用性见 [验收记录](acceptance.md#验证来源与源码绑定)。该次没有重新调用接口、构建、安装或推送；当时待办是代理端恢复后重验新地址计划生成。

旧 `0.1.0+4` / `cc16f530944cf4f6034365aa111528536978ecc3` 的分析及全量 180 项测试通过，旧地址实机曾约 21 秒成功生成 AI 计划，随后追问回落本地，旧包不再作为最终待验包。以下保留此前 `0.1.0+3` 主线与 `0.1.0+2` 训练接入证据。

后续分支 `fix/chat-keyboard-reopen` 与 SDK `fix/catalog-repseconds-source` 已经开哥授权依次合入并推送两仓 `main`。App `0.1.0+3`，Git 依赖固定到已发布的 SDK `9407bf3`；GitHub 全新克隆及严格锁文件解析通过。SDK 目录节奏识别 `source=repSeconds`，100 项测试及分析通过。主页键盘通过重启微信输入法服务恢复，用户手动复验正常；未保留无效 App 输入补丁。详见 [后续修复记录](ugk-trainer-integration.md#后续修复2026-10-20)。以下为已合并的 `0.1.0+2` 接入基线。

`feat/ugk-trainer-integration` 已经用户同意合入并推送 `main`，接入检查点 `04112472a1ab8f07cebc1e7feb00604a56796b56`，当前 App 版本 `0.1.0+2`。SDK 修复 `ea00ff7` 已先合入并推送其 `main`，远端依赖可获取；迁移、验证范围与发布记录见 [接入记录](ugk-trainer-integration.md)。Android 16 真机同一包自然跑完 7 动作、每项 2 组、696 活动秒；出声、后台/锁屏、暂停、保存/重启读取、服务释放通过，见 [真机记录](trainer-device-check-2026-10-20.md)。通知可见性、其他系统中断与 Play Console 声明仍待处理。下段版本与交付说明保留的是上一阶段 M7 状态。

上一阶段 M7 记录：当时源码里程碑 `m7-aesthetic-v2`，PR #1、#2、#3 均已合并；App 包版本为 `0.1.0+1`，动作包 1.1.0、公共包 1.0.0。当前版本状态以 [版本管理与台账](version-management.md) 为准，验证结果与未通过项以 [本机验收记录](acceptance.md) 为准。

该阶段的 M7 Android debug 测试包已本地交付，用户已取包，当时个人远程验证结果待反馈；未上传、未公开发布，也未在该阶段再次安装手机。release 尚无成功交付记录，正式签名与完整真机验收保持待办，不能标记 `m3-local-verified`。下列引述按时间保存阶段记录；文末 M1/M2 路径、旧待办和“当前 main”只描述原始交接时点。

## 阶段记录（历史）

> 美学 v2 检查点（2026-10-20）：PR #3 已合入 `main@a5997ef`，里程碑 `m7-aesthetic-v2`。对话入口、共享控件与动效统一，93 个动作均有浅色媒体；动作包版本 1.1.0，公共包 1.0.0。五项审核意见全部修复并复验：静态分析 0 issue、144 项测试、5 项独立复现/无障碍检查、资源校验 0 errors、Web release 与 Android debug 构建通过。合并树与审核源 `7ef80d7` 完全一致，详见 [PR #3 本机审核记录](pr3-local-review.md)。本次没有更新手机；真机媒体、系统中断与 release 验收继续待办。

> 输入与设备检查点（2026-10-19）：`m6-input-focus` 修复对话输入框上下留白点不到的问题，新增 4 项回归，全量 102 项测试及 Web release / Android debug 构建通过；已覆盖安装到小米 Android 16，用户确认输入测试通过。目前手机为搜狗输入法，USB 调试保持连接。完整媒体、系统中断及 release 验收仍见 [acceptance.md](acceptance.md)。

> 最新本机复验（2026-10-19）：PR #1 已合入 main（`adafcf9`，`m4-drill-packs`）；PR #2 已改 base 为 main，本机修复安全入口、保存复用约束与小屏交互后，98 项测试、截图检查及 Web release / Android debug 构建通过。见 [PR #2 审核记录](pr2-local-review.md) 和 [验收记录](acceptance.md)。下文保留各阶段历史；Android 真机与 release 签名尚未验收，`m3-local-verified` 未打。

> 动作包迁移记录（2026-10-19）：动作库、视频、语音已改为「动作小包」`assets/packs/<id>/`，`assets/library/exercises.json`、`assets/drill_media/`、`assets/voice/` 及 `tools/library/build_library.py` 已移除。格式见 [drill-pack-spec.md](drill-pack-spec.md)，语音审计见 [voice-audit-2026-10-19.md](voice-audit-2026-10-19.md)。下文路径为旧结构。

> Web 复验更新（2026-10-19）：检查点 `m3-web-qa`，本机 Web release 构建成功，静态分析无问题，38 项测试通过。已修复不适短语漏识别、旧推断目标残留、手动换动作绕过器械/保护条件校验及横屏详情溢出。浏览器验证主流程、真实音频播放、暂停、提前结束与存储。Web 仍只显示视频封面，中文字体首次加载可能联网；Android 完整验收继续待办，详见 [acceptance.md](acceptance.md)。

> 本机接手更新（2026-10-19）：已从 `6c2c1d3` 开始推进；本机 Flutter 3.44.7 / Dart 3.12.2 静态分析无问题，修复后 31 项测试通过。修复提前结束误记全部完成、暂停未冻结视频及暂停跳过的历史记录边界，补齐真实语音时序测试。检查点 `m3-local-tests`；真机未连接，模拟器和 release 构建因系统可用提交内存不足失败，尚未产出 APK。完整记录与待验清单见 [acceptance.md](acceptance.md)；`m3-local-verified` 仍待完整验收。下文保留原始交接记录。

## 原始 M1/M2 交接存档

> 交接日期：2026-10-19 · 交出方：Hark 云端沙盒 · 接手方：用户本机（从此为 **main 主线**）
> 仓库：https://github.com/mhgd3250905/Sport-Helper · 交接时 `main` = `b386d03` · 当时 tags：`m1-core`、`m2-voice-docs`

## 0. 角色与分工（从本次交接起生效）

- **本机 = 主线**：负责 Android 开发推进、项目管理、版本决策、合并 `main`、打包发版。
- 云端 Hark 不再主动推进本仓库开发；之后只在用户明确指派时做辅助任务（调研、素材处理、文档等），且一律走 **feature 分支 + PR**，不直接推 `main`。
- 参考仓库 **只读**：`mhgd3250905/3D-Pose-Hub`、`mhgd3250905/HipLab` —— 只能读取、复制素材/代码，**禁止写入、push、开 PR/issue**。复制过来的文件头已注明来源。

## 1. 产品目标

- MVP：用户描述训练场景 → 按固定模板生成训练计划 → 展示训练小组（预渲染动作视频）→ 进入跟练（计时 / 组×次数 / 休息 / 换侧 / 语音播报）。
- 进阶：接入 AI/Agent，用动作库做 Skill/提示词，输出结构化训练计划（模型由用户后续决定，尚未接入）。

## 2. 已确认的决策

| 项 | 决定 |
|---|---|
| 技术栈 | Flutter，Android 先行（iOS 同代码库，暂不做） |
| 首发场景 | 居家、办公室 |
| 器械 | 徒手、弹力带、哑铃（另有椅子/墙/垫子/瑜伽砖作为环境器械） |
| 素材 | Pose-Hub 固定版本 + 用户 Drive 已渲染素材（已授权使用） |
| AI | MVP 不接模型，保留 `PlanGenerator` 接口；模型以后由用户定 |
| App 名 / 包名 | 智能健身助手 / `com.ugk.smartfit`（与 `com.ugk.hiplab` 同族） |
| 发布 | 不上架、不花钱；完全离线、无账号 |
| 版本管理 | 每个成果节点 commit + tag（`mN-xxx`） |

## 3. 交接时完成度（M1 + M2，历史）

- **动作库 93 个**（`assets/library/exercises.json`，生成文件）
  - 46 个：Pose-Hub v0.2.0 深色成片（经 HipLab 冻结版本）
  - 47 个：用户 Drive 素材文件夹的绿幕母版，本仓库抠像到同色背景（力量类主要在这批）
  - 视频 `assets/drill_media/sf-<id>.mp4/.jpg`（720²，共约 11 MB）
- **模板 13 套**（`assets/library/templates.json`）：工位肩颈腰放松、工位 10 分钟激活、晨起唤醒、睡前放松、居家徒手全身、哑铃全身力量、弹力带上肢与体态、核心强化、臀腿强化、开胯灵活、久坐后链激活、运动前热身、运动后拉伸
- **领域层**：场景描述匹配（规则）→ `TemplatePlanGenerator` → `PlanValidator`（规则见 `docs/plan-schema.md`）→ 会话引擎（绝对时钟，阶段化）
- **语音**：预生成中文语音 270 条（`assets/voice/zh/` + `manifest.json`），edge-tts 生成
- **UI**：安全确认 → 首页/场景描述 → 模板 → 训练计划（训练小组）→ 跟练（准备/训练/休息）→ 动作库 → 关于（含 CC BY 署名）
- 截图：[旧图索引](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)

## 4. 代码地图

```
lib/domain/   exercise / plan(TrainingPlan v1) / template / scenario / plan_generator / plan_validator / session
lib/voice/    session_script（台词时间线）、session_runner；queue/library/controller/just_audio_output 复制自 HipLab
lib/core/     媒体 WebView 播放器 + 本地资源服务器、存储、屏幕常亮（复制自 HipLab）
lib/data/     app_store、library 加载、models
lib/ui/       各页面
lib/app/      services 装配
tools/library build_library.py / build_templates.py（重新生成动作库与模板）
tools/media   prepare_media.py（Pose-Hub 成片转码 / 绿幕抠像）
tools/voice   build_voice.py（edge-tts；.cache 已 gitignore）
tools/        pose-hub.lock.json / manifest / pose_hub_sync.py（素材版本锁）
test/         domain_test.dart、app_flow_test.dart
docs/         assessment（评估报告）、plan-schema、screenshots、本文件
```

## 5. 本机接手步骤

```bash
git clone https://github.com/mhgd3250905/Sport-Helper.git && cd Sport-Helper
flutter --version        # 需 Dart ≥ 3.12（沙盒用 Flutter 3.47.6；HipLab 的 3.44.7 也兼容）
flutter pub get
flutter analyze          # 沙盒结果：No issues found
flutter test             # ⚠ 沙盒(aarch64)测试宿主崩溃无法运行，请在本机首跑并确认
flutter run              # 真机/模拟器走一遍主流程
flutter build apk --release
```

首次验收建议路径：安全确认 → 输入「办公室 10 分钟放松肩颈」看匹配 → 选「哑铃全身力量」看训练小组 → 进入跟练，检查视频封面→首帧切换、计时、组×次数、休息、换侧、语音 → 动作库翻看力量类视频 → 关于页署名。

## 6. 交接时问题 / 待办（历史，不代表当前状态）

**P0（本机首日）**
1. 在本机跑 `flutter test`，修掉真实失败（沙盒从未成功运行过测试）。
2. 真机走查主流程，尤其 WebView 本地视频播放与语音时序。
3. README 引用了 `docs/acceptance.md`，该文件尚不存在 —— 补一份验收清单或删掉引用。

**P1**
4. Release 签名：`android/app/build.gradle.kts` 的 release 仍用 debug 签名。新建 keystore + `key.properties`（已 gitignore，**不要提交**，仓库是公开的）。
5. 动作元数据不完整（难度、剂量、要领、禁忌、体位）—— 影响模板质量和后续 AI。
6. 场景描述匹配目前是关键词规则，覆盖面有限。
7. Drive 素材里还有未纳入的动作（久坐强化、托马斯专项、肌群训练等子目录），按需扩充；不要把大 zip 进仓库。

**P2 / 进阶**
8. AI 接入：实现 `lib/domain/plan_generator.dart` 中的 `AiPlanGenerator`，输出 TrainingPlan v1，必须过 `PlanValidator`，失败回落模板。评估报告建议 Cloudflare Worker 代理 + 候选动作预过滤（模型待用户定）。
9. 语音合规：edge-tts 商用条款不明，正式发布前换 Azure Speech 等官方服务。
10. iOS 适配（同代码库，暂缓）。

## 7. 素材与许可

- 人物派生自 Blender Studio Snow（**CC BY 4.0**），署名在 `assets/licenses/Drill-media-ATTRIBUTION.md`，App「关于」页展示，勿删。
- 用户 Drive 素材文件夹：`https://drive.google.com/drive/folders/1SYZ1Ww3LRpMX4MZOSZeV6gpWl0Tc7fJe`（已设为知道链接可查看），内含 `catalog.json`、`动作目录.csv`、各分类子目录。
- 项目交接 Drive 文件夹「项目交接/智能健身助手」（父目录 id `1xUjS4-W4TfxmxYl9zcCzY5EcW4wRT5yM`）。

## 8. 约定

- 分支：`main` 由本机主线维护；功能走 `feat/*`，完成后合并。
- 每个里程碑 commit + tag，下一个建议 `m3-local-verified`（本机测试与真机验收通过后）。
- 公开仓库：不提交密钥、token、keystore、`local.properties`、APK/build 产物。
- 生成文件（exercises.json、templates.json、voice manifest）改动应通过 `tools/` 脚本再生成，不手改。
