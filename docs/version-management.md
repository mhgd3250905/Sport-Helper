# 版本管理与台账

## 当前 +45 生成卡 v2 候选（2026-10-29）

App `codex/task-bubble-v2` / `0.1.0+45`，预期 internal arm64 2045，基于已验收合入并推送的 main `94e924fe287770f56d4e8ceeedd521e2871267da`。+44 留给独立 `codex/guide-lite`，没有互相合入。SDK 三包、coach override 与整份 pubspec.lock 均保持 b490eec43b408a8a35ce81a7830833bc6a3ff278。实际打包提交、版本、签名、16KB、SHA256 和软件截图以独立目录 `E:/AII-3D/3D-Sport-AI/deliveries/task-bubble-v2-plus45/` 的源码绑定回执为准，见[本轮记录](task-bubble-v2-plus45-2026-10-29.md)。候选只作本地提交，不合并、不推送、不打 tag；main、release/1.0 和 SDK 仓库不动。下方为原时点历史记录。

## 当前 +43 计划讨论候选（2026-10-29）

App `codex/plan-focus` / `0.1.0+43`，基于 +42 `d90054902c1cb850f246ecfad100af81b0f31bad`，尚未合并或推送。三包与 coach override 固定 `b490eec43b408a8a35ce81a7830833bc6a3ff278`，仅六个 SDK 锁引用值变化。发到对话导入完整 SDK focus；SDK 管理讨论与修改；App 支持重启、更新原记录、另存和旧 sdkVersion 数据迁移。详见[本轮记录](plan-focus-plus43-2026-10-29.md)。

internal arm64 实际 2043、最终源 SHA/APK 哈希及门禁以 `E:/AII-3D/3D-Sport-AI/deliveries/plan-focus-plus43/release-apk.json` 与 `package-metadata.json` 为准；测试、真实接口、软件截图分别留存，不据此认定真机验收完成。main 为 `31fd3f0b0741175536b0a72ff2e0fc4f71b18f9f`；release/1.0 与 SDK 仓库未操作。以下为各原时点的历史记录。

## 当前 +41 验收更正与流畅度摸排（2026-10-29）

开哥确认“我的计划”两卡切换不合格；SDK475收起整卡高度为零，单卡修复按指令暂停，接口缺口已列明，不在App另写动画、不出冒称修复的release包。全App本轮只读报告，应用/SDK/测试代码未改；profile采集包源4047072、同+41/2041已备，开哥远程回传原始JSON和录屏后补实测最大值/超16ms帧数与排序。见[当前报告](ui-motion-audit-2026-10-29.md)及其接口缺口、采集步骤。下方原包测试/“已补齐”记录属于当时检查点，不代表本次单卡验收通过；App main与release/1.0不动，+42待Hark定案且+41合main后再从新main开展。

## 当前 +41 两项补齐 / SDK475（2026-10-29）

最终打包源 `9777eb4a2eed52dda173bd31e2e7f3f69d413b83`；全量611/611、0跳过，分析0问题，实际2041、同签名/16KB/JNI通过，APK143,599,186B / 136.95MiB。26张浅深原图及交互回执已核对，截图8092与打包源仅测试正文差异有Git证据。当前仅待用户远程真机确认，未合入或推送App main。

SDK远端main已核实发布475a5d8，用户授权后三包及coach传递override统一锁定完整SHA。计划列表直接接入公开CoachPlanExpanded，菜单修复沿用826ea92；同一+41/2041的最终源码、测试、APK和截图见[本轮记录](ui-polish-1-plus41-plan-expand-2026-10-29.md)与独立目录 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-plan-expand/`。下方826菜单候选、488初包及更早记录均属历史。没有真机/模拟器操作，最终等待用户远程安装确认；App main、release/1.0不动。

## 当前 +41 菜单补项（2026-10-29）

同一 `codex/ui-polish-1 / +41 / 2041` 继续修复菜单：单240ms控制器、固定面板、键盘共用占位及独立重绘边界。我的计划原地展开仍等待SDK最小公开接口授权，不能记为完成。用户无真机且明确不启动模拟器，由用户远程安装验收；当前软件验证与新APK回执见[本轮记录](ui-polish-1-plus41-menu-supplement-2026-10-29.md)。新交付独立位于 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-supplement/`；下方SDK488初包及其他旧验证均保留为历史。

## 当前同一 +41 / SDK488（2026-10-29）

App仍为 `0.1.0+41 / 2041`，分支仍为 `codex/ui-polish-1`。三包声明/锁文件和coach传递override统一固定 `488ce82b9dc7031925ba12c18f252b4e596e7776`，非SDK依赖不变。单动作preview、整套training、完成感受本地保存和日志、SDK样式归属见[补充记录](ui-polish-1-plus41-sdk488-2026-10-29.md)。新包和全部验证独立保存于 `../../deliveries/ui-polish-1-plus41-sdk488/`，不替换下方首包及旧截图；最终源码/包哈希以新目录 `release-apk.json` 为准。main仍adc79ab，release/1.0未动，+41未合main或推送。

当前SDK488验证：598/598、0跳过，analyze0问题，严格锁文件通过；58张浅深软件图和harness哈希已核对。旧的586项记录仅属于下方SDK1532首包。

最终包源 `c8c64e3868849cf24e6a917a963d50cc63a0195c`；`SmartFit-ui-polish-1-sdk488-0.1.0+41-c8c64e3-internal-arm64-v8a-release.apk`，143,533,650B / 136.88MiB，SHA256 `9fcb1da1b43fd289904bc7113f64d10956c779ae979e177f51cb64a59b3b641b`。aapt确认 `com.ugk.smartfit.internal / 0.1.0 / 2041`；与旧+41同签名、ZIP/ELF16KB和存储JNI通过，未装机。

## 历史：同批 +41 首包（2026-10-29，SDK1532基线）

`0.1.0+41` / `codex/ui-polish-1`，internal arm64 Android构建号2041；打包源码、大小、哈希及实际身份以 `../../deliveries/ui-polish-1-plus41/release-apk.json` 为准。+40 功能源 `428c5f3` 经开哥真机确认，含其后8份文档收束的 `adc79abef2b7195872e589f6225486e944b66644` 已合入并推送 main；本批从该新 main 继续。SDK 三包固定1532f082不变，`release/1.0` 未操作。+41 仍待真机确认，未合main、未推送、未打tag。详见[本批逐项交付与SDK限制](ui-polish-1-plus41-2026-10-29.md)。

