# 版本管理与台账

更新日期：2026-10-21（Asia/Shanghai）。本文件是源码里程碑、App 包版本与交付包身份的统一台账；验收证据及待验清单以 [acceptance.md](acceptance.md) 为准，角色与历史交接见 [HANDOVER.md](HANDOVER.md)。

## 当前版本

| 项目 | 当前事实 / 事实来源 |
| --- | --- |
| 主线与合并 | 本机维护 `main`；PR #1、#2、#3、`feat/ugk-trainer-integration` 及工具会话 `feat/smartfit-coach-tools` 已合入并推送。当前 `+7` Skill Agent 分支尚未合并，核心验证已通过，待开哥同意 |
| 当前开发状态 / 运行源码 | 开发分支 `feat/smartfit-skill-agent`，功能开发版本 `0.1.0+7`，当前运行源码 `5743073691547d44aec891ab6d4a45b5b3fa381b`，固定 SDK 记忆指令修复 `43dfef6`。前版 `a7cfe04` / SDK `712cb7b` 与更早 `0a8fada` / SDK `029af4a` 均单独保留阶段历史 |
| 共享训练依赖 | `ugk_coach 0.3.0` / `ugk_trainer 0.1.4` 当前临时固定 SDK 修复分支 commit `43dfef637144a1e08b5eda5ed743db0671ba5a8d`，已推送 `fix/coach-agent-reasoning-replay`。该提交在推理字段续传修复上，仅增强记忆开启时的系统指令；关闭记忆时三份 profile 的系统/工具 SHA 与 `712cb7b` 一致，循环、传输、存储未改。SDK main 当前为 `1d1aad86f516bd7121cc73c71d623043f1042dc3`（新增文档提交），未合入修复。临时引用按 SDK 修改规则第 4 条执行，App 合 main 前须改为已获准合入 SDK main 的具体 commit。App 不复制、内嵌或 patch SDK，不修改 pub 缓存 |
| 源码里程碑 | `m7-aesthetic-v2` → `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` |
| 上一阶段文档整理前主线快照 | `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7`；后续 HEAD 由 Git 查询，不把本表固定 SHA 写成永远最新的 HEAD |
| PR #3 合并提交 | `a5997ef7aef2695b24cab3f4b330543bbb2c7027` |
| PR #3 已测源 | `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`；合并树相同，至上述主线快照只增加 3 份文档 |
| Android 身份 | `com.ugk.smartfit`，App 名「智能健身助手」 |
| 默认包版本 | Skill Agent 开发版本 `0.1.0+7`：versionName `0.1.0`、versionCode `7`；`pubspec.yaml` 与关于页同步。旧 `+6` 工具会话、`+2` 完整训练包各有独立历史身份 |
| 关于页版本 | `0.1.0+7 (MVP)`；独立常量见 [about_page.dart](../lib/ui/about_page.dart)，尚未自动读取包版本 |
| 资源版本 | 93 个动作包为 `1.1.0`；公共包 `_common` 为 `1.0.0`；格式版本仍为 `1`，见 [小包规范](drill-pack-spec.md) 与 [索引](../assets/packs/index.json) |
| 交付状态 | SDK `43dfef6` 对应的 `+7` debug APK 已重建并在本机保留，当前身份见下表；`712cb7b` / `029af4a` 旧包另名归档。真实 Worker 核心验证通过；无本轮真机或完整训练通过结论 |
| 验收状态 | SDK `43dfef6`：coach 304 项、trainer 126 项测试及两包分析 0 issue，通过并已推送修复分支。App `5743073` 的全量 217 项、分析 0 issue、严格锁文件检查与 debug 构建均通过。前三轮关闭记忆案例按与 `712cb7b` 的等价性复用，当前记忆写入、后续参考及关闭后隔离三轮通过，六类核心功能通过、最终采用的六条记录均无回落，逐轮记录见 [本轮 Worker 记录](coach-agent-smoke-2026-10-21.md) |

Git 标签、App 包版本与资源版本分别管理。`m7` 不代表 Android versionCode 为 7；此前为 `+1` M7、`+2` 训练接入、`+3` 目录节奏修复、`+4` 旧 AI 地址、`+5` 新地址 JSON 信封测试、`+6` 工具会话；当前 Skill Agent 开发版本为 `0.1.0+7`。没有形成可交付 release 包。

