# 智能健身助手（SmartFit）交接说明

## 当前交接入口（2026-10-21 工具会话接入）

当前主线 `main`（原开发分支 `feat/smartfit-coach-tools`），功能开发版本 `0.1.0+6`。`ugk_coach 0.2.0` 与 `ugk_trainer 0.1.4` 的 git 依赖都固定到 SDK main commit `09a392bc0b736e6a23eef71d55d86108660e0e59`。App 改用 SDK README 的 `CoachSession` 工具会话接口，取代旧 `CoachAssistant.ask()` JSON 信封聊天。本轮不修改 SDK 代码或 pub 缓存，不在 App 复制、内嵌或 patch SDK。

BaseURL `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`。App Key 只通过 `--dart-define=SMARTFIT_AI_TOKEN` 注入，沿用原设备 UUID；SDK `UgkWorkerAuth` 只发送 `X-App-Key` / `X-Device-Id`，无 `Authorization`。UUIDv4 首次持久化成功才启用 AI，配置缺失或标识存储失败使用本地引擎。服务器执行每设备 30 次 / 10 分钟限流。

`AiChatEngine` 在 App 生命周期内长期持有一个 `CoachSession`；关闭 AI 界面不清会话，「新对话」取消请求并调用 `reset()`。等待时禁用发送，重复调用由 SDK 返回 `busy`；显示等待态和取消入口，用户主动取消或 reset 作废的结果不显示。首轮出计划可能 75–120 秒，单次 HTTP 超时 120 秒、HTTP 重试 0 次；门禁最多要求重交 2 次，整轮保护超时 365 秒。

纯文字进气泡，`show_actions` 仅以 `ValidatedActions` 显示动作卡并打开本地动作详情；`show_plan` 仅以 `ValidatedPlan` 显示可保存、可由 `ugk_trainer` 开练的计划卡。模型原始输出不得进渲染层，本地持久化卡片恢复时重过 SDK 门禁。断网、超时、限流或门禁最终失败回落原有 `RuleChatEngine` / `TemplatePlanGenerator` 并标「预设方案」；模板计划同样经 `admitTemplate`，不合格不显示计划卡。

profile 使用 SDK `09a392b` 的 smartfit，随包 `assets/coach/smartfit.json` 与上游一致；AI 目录由 SDK `DrillPackAdapter` 从实际 93 个随包动作构造，profile 备注中的全库 142 动作不代表 App 全部可用。每轮 `CoachContext` 带已知用户水平、时长、保护部位及场景/器械；水平和时长冲突会打回模型重交。请求发送当前输入、本轮条件、用户明确采用的当前计划与该会话模型历史（含工具调用与门禁反馈）；本地操作消息、已存计划列表和训练历史不自动上传。

本次分析、App 测试、打包及模拟器 Worker 冷烟的结果由 [版本台账](version-management.md) 与 [验收记录](acceptance.md) 记录，尚未完成的检查不能标通过。本轮用户无可用真机，不写真机通过结论；模拟器已分别完成一次 `show_actions` 和一次 `show_plan` 的 Worker 首轮冷烟；核心功能链路已验，用户后续安装 APK 做真实问答体验。旧 `+5` 等真机记录只作历史证据。2026-10-21 开哥已授权合并推送，功能以 `f83642e` 合入 `main`，合并树与已验分支完全一致。后续只需跟进用户安装 APK 后的体验反馈。

## 上一阶段 AI 接入（0.1.0+5，历史）

下列记录描述 `+5` 的旧版 JSON 信封实现与 2026-10-21 文档收束，不代表当前 `+6` 工具会话的源码或验收状态。当时开发分支 `feat/smartfit-ai-replies`，待验版本 `0.1.0+5`。BaseURL `https://api.uuugk.win/v1`、模型 `deepseek-v4-flash-0731`，沿用原 App Key 与原设备 UUID，通过 `X-App-Key` / `X-Device-Id` 发送，无 `Authorization`。随包 93 个动作的计划经严格校验后可保存和开练；断网、超时、限流或最终校验失败回退本地。旧实现上传 AI 可见相关轮次与显式当前计划/训练条件，已存计划及训练历史不自动上传。随机设备标识首次持久化成功才启用 AI，服务器执行每设备 30 次 / 10 分钟限流。

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
- 截图：`docs/screenshots/01–10`

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