本批软件验证：固定Flutter3.44.7全量586/586、0跳过，静态分析0问题、严格锁文件通过；40张浅深前后软件图及索引已保存。SDK受限的第二、四、五项不因此视为完成。

最终包源 `c6369c44c0a048d3c0ad56f4a2acbbddbc59048a`；APK `SmartFit-ui-polish-1-0.1.0+41-c6369c4-internal-arm64-v8a-release.apk`，143,468,018B / 136.82MiB，SHA256 `ed8bc9987c4cfe33367d4492a7e37edccf8df6444a2069a1fb730a4d862db1c6`。aapt确认 `com.ugk.smartfit.internal / 0.1.0 / 2041`；与+40同签名、ZIP/ELF16KB和存储JNI通过。仅供用户内部真机确认，未自动装机；后续交付文档提交不替代打包源码。

以下为2026-10-28及更早历史；其中“当前”、main冻结与未合并描述仅属于原时点。

> 2026-10-28 当前版本：`codex/coach-v2` 的 `0.1.0+40` 已出内部 release APK；开哥确认“基础版本功能可用了”“算是调通了”。确认范围仅为基础功能可用，本次未通过 ADB 覆盖安装、未新增真机量化验收，未合入或推送 main，`release/1.0` 不动。详见[本轮交付记录](coach-v2-plus40-2026-10-28.md)与[当前验收记录](acceptance.md)。

## 当前 +40 内测交付（2026-10-28）

| 项目 | 当前事实与边界 |
| --- | --- |
| App 版本 / 分支 | `0.1.0+40` / `codex/coach-v2`；前一交付 +39 功能源为 `43f8ff17faa5098a0ff00107040f7ca56e38d5f2` |
| 功能源码 | `428c5f3db4a90907889a2fa3e0eb9633b38a48b0`；本轮日志改动提交 `5a1e25405f799bc8835a2d54fc9225dde6d45dfc`，随后升级场景澄清修复并递增为 +40；文档收束提交不替代已打包功能源码 |
| SDK 固定依赖 | `ugk_coach 0.8.0`、`ugk_coach_ui 0.4.0`、`ugk_trainer 0.6.0` 三包均以完整 commit 固定 `1532f0825b93777139be0e92e715ebec144a73b9`，锁文件一致；这是 App 依赖记录，不据此声称 SDK 当前 HEAD 或正式 tag |
| 本地主线 / 发布分支 | `main` 与本地跟踪的 `origin/main` 均为 `7344df22744feb2550f8d989bebd154c6d1ec9c5`；`release/1.0` 为 `6c786c08450d5a988db32af025ef0a1f8f5ae331`；本轮均未合并或推送 |
| APK 文件 | `SmartFit-coach-v2-0.1.0+40-428c5f3-internal-arm64-v8a-release.apk` |
| 包身份 | `com.ugk.smartfit.internal`，versionName `0.1.0`、实际 versionCode `2040`，internal / arm64-v8a / release；pubspec 构建后缀为 `40`，不与 ABI 偏移后的原生构建号混写 |
| 字节数 / SHA-256 | 143,468,166B / 136.82MiB；`6b634f1292363ce798738667aa9a7dcd1a08e3854c2f6bfa8a032e2bf308d74c`；比 +39 增加 131,072B |
| 包检查 | 签名与 +39 一致；16KB 对齐与存储 JNI 门禁通过，不代表生产发布签名或真机安装完成 |
| 既有验证回执 | 本轮功能源码全量 571 项通过、0 跳过，静态分析 0 问题，严格锁文件校验通过；构建环境及详细回执见[本轮交付记录](coach-v2-plus40-2026-10-28.md)；本次文档收束不冒充重新测试或构建 |
| 真实模型回执 | 先询问地点：5,808ms / 2 次调用；回答“在家”后推荐：4,885ms / 3 次调用；合计 10,693ms / 5 次调用，无报错；日志中的 `scene` 为 `value=home`、`source=user`、`quote=在家` |
| 用户确认 / 待验 | 2026-10-28 开哥确认“基础版本功能可用了”“算是调通了”；仅记录基础功能确认。本轮未通过 ADB 保留数据覆盖安装，未新增真机截图、Raster P99 或完整训练量化结果；不能由本次确认推断这些项目通过，也不扩大为主线合并、推送或发布授权 |

更新日期：2026-10-28（Asia/Shanghai）。当前交付以本节及[验收记录](acceptance.md)为准，交接入口见 [HANDOVER.md](HANDOVER.md)。

以下至“后续版本维护规则”前均为历史记录；其中“当前”“本轮”“待验”等措辞只属于各节标注的时点，不替代上方 +40 状态。

## 历史：反馈 r1 +35 候选（2026-10-27）

当时 +34 已确认并进入 main（`7344df2`）；`codex/feedback-r1-part1` 的 +35 候选完成 SDK / 训练接入和 B / D 设置页，211 项定向测试、静态分析通过，出包及真机结果另记；当时开哥确认前 main 和 release/1.0 不动。见[阶段记录](feedback-r1-part1-2026-10-27.md)。

## 历史：扁平 +32 候选（2026-10-26，当时待真机验收）

- App 候选为 `0.1.0+32`，分支 `feat/solid-surfaces-20261026`；扁平视觉基线为 `353f146b42a434d999e83912fe3e1147422a787e`。
- 正式依赖：`ugk_trainer-v0.3.1` 与 `ugk_coach_ui-v0.2.1`，均指向 `c6e261e75dc8647ccc2767bc253af664957c516b`；coach 保持 `ugk_coach-v0.5.0`。
- 保留页面结构、功能、星尘、A2 青绿以及透明人物出框；卡片、顶栏、底栏、输入、建议、弹层使用三档不透明实色表面。
- `packed_alpha.frag` 及其透明视频合成路径是播放功能，必须保留；本轮不接入或替换 219 素材。
- 本轮不改 App `main` 或 `release/1.0`；原有聊天、保存计划、训练记录、设备身份及其他用户数据不清空。
- 全库 `flutter analyze --no-pub` 为 0 问题；截图测试通过，已生成[首页/对话浅深预览与底部细节](../../deliveries/flat-release-20261026/screenshots-v2)。这些图来自实际 Flutter widget 渲染，不是真机截图，不证明安装、性能或设备验收已完成。
- 当前指定红米不可连接；安装、真机 Raster P99 与持续训练待实际采集。包体及对照变化以 `deliveries/flat-release-20261026/release-apk.json` 构建回执为准，旧 APK 的历史数字不代表本候选。
- 最终按 120Hz 的 8.33ms 预算检验计划卡滚动、长聊天、进页、底部切换与训练播放，浅深分别采集；逐帧原始整数微秒计算 P99，并报告超预算帧数。