## Skill Agent 开发版本（0.1.0+7，核心功能通过，待合并）

SDK 默认 `maxSteps=10`，每次 HTTP 超时 120 秒且不重试，App 整轮保护超时 1230 秒。新增 `reading` / `checking` 进度与本机 `UserMemoryStore`，记忆独立键为 `smartfit.ai-memory.v1`，开关持久化；关闭和清除保留当前对话，关闭后的隔离验证需显式新对话。`ValidatedActions` / `ValidatedPlan` 门禁、取消与本地「预设方案」边界保持。

当前 SDK `43dfef637144a1e08b5eda5ed743db0671ba5a8d` 已在独立分支通过 coach 304 项、trainer 126 项测试，两包分析均 0 issue 并已推送。前版 `712cb7b` 的前三轮关闭记忆案例通过，但开启记忆的第四轮未调用 `remember`、本机记忆仍空，因此仅加强记忆开启时的系统指令；记忆关闭的三份 profile 系统/工具 SHA 未变，前三轮真实证据按此等价性复用。当前 `43dfef6` 的「新手、家里有哑铃」已真实写入本机并确认，后续参考和关闭后隔离两轮也通过。App `5743073691547d44aec891ab6d4a45b5b3fa381b` 的依赖检查、217 项全量测试、分析和 debug 构建已通过；完整真实结果及分组复验依据见 [验收记录](acceptance.md) 与 [首次真实 Worker 验证](coach-agent-smoke-2026-10-21.md) 更新。通过后仍须开哥同意，才能先将 SDK 修复合入其 main，再使 App ref 指向 SDK main 上的具体 commit，并完成 App 合并推送。

| 项目 | 当前 `+7` debug 包身份 |
| --- | --- |
| 源码 / SDK | App `5743073691547d44aec891ab6d4a45b5b3fa381b`；SDK 临时修复 commit `43dfef637144a1e08b5eda5ed743db0671ba5a8d` |
| APK | `.buildlog/install/SmartFit-skill-agent-0.1.0+7-debug.apk`，229,903,158 bytes，本机保留 |
| SHA-256 | `9d35b899e59b60f613f65d230431f1c4f0368da07b8c0f61a79daebed0946e19` |
| Android 身份 | `com.ugk.smartfit`；versionName `0.1.0`、versionCode `7`；minSdk `24`、targetSdk `36`；debug |
| 自动化 / 构建日志 | `.buildlog/skill-agent-43-tests.log`（217 项）、`skill-agent-43-analyze.log`（0 issue）、`skill-agent-43-lock-verify.log`（严格锁文件通过）、`skill-agent-43-build.log`（debug 构建成功） |
| 验收边界 | 六类真实 Worker 核心验证通过，前三按关闭记忆等价复用、后三在当前 SDK 实测；无本轮真机或完整训练结论；SDK 与 App 尚未获准合 main |

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
3. 后续新交付包递增 Android versionCode；在 `pubspec.yaml` 维护默认 `versionName+versionCode`，若通过 `--build-name` / `--build-number` 覆盖，必须在包台账记实际值和命令。关于页独立版本常量需同步核对。
4. 每次交付记录源码 SHA、构建命令及环境、包名、版本、类型、ABI、大小、SHA-256、签名类型、交付方式和待验边界；记录的是实际产物，不以分支名、标签或文件名推断包身份。
5. 覆盖安装前核对包名、签名和版本兼容性，保留用户数据。正式 keystore 仅在本机管理，切换证书须另行安排迁移，不能把现有 debug 证书记为正式签名。
6. 动作包版本按 [小包规范 §6](drill-pack-spec.md#6-版本规则) 更新；生成内容通过 `tools/` 重建并校验，不手改生成的文件清单与索引。
7. 新验证结果先写验收记录，再更新本台账的状态和交接入口。APK、build 产物、密钥、keystore、`local.properties` 不入 Git；Snow CC BY 4.0 署名保留。

查询当前主线、里程碑和本台账最近提交：

```bash
git rev-parse HEAD
git rev-parse 'm7-aesthetic-v2^{commit}'
git log -1 --format='%H %s' -- docs/version-management.md
git status --porcelain=v1 --untracked-files=all
```