退役的实验文档、报告和旧图已按原字节移出候选，原文与 SHA-256 见 [历史证据归档清单](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。下方历史记录只描述各自时点，不代表本候选重新通过了那些检查。

## 共享聊天 UI 0.1.1 补丁（2026-10-24，已批准合入并推送）

功能源码 `9d2ff7db6f598fe6cf629de02ed3c56ade660f9e` 已合入并推送 main，基于 `5b65cd7` 保留既有 iOS 提交，App 版本仍为 `0.1.0+22`。SDK 三个正式 tag：coach_ui 0.1.1、coach 0.4.2、trainer 0.2.2，均固定 `3302d6235a39e2c2b4b51fa196cc32b37c31b54c`。按批准先发布 SDK，再用隔离 Flutter 3.44.7 从正式 GitHub 严格解析且锁文件不变后合入 App；全局 3.47.8 引入的另外 5 项依赖变化未纳入本轮。本任务未写 `release/1.0`，后续提交仅发布状态文档。详见[补丁回执](coach-ui-011-2026-10-24.md)。

## SDK 与共享聊天 UI（2026-10-24，已批准合入并推送）

功能源码 `7f3458dabbf8db4d5c65297d72bccc77eeed8c86` 已合入并推送 main，App 版本仍为 `0.1.0+22`。固定 `ugk_coach-v0.4.1`、`ugk_trainer-v0.2.1`、`ugk_coach_ui-v0.1.0`；后两个 tag 已发布且均指向 SDK `f0ea0647586913b205fc6dbb75fc9f97cedc55ce`。trainer 只改依赖声明，运行代码不变。正式远端全新 Git 缓存解析及严格锁文件验证通过，后续提交仅对齐发布状态文档。未安装或上架新 App，`release/1.0` 保持原状。详见[本轮记录](coach-ui-integration-2026-10-24.md)。

历史条目原更新日期：2026-10-24（Asia/Shanghai）。以下保留当时版本、主线与交付记录，不代表当前 +40 的验收结果。

## 流畅度基线候选（2026-10-23，+16 待手机采集）

`feat/performance-baseline` 基于已验收的 +15 保存节点 `c350680`，版本 `0.1.0+16`。仅增加 internal 帧统计、页面/场景标签、设备元数据和 JSON 系统分享；SDK 两项 ref 保持 `f684e02`，未作性能修复或视觉改动。手机基线、修复后同场景对比和开哥同意后才合并推送。使用方法与最终产物核验见[性能基线报告](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)，候选原因和 SDK 边界见[静态审核](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。以下 +15 仍是最近一次用户明确验收通过的版本。

## 历史保存版本（2026-10-23，+15 用户确认通过）

开哥确认最近交付的 +15 测试通过，本次按要求先作本地版本保存并对齐台账。确认原话和证据范围见[验收记录](acceptance.md)，机器可读记录见[版本存档](reports/version-save-0.1.0+15-2026-10-23.json)。

| 项目 | 当前保存事实 |
| --- | --- |
| App 版本 / 分支 | `0.1.0+15` / `feat/voice-aac-comparison` |
| APK 运行源码 | `15079e6fc57be7c1e0d5b6c5f876784f183ce63e`；文档保存节点不冒充新的打包源码 |
| 本地保存标签 | 注释标签 `smartfit-v0.1.0+15-internal-verified`，指向文档对齐后的保存节点；已有标签不移动 |
| 本地主线 | `main@94d78cee9550dfbf470c7140e3729260d9b79f2d`，`0.1.0+12`；本次未合并或推送 |
| 固定 SDK | 两项 App ref 均为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`，coach 0.3.3 / trainer 0.1.6；不表示 SDK 当前主线 HEAD |
| 本轮功能 | 全量单声道 AAC-LC 32kbps / 22.05kHz、内测运行日志与文件导出、Android 存储 JNI keep 规则、持久化缓存修复和发布前 JNI 门禁 |
| 关于页 | `0.1.0+15 (内测)`；pubspec、关于页与日志版本已核对一致 |
| 交付包 | `.buildlog/install/SmartFit-0.1.0+15-storage-fix-internal-arm64-v8a-release.apk` |
| 实际 Android 身份 | `com.ugk.smartfit.internal`，versionName `0.1.0`，versionCode `2015`，arm64-v8a，release / 非 debuggable，minSdk 24 / targetSdk 36 |
| 字节数 / SHA-256 | 49,384,327B（49.38MB / 47.10MiB）；`6ecdc72d0fb48c8b179e288009cfe8279a50be4bef1391ee7dfdedebf48249fb` |
| 签名与产物保留 | 沿用既有开发证书、v2 校验通过；本次不重建或改写已测 APK，没有新 +15 生产交付包 |
| 既有验证 | 运行源码 Flutter 298 项、Python 3 项、分析 0 issue、严格锁文件、三 ABI 最终 DEX 门禁及媒体/语音哈希通过 |
| 用户验收 / 待办 | 本次 +15 测试由开哥确认通过；未补写量化指标，连续 >20 分钟训练与 iOS 专项仍单列待验 |

运行依赖、存储后端与用户数据未迁移或清理；+13/+14 包保留为历史，已因存储缺陷停止推荐。细节见 [Android 修复报告](android-storage-jni-fix-2026-10-23.md)。

## 上一内测候选（2026-10-23，+14 已由 +15 替代）

`feat/voice-aac-comparison` 当时为 `0.1.0+14`，internal arm64 包 `com.ugk.smartfit.internal` / versionCode `2014`，49,384,327B，SHA-256 `c26b4a3a744566c354887cc7fd7822ebf31ed0080f918bfb702b874a53885710`。增加本机运行日志后，用户日志暴露存储 JNI 混淆缺陷，现由 +15 替代；当时未合并/推送，也未交付 +14 生产包。原始核验见 [运行日志历史记录](internal-runtime-logs-2026-10-23.md)。

## PR #5 与 M7 台账快照（2026-10-22，历史）

| 项目 | 当时记录 / 事实来源 |
| --- | --- |
| 主线与合并 | 2026-10-22 按开哥授权修复并通过审核，PR #5 以 `172366c6527d999b7817d97fe386e442f70f0e20` 合入 main；合并树与已测 head 完全一致，本地已快进同步 |
| 验收分支 / 运行源码 | `feat/ui-polish@f92cbc936a123b77bc43d2a23987d928596eaefd`；计划卡展开动画、标题布局与键盘焦点修复，保留 SDK 0.3.3 和无顶部栏界面 |
| 共享训练依赖 | App main 的 `ugk_coach 0.3.3` / `ugk_trainer 0.1.4` 均固定 SDK main `fc5e456c44d76b872eb812597ffb5f67bc66bce3`。不使用 path 或分支名，不复制或 patch SDK、不修改 pub 缓存 |
| 源码里程碑 | `m7-aesthetic-v2` → `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` |
| 上一阶段文档整理前主线快照 | `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7`；后续 HEAD 由 Git 查询，不把本表固定 SHA 写成永远最新的 HEAD |
| PR #3 合并提交 | `a5997ef7aef2695b24cab3f4b330543bbb2c7027` |
| PR #3 已测源 | `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`；合并树相同，至上述主线快照只增加 3 份文档 |
| Android 身份 | `com.ugk.smartfit`，App 名「智能健身助手」 |
| 默认包版本 | 当时 main `0.1.0+9`：versionName `0.1.0`、versionCode `9`；pubspec 与关于页同步，旧 +8 等身份保留为历史 |
| 关于页版本 | `0.1.0+9 (MVP)`；独立常量见 [about_page.dart](../lib/ui/about_page.dart) |
| 资源版本 | 93 个动作包为 `1.1.0`；公共包 `_common` 为 `1.0.0`；格式版本仍为 `1`，见 [小包规范](drill-pack-spec.md) 与 [索引](../assets/packs/index.json) |
| 交付状态 | PR #5 仅编译验证，未交付或安装新 APK。此前 SDK 0.3.3 / +9 debug APK 仍为 208,043,503 bytes，不含 PR #5；未将真机已装的 UI +10 降级 |
| 验收状态 | PR #5 全量 253 测试、分析 0 issue、严格锁文件、Web/Android debug 构建及浏览器交互通过，见 [审核记录](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。AI 链路未改；此前六条 Worker 的身份与复用边界仍见 [0.3.3 报告](coach-033-smoke-2026-10-21.md) |

Git 标签、App 包版本与资源版本分别管理。`m7` 不代表 Android versionCode 为 7；该历史阶段依次为 `+1` M7、`+2` 训练接入、`+3` 目录节奏修复、`+4/+5` JSON 信封、`+6` 工具会话、`+7` 首次 Skill Agent 分支、`+8` SDK 0.3.2、`+9` UI 主线；当时尚无可交付 release 包。后续 +12/+13/+14/+15 release 以顶部当前台账及各阶段报告为准。

## SDK 0.3.3 提速接入（0.1.0+9，已合 main 并推送）

`feat/coach-033-speed@3388bd1` / 运行源码 `158f4ac0d2cf7bfed0ac37d63ec6bd66eb0e5537`；两项 SDK ref 均为 `fc5e456c44d76b872eb812597ffb5f67bc66bce3`，版本及关于页遵从本次指定 `0.1.0+9`。全量 237 项、分析 0 问题和 debug 构建通过，六条真实 Worker 复用依据与逐条耗时/token 见 [0.3.3 报告](coach-033-smoke-2026-10-21.md)。2026-10-21 开哥批准后已以 `f80db2804d6cb9791817463cd1cd5250b32a0e84` 合入并推送 main，包含无顶部栏修改；合并树与验收分支完全一致，后续仅更新文档。

APK `.buildlog/install/SmartFit-coach-0.3.3-0.1.0+9-debug.apk`，208,043,503 bytes，SHA-256 `1eb0ebb16266e335069579c6a4f6bb42e5ce88e86fa848cf0541d73938778b26`；`com.ugk.smartfit`、versionName `0.1.0`、versionCode `9`、minSdk `24`、targetSdk `36`、debuggable。由上述源码注入原本机 dart-define 构建，后续仅验收文档；独立命名，未覆盖旧 UI +9 包。真机当前已装 +10，本次未安装。

日志 `.buildlog/coach-033-full-tests.log`、`coach-033-analyze.log`、`coach-033-pub-strict.log`、`coach-033-debug-build.log`。没有重复运行已核验相同代码的 Worker，也未改 SDK 仓库或 pub 缓存。

## 顶部栏移除（0.1.0+10，UI 调整分支）

`fix/chat-without-top-bar` 按真机反馈去掉聊天顶部「新对话」栏，入口移至左下角抽屉。运行源码 `89ffa8f7bea2f42a7afd28eade9fc13b7c4ba856`；237 项测试、分析 0 issue、Android debug 构建通过。该 UI 调整现已随上方 SDK 0.3.3 一起合 main，版本按新任务为 `+9`；本节 `+10` APK 仍是原先真机交付。

APK `.buildlog/install/SmartFit-ui-no-top-bar-0.1.0+10-debug.apk`，208,029,103 bytes，SHA-256 `94e7402e3e48b262a934f78d78f560b7fbec8272c74d005d08d22a43bddd8896`；`com.ugk.smartfit`、versionName `0.1.0`、versionCode `10`、minSdk `24`、targetSdk `36`、debug。沿用现有 dart-define 构建配置，密钥不入仓库。

2026-10-21 已在连接的真机从 `+9` 覆盖升级，未清空数据；前台启动正常，截图确认顶部栏已消失、原聊天保留。新对话的取消/reset 及键盘可达性由现有回归测试覆盖。日志 `.buildlog/no-top-bar-tests.log`、`no-top-bar-analyze.log`、`no-top-bar-build.log`；真机截图仅保留在本机 `.buildlog/no-top-bar-device.png`。

## PR #4 界面阶段（0.1.0+9，PR #4 已审核合并）

| 项目 | 当前 +9 debug 包身份 |
| --- | --- |
| 源码 / 合并 | 已测 `829381ffa19b737a6c146c8c73b33394937665b1`；最终 PR head `67d1a73`；GitHub 合并 `561ea8c`，整树一致 |
| APK | [旧包身份原始记录](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |
| 字节数 / SHA-256 | 208,025,947 bytes；`46f5ffc77b64774ef7cb2ee2634d0ab3a819a4367521becca0168cba9875de16` |
| Android 身份 | `com.ugk.smartfit`，versionName `0.1.0`、versionCode `9`，minSdk `24`、targetSdk `36`，debug |
| 日志 / 审核 | 隔离副本 `.buildlog/pr4-tests-final.log`、`pr4-analyze-final.log`、`pr4-web-build.log`、`pr4-android-debug-build.log`；[审核与截图](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |
| 边界 | 大字体溢出已修复，AI/门禁和共享播放器保留；没有新增真实 Worker 或 Android 真机性能结论，旧 +8 的六条数据不改写 |

## SDK 0.3.2 接入（0.1.0+8，历史，已合入并推送 main）

沿用 SDK 默认 `maxSteps=100`、`requestTimeout=60s`、`turnTimeout=360s`、`maxRequestRetries=4`、`slowAfter=30s`；客户端 `maxRetries=0`，Agent 负责步级重试，App 外保护为 390 秒。`retrying` 显示 n/max，`contextTooLong` 的 1/1 特例显示整理上下文，`slow` 显示「还在想…」。回落区分三种 `AgentFailureKind` 和 `AgentStalled`，不渲染异常。

记忆每条等待 `save` 真正成功才确认；已确认事实在后续取消/reset 时保留，未确认的迟到写入由 SDK 补偿。清除等待 SDK `clearMemory()` 并处理抛错。预算、重试、上下文压缩及持久化契约相对旧版已改变，本轮六条问题全部重跑；阶段记录见 [0.3.2 验证](coach-032-smoke-2026-10-21.md)。

| 项目 | `+8` debug 包身份（核心已验） |
| --- | --- |
| 源码 / SDK | App `b39304488e964b22a65501363a15140b5d0ca235`；SDK main `b26e4fda807b6ef3db15a61ba30c67fb51dce5e1` |
| APK / 字节数 | `.buildlog/install/SmartFit-coach-0.3.2-0.1.0+8-debug.apk`；203,937,142 bytes |
| SHA-256 | `a8746c2a04348855dc43cd9b402a9733cc827edda1f72d7d35070bf818dee4d7` |
| Android 身份 | `com.ugk.smartfit`；versionName `0.1.0`、versionCode `8`；minSdk `24`、targetSdk `36`；debug |
| 自动化 | 224 项测试、分析 0 issue、严格锁文件与 debug 构建通过；日志 `.buildlog/coach-032-tests.log`、`coach-032-analyze.log`、`coach-032-lock-verify.log`、`coach-032-build.log` |
| 资产 / Worker | 1,167 条 pack entries 无缺失。六条新交互为 39 步 / 43 请求 / 384,013 token，无回落；原脚本无卡断言失败保留。独立 show_actions 为 4 步 / 4 请求 / 72.908 秒 / 20,109 token，通过严格断言，无重试/slow/回落 |
| 合并 | 2026-10-21 开哥授权，`f0ebafc` 以 `ebb0840` 合 main；整树相同，已推送 origin/main 并核对远端一致 |

## 首次 Skill Agent（0.1.0+7，历史分支未单独合并，功能随 +8 入主线）

以下保留 `+7` 当时的参数、源码、APK 与分组验证及待批状态；它未单独合 main，功能现已随 `+8` 进入主线。旧记录不代替 `+8` 的六条全新验证。

SDK 默认 `maxSteps=10`，每次 HTTP 超时 120 秒且不重试，App 整轮保护超时 1230 秒。新增 `reading` / `checking` 进度与本机 `UserMemoryStore`，记忆独立键为 `smartfit.ai-memory.v1`，开关持久化；关闭和清除保留当前对话，关闭后的隔离验证需显式新对话。`ValidatedActions` / `ValidatedPlan` 门禁、取消与本地「预设方案」边界保持。

该阶段 SDK `43dfef637144a1e08b5eda5ed743db0671ba5a8d` 在独立分支通过 coach 304 项、trainer 126 项测试及两包分析。前版 `712cb7b` 的前三轮关闭记忆案例通过，但第四轮漏记条件，因此仅加强记忆开启指令，并按关闭记忆 system/tools SHA 未变复用前三轮。`43dfef6` 的实际本机记忆、后续参考及关闭隔离三轮通过。App `5743073691547d44aec891ab6d4a45b5b3fa381b` 的依赖检查、217 项测试、分析和 debug 构建通过；历史结果见 [验收记录](acceptance.md) 与 [首次真实 Worker 验证](coach-agent-smoke-2026-10-21.md)。这些分组证据只属于 `+7`；当前 `+8` 已另行完成全新终验并获准合 main。

| 项目 | 历史 `+7` debug 包身份 |
| --- | --- |
| 源码 / SDK | App `5743073691547d44aec891ab6d4a45b5b3fa381b`；SDK 临时修复 commit `43dfef637144a1e08b5eda5ed743db0671ba5a8d` |
| APK | `.buildlog/install/SmartFit-skill-agent-0.1.0+7-debug.apk`，229,903,158 bytes，本机保留 |
| SHA-256 | `9d35b899e59b60f613f65d230431f1c4f0368da07b8c0f61a79daebed0946e19` |
| Android 身份 | `com.ugk.smartfit`；versionName `0.1.0`、versionCode `7`；minSdk `24`、targetSdk `36`；debug |
| 自动化 / 构建日志 | `.buildlog/skill-agent-43-tests.log`（217 项）、`skill-agent-43-analyze.log`（0 issue）、`skill-agent-43-lock-verify.log`（严格锁文件通过）、`skill-agent-43-build.log`（debug 构建成功） |
| 验收边界 | 当时六类真实 Worker 核心验证通过，前三按等价复用、后三在 `43dfef6` 实测；无当时真机或完整训练结论。`+7` 未独立合并，其功能现随 `+8` 入 main；旧审批待办仅属历史 |

### 推理字段第二版修复阶段（`712cb7b`，历史）

| 项目 | 第二版阶段记录 |
| --- | --- |
| 源码 / SDK | App `a7cfe04550c8c8cac867b105470d66c96744858d`；SDK `712cb7b3d636a5314c5aa08211c822928a0af4f4` |
| 历史 APK | `.buildlog/install/SmartFit-skill-agent-712cb7b-0.1.0+7-debug.apk`，229,902,535 bytes |
| SHA-256 | `2f513b380d9ba091c989fd5dff79bbded45f947b70ef36d185970c23d9b8cca8` |
| 自动化 | App 217 项、分析 0 issue、严格锁文件与 debug 构建通过（`.buildlog/skill-agent-712-*.log`）；SDK coach 299 项、trainer 126 项及两包分析 0 issue |
| Worker 边界 | 前三轮关闭记忆请求通过；第四轮未记忆稳定事实，本机记忆为空，未完成全部六轮。前三轮按当前提交关闭记忆系统/工具 SHA 不变复用，旧 APK 不是当前交付包 |

### 第一版 SDK 修复阶段（`029af4a`，历史）

以下为第一版修复的自动化及构建记录，不是当前 `43dfef6` 的最终包或通过结论。更早基线 ref 的 215 项全量与 28 项定向仅作开发阶段证据，测试数不叠加。

| 项目 | 第一版 `+7` debug 包身份 |
| --- | --- |
| 源码 / SDK | App `0a8fada86b504964551bc58f8854837162210e6c`；SDK 临时修复 commit `029af4a1e735b5f1c3f1ee5cef6c82aad8a1c3f4` |
| APK | 已另名保存 `.buildlog/install/SmartFit-skill-agent-029af4a-0.1.0+7-debug.apk`，203,909,858 bytes；仅作第一版历史包 |
| SHA-256 | `35b07c8ae6b59a82d9bb6f2883999143841ed17fec0dd4da7294114ef2b7b326` |
| Android 身份 | `com.ugk.smartfit`；versionName `0.1.0`、versionCode `7`；minSdk `24`、targetSdk `36`；debug |
| 自动化 / 构建日志 | `.buildlog/skill-agent-final-tests.log`（217 项）、`skill-agent-final-analyze.log`（0 issue）、`skill-agent-fixed-lock-verify.log`（严格锁文件通过）、`skill-agent-debug-build.log`（debug 构建成功） |
| SDK 验证 | 第一版 coach 291 项、trainer 126 项及两包分析 0 issue；不代替第二版的验证 |
| 验收边界 | 核心计划曾通过，臀桥后续仍遇上游空推理字段要求，未跑通全部六轮；本 APK 与摘要不代表当前修复的终验包，无真机或完整训练通过结论 |

## 工具会话版本（0.1.0+6，历史已验）

| 项目 | 记录 |
| --- | --- |
| 源码 | `9e94bb513751def6306f8e63313050efd632ccb9`；后续文档提交不改变该运行源码 |
| SDK 依赖 / 合并 | `ugk_coach 0.2.0` / `ugk_trainer 0.1.4` 固定 SDK main `09a392bc0b736e6a23eef71d55d86108660e0e59`；经开哥授权以 `f83642eb06260c22cb891931acc02ce908ad538d` 合入 App main，合并树与已验分支一致 |
| APK | `.buildlog/install/SmartFit-coach-tools-0.1.0+6-debug.apk`，229,742,403 bytes |
| SHA-256 | `7469c492cdc400ba2648dfb837394334ce6c6a507f12c3019d2cce26f787e59b` |
| 自动化 / 构建 | `flutter test --no-pub` 195 项通过；`flutter analyze --no-pub` 无问题；debug 构建成功 |
| Worker | API35 模拟器，两个新 SDK 会话各首轮请求：动作卡 22.5 秒、计划卡 32.4 秒，均通过门禁，未发生重交或回落；不推断服务端物理冷启动 |
| 验收边界 | 按用户后续确认，本阶段只验本次 SDK 新功能跑通，核心链路通过；实际问答体验由用户安装 APK 后继续测试。完整真机/训练/声音不在本轮结论内，2026-10-21 已获开哥授权合并推送，后续跟进 APK 体验反馈 |

## AI 阶段本地收束（2026-10-21，历史）

本阶段基线为 `main@0a40a45859378a93450c7d89cd355909613f99d5`，是接入 AI 前已记录的主线起点；Preflight HEAD 为 `4cbadb0c5be786d16694ff1e7fbd2f3cb453925c`，祖先关系已核对。范围内 4 个提交依次为 `6fa4c0c`、`cc16f53`、`e549e0f`、`4cbadb0`，涉及 20 条路径（文档 5、运行 Dart 9、profile 1、包配置 1、测试 3、构建脚本 1），均为本会话 AI 接入成果；完整工作区状态为空。

`e549e0f84aa9118ef20752b8926c7b8c602a7e0f` 标识已测运行源码和 `+5` 包来源，收束前 HEAD 另含 5 份文档更新；两者不混写为同一提交。当前收束只修正文档，复用证据的命令、日期和源码绑定见 [验收记录](acceptance.md#验证来源与源码绑定)。既有 APK 与设备结果保留为对应包的历史观察，本次未重新构建、安装或调用接口。

当时确定的文档分工：本台账管理版本和包身份，`acceptance.md` 管理验证结果与边界，`chat-home.md` 说明对话行为，`HANDOVER.md` 顶部汇总下一步。该次仅文档收束，没有重新验证新地址计划生成，也没有该阶段推送授权；这是 `+5` 历史边界，后续 `+6/+7` 的验证与批准状态见各自记录。

## AI 新接口待验版本（0.1.0+5）

| 项目 | 记录 |
| --- | --- |
| 配置 | BaseURL `https://api.uuugk.win/v1`；模型 `deepseek-v4-flash-0731` |
| 鉴权 / 设备 | 沿用原 App Key 与原 UUID 的 `X-App-Key` + `X-Device-Id`；无 `Authorization` |
| 源码 | `e549e0f84aa9118ef20752b8926c7b8c602a7e0f` |
| APK | `.buildlog/install/SmartFit-ai-proxy-0.1.0+5-debug.apk`，203,741,474 bytes |
| SHA-256 | `f3ac1f4276f82c629bb254065d5bc3108d4181a5531679fed7a7d2f90d2a14a4` |
| 包检查 / 安装 | debug 签名与旧包相同，ZIP/profile 打包通过；已保留旧数据覆盖安装 |
| 自动化 | 6 项 endpoint/UUID/header 配置测试及分析通过；旧源全量 180 项本轮未重跑 |
| 真机观察 | 通用问答 `outcome=model`，27,722 ms、HTTP 请求 1 次；三次计划请求 43,447 / 41,589 / 41,952 ms 后回退本地，均报 `all upstreams failed (tencent:AbortError)`；第三次为极简 3 动作 / 3 分钟、HTTP 请求 1 次，新接口计划生成未通过 |
| 局部 UI 流程 | 保存旧 `+4` 原始 AI 计划，已存计划 1→2；原卡启动、视频/倒计时、暂停及 34 活动秒提前结束已观察，历史 3→4。重启后原计划及部分 SessionResult 保留，设备标识未变、前台服务释放 |
| 验证边界 | 局部流程不代表新地址 AI 生成链路、完整训练或 `+5` 声音实听通过。本地回退已提示且继续可用；未刷第 31 次请求，仅自动化覆盖 429 无重试与提示 |
| 构建 | `tools/coach/build_debug.ps1 -AppKeyFile '<本机 App Key 文件绝对路径>'`，只以 dart-define 注入 App Key |
| 未完成 | 待服务器恢复计划生成后重验新地址；目前不申请合并，合 main / 推送等待开哥新批准；通知、Play Console、正式签名与其余设备验收仍待办 |

## 旧 AI Worker 测试包（0.1.0+4，历史）

| 项目 | 记录 |
| --- | --- |
| 文件 | `.buildlog/install/SmartFit-ai-worker-0.1.0+4-final-debug.apk`，本机忽略目录保存；名称含 final，但已不是当前最终待验包 |
| 源码 / 版本 | `cc16f530944cf4f6034365aa111528536978ecc3`，分支 `feat/smartfit-ai-replies`；`com.ugk.smartfit`，`0.1.0+4`，debug |
| 大小 / SHA-256 | 229,561,107 bytes；`e2fcb4d54fd10fa7d0d7a10783d751aafb197fbd4285f653a64eaae3f4533446` |
| 自动化 | 该旧源全量 180 项测试、静态分析通过；不作为 `+5` 验证 |
| 配置 | Worker `https://ugk-ai-proxy.294851575.workers.dev/v1`；模型 `deepseek-v4.1-flash-1017`；`X-App-Key` + `X-Device-Id`，无 `Authorization` |
| 真机历史 | 旧地址曾约 21 秒成功生成 AI 计划，随后追问回落本地；服务调整中，现须验证新地址 |

## ugk_trainer 测试包（真机主链路已验）

| 项目 | 记录 |
| --- | --- |
| 文件 | `.buildlog/install/SmartFit-ugk-trainer-0.1.0+2-debug.apk`，本地忽略目录保存，并已覆盖安装到 Android 16 真机 |
| 大小 / 身份 | 203,720,356 bytes；`com.ugk.smartfit`，versionName `0.1.0`、versionCode `2`；minSdk 24、targetSdk 36；三 ABI |
| SHA-256 | `7fd8c50b521090dd9bf60e2a332f266729c44bdab3e10936ff6de8e7bb4d24fd` |
| SDK 固定提交 | `ea00ff7f2a4b7f46274b70708a45b435f269f993`，已合入 SDK main 并推送，远端可获取，见 [接入记录](ugk-trainer-integration.md) |
| 验证 | debug 签名与旧包一致，ZIP/静音素材/通知图标及单份媒体播放服务和权限检查通过 |
| 真机结果 / 未完成 | 一轮自然完成 7/7、696 活动秒；出声/锁屏/后台/暂停/完成保存/重启读取/服务释放通过。通知可见性及其他系统中断未验；Play Console 声明草稿未提交。代码已经用户同意合入并推送 main |

## 源码里程碑台账

日期按标签所指提交的时间换算为 Asia/Shanghai；完整 SHA 指向 commit，而不是 annotated tag 对象。

| 日期 | 标签 | Commit SHA | 成果与验证边界 |
| --- | --- | --- | --- |
| 2026-10-19 | `m1-core` | `6ed0399c0fea3d6f687240f172725cbf6fc70fef` | MVP 动作库、模板、生成器、会话与 UI；不据此认定本机或真机验收通过 |
| 2026-10-19 | `m2-voice-docs` | `b386d032563a94049ce99a48a49e67051896d691` | 早期中文语音与文档；语音数量和资源路径属于迁移前状态 |
| 2026-10-19 | `m3-local-tests` | `7b500abe075dfe7c264d0cf5a4e54d807f3f80dc` | 本机分析、31 项测试通过；当时 release 与真机未通过 |
| 2026-10-19 | `m3-web-qa` | `4e45b7e7aa23f0952bd463b3f85da51e8a0c5417` | 38 项测试、Web release 和浏览器走查；Web 视频仍为海报 |
| 2026-10-19 | `m4-drill-packs` | `adafcf9f1fac259ddc2d5f8b1f8898fa6078c897` | PR #1，93 个动作包与公共包、695 条语音；44 项测试、语音审计及 Web release / Android debug 构建通过 |
| 2026-10-19 | `m5-chat-home` | `3ae70c61170326039d70f303310da36268c3e3a1` | PR #2，对话首页、计划保存复用与视觉；98 项测试及本机构建通过，完整真机验收待办 |
| 2026-10-19 | `m6-input-focus` | `6d4eb30fd16172f393d152225d2c725a63f84ad0` | 输入点击区域修复；102 项测试及本机构建通过，小米 Android 16 安装启动与输入获用户确认 |
| 2026-10-20 | `m7-aesthetic-v2` | `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` | PR #3，统一控件、动效与浅色媒体；144 项测试、5 项独立检查、资源校验及本机构建通过；完整设备验收待办 |

以上标签均已核对指向，且其 commit 均为文档整理前主线快照的祖先。`m3-local-verified` 尚未创建，须待完整设备与 release 验收通过。本次文档提交沿用 M7 里程碑，不另造发布标签。

## M7 历史交付包台账

| 项目 | 记录 |
| --- | --- |
| 文件 | `SmartFit-m7-d0b1c7e-debug.apk`，仅本机忽略目录 `.buildlog/install/` 保存 |
| 用途 | 用户个人远程测试验证；已取包，未收到本包测试通过反馈 |
| 类型 / 大小 | Android debug，多 ABI（arm64-v8a、armeabi-v7a、x86_64）；228,341,715 bytes |
| 包身份 | `com.ugk.smartfit`，versionName `0.1.0`，versionCode `1`；minSdk 24、targetSdk 36 |
| 构建来源 | PR #3 已测源 `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`；与 `m7-aesthetic-v2` 的运行源码、资源及配置一致，文件名中的主线 SHA 仅标识对应检查点 |
| 文件 SHA-256 | `adde572a760e425a0c45779b6d4337eb4d8fdcf1ba59b8e12967913c4e8a10ec` |
| 签名证书 SHA-256 | `3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`；与旧版相同的本机 debug 证书，可覆盖安装 |
| 既有包检查 | ZIP 完整性通过；1167 个小包文件与源一致，含 94 份 manifest、93 组深色和 93 组浅色视频/封面、695 条语音；签名校验通过 |
| 未完成项 | 无可交付 release APK；`release` 配置仍使用 debug 签名；未将此包记作真机已验收 |

包摘要及检查结果是 2026-10-20 上一阶段本地交付时的记录，不代表当前 HEAD 重新构建或重新安装该 M7 包。该阶段文档收束未读取构建产物、未重跑构建或上传 APK；当前训练接入包单独记录在上方台账。后续替换文件必须重新记录身份、摘要和验证结果，不能沿用本行摘要。

## M7 历史验证证据与源码绑定

2026-10-20 本机审核在固定源 `7ef80d75331a150b6a258ef3ba0c27832fd1e54b` 完成，来源为上一阶段 [PR #3 本机审核记录](pr3-local-review.md)。

| 命令 / 观察 | 记录结果 | 适用范围 |
| --- | --- | --- |
| `flutter pub get --offline` | 成功，pub.dev，lock 未变 | 固定审核源 |
| `flutter analyze --no-pub` | 0 issue | 固定审核源；至 M7 文档提交 `e8981ee` 仅文档变更，不能泛化到后续训练接入代码 |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 144 项通过 | 同上；不代替设备实测 |
| `python tools/packs/validate_packs.py` | 0 errors | 同上；93 个动作包、公共包与 695 条语音 |
| 独立媒体复现 / 无障碍检查 | 2 + 3 项通过 | 固定审核源上的补充检查；不计入 144 项常规测试 |
| Web release / Android debug 构建 | 上一阶段记录成功 | 固定审核源上的构建观察；原记录未完整列出构建参数，本次不冒充当前 HEAD 的新构建证据 |
| `git diff --name-status 7ef80d75331a150b6a258ef3ba0c27832fd1e54b..d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` | 仅 `docs/HANDOVER.md`、`docs/acceptance.md`、`docs/pr3-local-review.md` | 上一阶段 Preflight 重新核对，说明当时已有运行源码验证为何仍适用 |

PR #3 合并提交与已测源的树均为 `029a952876a816ffa72f28def688cd62ba34b1d1`。该阶段文档整理期间核对运行源码与配置无差异，并校验文档链接、标签指向、版本字段及差异格式，没有因文档变化重复全量 Flutter 测试。这是 M7 的历史范围；训练接入使用当前上方记录的 156 项测试及独立真机证据。

## 后续版本维护规则

1. 本机维护主线、审核合并与打包；云端仅在明确指派时使用 `feat/*` + PR。3D-Pose-Hub、HipLab 保持只读。
2. 新功能里程碑使用独立 commit + `mN-xxx` 标签；已有标签不移动。文档对齐不自动新增里程碑、公开发布或标记验收通过。
3. 后续新交付包递增 Android versionCode；在 `pubspec.yaml` 维护默认 `versionName+构建后缀`，若通过 `--build-name` / `--build-number` 覆盖，必须在包台账记实际值和命令。split APK 的实际 versionCode 含 ABI 偏移，应以原生包身份为准。关于页、运行日志头及启动日志统一通过 `AppBuildInfo` / `PackageInfo` 读取实际 versionName 和 buildNumber，不维护独立版本常量；读取失败记 `unknown`。
4. 每次交付记录源码 SHA、构建命令及环境、包名、版本、类型、ABI、大小、SHA-256、签名类型、交付方式和待验边界；记录的是实际产物，不以分支名、标签或文件名推断包身份。
5. 覆盖安装前核对包名、签名和版本兼容性，保留用户数据。正式 keystore 仅在本机管理，切换证书须另行安排迁移，不能把现有 debug 证书记为正式签名。
6. 动作包版本按 [小包规范 §6](drill-pack-spec.md#6-版本规则) 更新；生成内容通过 `tools/` 重建并校验，不手改生成的文件清单与索引。
7. 新验证结果先写验收记录，再更新本台账的状态和交接入口。APK、build 产物、密钥、keystore、`local.properties` 不入 Git；Snow CC BY 4.0 署名保留。
8. 用户明确要求保存版本时可创建本地注释标签。既有 `smartfit-v0.1.0+15-internal-verified` 仅记录 +15 的历史内测交付与用户确认，不代替生产发布、专项验收或主线合并；本轮 +40 文档收束不新增标签，推送另按当次授权执行。

查询当前主线、里程碑和本台账最近提交：

```bash
git rev-parse HEAD
git rev-parse 'm7-aesthetic-v2^{commit}'
git log -1 --format='%H %s' -- docs/version-management.md
git status --porcelain=v1 --untracked-files=all
```
