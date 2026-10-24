# 智能健身助手 SmartFit

2026-10-25 播放按钮动画待验：训练页改用 SDK 独立 `UgkPlayPauseButton`，保留原尺寸和配色，加入可中断图标形变、中心色波、按压弹回和减少动态分支。内测 `0.1.0+26`，固定新 `ugk_trainer-v0.2.7`，与切换闪烁和首帧对齐修复一起真机复测。见[本轮记录](docs/play-pause-button-2026-10-25.md)。

2026-10-25 首帧衔接待验：训练待播图改用同主题、同一视频解码出的第 0 帧，消除另选关键姿势图与视频起播的跳变；聊天与列表封面保留。内测 `0.1.0+25`，SDK 保持 `ugk_trainer-v0.2.6`。仅验证相关改动，不跑全量；见[首帧修复说明](docs/playback-first-frame-2026-10-25.md)。

2026-10-24 复测修订待验：在 `14684cd` 上把详情改为“训练图文”，默认静帧、手动播放/暂停、出屏暂停和右下“前往训练”；首页滚动内容延伸进透明状态栏，训练下一动作移左上、暂停按钮改用红色，并修复快速切换动作时播放器占位闪烁。内测 `0.1.0+24`，固定新 `ugk_trainer-v0.2.6` 与 `ugk_coach_ui-v0.1.2`，仍等待开哥真机确认后合 main。见[修订说明与回执入口](docs/phone-feedback-followup-2026-10-24.md)。

2026-10-24 真机反馈第 1 批待验：动作示范改为 App 动作浅深两套随包离线播放，主题静帧/视频一致；详情改为分段卡片流且中央卡单独播放；Android 全局透明状态栏与安全区同步。内测 `0.1.0+23`，固定新 `ugk_trainer-v0.2.4`，App 全量 460 通过 / 13 原有条件跳过。两个 main 等开哥真机确认，见[根因、素材与待验记录](docs/phone-feedback-batch1-2026-10-24.md)。

2026-10-24 待审：AI 会话与询问状态改由 SDK 纯 Dart `CoachConversationController` 管理，SmartFit 先接入。拟固定 `ugk_coach-v0.5.0` 与依赖兼容的 `ugk_trainer-v0.2.3`，UI 保持 `ugk_coach_ui-v0.1.1`。全量 454 项通过 / 13 原有条件跳过，分析无问题；隔离候选 Git 严格锁文件校验通过，正式发布与远端校验等开哥同意。见[本轮待审回执](docs/coach-conversation-controller-2026-10-24.md)。

2026-10-24 已批准合入并推送补丁，功能源码 `9d2ff7db6f598fe6cf629de02ed3c56ade660f9e`：固定 `ugk_coach_ui-v0.1.1`、`ugk_coach-v0.4.2`、`ugk_trainer-v0.2.2`（均为 SDK `3302d62`），修复套路剂量溢出与中文 Windows Git 包解析。先核对指定 SDK 回归已通过、发布正式 tag，再用原验收 Flutter 3.44.7 从 GitHub 严格验证锁文件后合入 App；锁文件未变化，已有 iOS 更新保留。本任务未写 `release/1.0`。见[补丁验收与发布回执](docs/coach-ui-011-2026-10-24.md)。

2026-10-24 已经开哥批准，将功能源码 `7f3458dabbf8db4d5c65297d72bccc77eeed8c86` 合入并推送 main：SDK tag 升级、`ask_user` 多轮澄清及聊天 UI 下沉完成。固定 coach 0.4.1、trainer 0.2.1、coach_ui 0.1.0 三个正式 tag，从 GitHub 重新验证严格锁文件通过；接口、验证及发布回执见[本轮接入记录](docs/coach-ui-integration-2026-10-24.md)。后续只对齐发布状态文档，`release/1.0` 保持原状。

描述训练场景 → AI 回复与生成规范训练计划（异常时回退本地模板）→ 用预渲染动作直接展示训练小组 → 跟练（计时 / 组 × 次数 / 休息 / 换侧 / 语音播报）。

主界面是一段对话（[docs/chat-home.md](docs/chat-home.md)）：说想怎么练，助手可回复文字、动作演示卡或计划卡片。动作卡点开看详情；计划卡点「开始训练」直接跟练，「保存」后下次说「上次那个」或从左下角抽屉一键开始。

- 包名 `com.ugk.smartfit`（与 `com.ugk.hiplab` 同族），App 名「智能健身助手」
- Flutter（沙盒 3.47.6 / Dart 3.13，`sdk: ^3.12.0`，与 HipLab 3.44.7 兼容），Android 先行，iOS 同代码库
- 无账号，训练记录、已保存计划和 AI 记忆保存在本机；WebView 通过本机回环地址播放内置视频。
- 启用 AI 时，当前输入、本轮训练条件、用户明确采用的当前计划和同一 `CoachAgent` 的模型对话经 `https://api.uuugk.win/v1` 发送给 AI 服务；记忆开启时也发送本机记忆摘要，另携带本机随机生成的设备标识。Agent 在一轮内按需读取动作库 skill 文件并核对计划，中间工具调用与结果会用于该轮后续请求；后续轮次只保留用户消息与最终交付。已存计划与训练历史不自动上传。服务器按每设备每 10 分钟最多 30 次请求限流；429 等可重试错误由 SDK 重试当前步骤，最终失败后提示并使用「预设方案」。断网、整轮超时或门禁最终失败同样使用本地模板。

## 版本与验收入口

2026-10-23 流畅度审核分支 `feat/performance-baseline` 已生成 **`0.1.0+16` 内测性能基线**（运行源码 `4319e1e`，arm64 release 49,515,967B）：仅增加内存帧统计、场景分组和系统分享，不先修改业务/视觉或 SDK。334 项测试、分析、三 ABI JNI 和生产版裁剪通过；按开哥提醒已停止模拟器，仅保留三个已导出场景。开哥导出手机基线后，再据实测决定修复与对比；本轮尚未合并推送。[基线采集与产物核验](docs/performance-baseline-2026-10-23.md)、[App 与 SDK 静态审核](docs/performance-static-audit-2026-10-23.md)。

2026-10-23 当前保存版本为 **`0.1.0+15` internal**，运行源码 `15079e6`，本地注释标签 `smartfit-v0.1.0+15-internal-verified`。开哥确认本次测试通过；arm64 release 为 **49,384,327B / 49.38MB**，包含已选 AAC-LC、内测运行日志与 Android 存储 JNI 修复。App 两项 SDK 依赖固定 `f684e02`（coach 0.3.3 / trainer 0.1.6）。当前仅保存版本及对齐文档，尚未合并或推送；连续 >20 分钟训练和 iOS 专项单独待验。入口：[验收记录](docs/acceptance.md)、[当前台账](docs/version-management.md)、[修复详情](docs/android-storage-jni-fix-2026-10-23.md)。下方为历史阶段。

2026-10-22 已按开哥授权修复、通过审核并合并 [PR #5](https://github.com/mhgd3250905/Sport-Helper/pull/5)，合并提交 `172366c6527d999b7817d97fe386e442f70f0e20`。计划卡展开后大图过渡到首行动作缩略图，标题与收起按钮适配大字体，隐藏卡片退出键盘焦点。253 项测试、分析 0 issue、Web/Android debug 构建及浏览器交互通过；SDK 0.3.3 与顶部栏改动保留。本轮未交付或安装新 APK，[审核、截图与边界](docs/pr5-local-review.md)。

SDK 0.3.3 已于 2026-10-21 经开哥批准，以 `f80db2804d6cb9791817463cd1cd5250b32a0e84` 合入并推送 App main，合并树与验收分支 `feat/coach-033-speed@3388bd1` 一致。两项 git ref 固定为 SDK main `fc5e456c44d76b872eb812597ffb5f67bc66bce3`，按要求使用 `0.1.0+9`，包含顶部栏移除。完整 237 项测试与分析 0 问题；六条真实 Worker 记录已核对为相同运行代码并复用，共 180.430 秒、74,130 token，均无回落。[可转发的六条记录](docs/coach-033-smoke-2026-10-21.md)。

此前 Liquid Glass UI 于 2026-10-21 经开哥授权审核、修复并合并 [PR #4](https://github.com/mhgd3250905/Sport-Helper/pull/4)，合并提交 `561ea8cc69efa38d07c03169c257e8fa4116bc72`。当时 237 项测试、分析 0 issue、Web 与 Android debug 构建通过，实际浏览器验证深浅色计划卡及共享训练流程；保留 CoachAgent 0.3.2 和 SDK 门禁，修复大字体溢出。截图、包身份和未测设备性能边界见 [PR #4 审核记录](docs/pr4-local-review.md)。以下 `+8` 数据描述之前的 SDK 接入验收，不替代当前版本。

### SDK 0.3.2 接入阶段（0.1.0+8，历史）

SDK 接入阶段版本 `0.1.0+8`，**2026-10-21 经开哥授权，已以 `ebb0840f479acdf0bdc8a46e41f30eff055a0c1b` 合入 main**，已推送 origin/main 并核对远端一致。合并树与审核分支 `feat/smartfit-coach-032@f0ebafc6257347e62533d98fb5d57f0706ddf6e9` 完全一致；两项 git ref 固定 SDK main `b26e4fda807b6ef3db15a61ba30c67fb51dce5e1`。运行源码、224 项测试和 APK 仍绑定 `b39304488e964b22a65501363a15140b5d0ca235`，未重新构建或冒烟。六条真实交互均 ok、无回落，独立动作卡严格补验通过；原臀桥合法文字导致的脚本断言失败 / exit 1 保留。完整证据见 [0.3.2 记录](docs/coach-032-smoke-2026-10-21.md)、[版本台账](docs/version-management.md) 与 [验收记录](docs/acceptance.md)。

App 生命周期内长期持有一个 `CoachAgent`，关闭 AI 界面保留会话，「新对话」取消并 `reset()`；请求中禁用发送并可取消，作废结果不显示。纯文字、动作卡与计划卡仍只用 SDK 接纳的文字、`ValidatedActions`、`ValidatedPlan`，恢复卡片重新过门禁。SDK 默认最多 100 逻辑步、单次请求 60 秒、整轮 360 秒、每步最多 4 次重试，30 秒发慢提示；客户端 `maxRetries=0`，重试由 Agent 负责，App 外保护为 390 秒。`reading/checking` 显示查库/核对计划，`retrying` 显示重试序号，`contextTooLong` 单独提示整理上下文，`slow` 显示「还在想…」。最终失败按重试用尽、不可重试、整轮超时或空转区分「预设方案」文案，不展示内部异常。

设置页提供「AI 记忆」与「清除记忆」。记忆默认开启，`UserMemoryStore.load/save` 整表保存到独立本机键 `smartfit.ai-memory.v1`。SDK 逐条等待真实保存成功才确认，后续取消或新对话保留已确认事实；未确认的迟到保存按 SDK 契约补偿。关闭不删除原记忆，清除须等待 `clearMemory()`，保存失败会抛错并提示重试。开关和清除保留当前聊天与计划；验证关闭后的隔离须先开「新对话」。

历史 `+7` 分支 `feat/smartfit-skill-agent` 当时完成分组验证、未单独合 main，其功能现随 `+8` 一并进入主线。旧测试数与包身份仍只适用于 [该阶段](docs/coach-agent-smoke-2026-10-21.md)，不替代 `+8` / SDK 0.3.2 的独立终验。

历史主线 `main` 的 `0.1.0+6`（来自 `feat/smartfit-coach-tools`）接入 `ugk_coach 0.2.0` 工具会话接口。`ugk_coach` 与 `ugk_trainer 0.1.4` 的 git 依赖共同固定到 SDK main commit `09a392bc0b736e6a23eef71d55d86108660e0e59`。该阶段核心链路及模拟器 Worker 冷烟已验证，2026-10-21 经开哥授权合入 `main`，合并提交 `f83642e`；没有真机通过结论。历史记录不能替代 `+7` Skill Agent 的首次多步验证。

`+6` 长期持有一个 `CoachSession`，关闭 AI 界面保留会话，「新对话」取消进行中的请求并调用 `reset()`。纯文字显示气泡；`show_actions` 仅以 `ValidatedActions` 显示动作卡，`show_plan` 仅以 `ValidatedPlan` 显示计划卡，可保存或交给 `ugk_trainer` 开练。持久化卡片恢复时重新过 SDK 门禁，模型原始输出不进入渲染层。请求期间禁用发送，显示等待与取消入口；单次 HTTP 超时 120 秒、HTTP 重试为 0，门禁最多重交 2 次，整轮保护超时 365 秒。

历史 `0.1.0+5`（`feat/smartfit-ai-replies`）使用旧版 JSON 信封接口，源码 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`；接口 `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`。当时 debug 包已覆盖安装并保留旧数据，6 项接口/UUID/鉴权配置测试及分析通过；旧源全量 180 项测试该轮未重跑。新地址真机通用问答通过，但三次计划生成均因上游 `tencent:AbortError` 回退本地模板，新接口计划生成未通过。`+5` 实际界面已验证旧 `+4` AI 计划的保存、局部启动/暂停/提前结束及重启保留；这不代表新地址生成链路或完整训练通过。2026-10-21 的该次文档收束沿用 2026-10-20 对应源码记录，不是 `+6` 工具接入的验证证据。

旧 `0.1.0+4` / `cc16f530944cf4f6034365aa111528536978ecc3` 的分析及 180 项测试通过；旧地址真机曾约 21 秒成功生成 AI 计划，随后追问回落本地。服务调整中，这些记录不代表新地址与 `+5` 已验证通过。

此前主线为 `0.1.0+3`：PR #1、#2、#3、共享训练接入及 `repSeconds` 来源修复均已合并推送，SDK 固定 `9407bf3`；最近里程碑标签仍为 `m7-aesthetic-v2`。键盘恢复及旧训练证据见 [接入及后续修复记录](docs/ugk-trainer-integration.md)。release 构建、正式签名和完整设备验收仍未完成；`0.1.0+2` 的完整训练不能替代新 AI 包验收。

- [版本管理与台账](docs/version-management.md)：当前版本、里程碑 SHA、测试包身份、版本更新及交付规则的统一入口。
- [本机验收记录](docs/acceptance.md)：各检查点的验证证据、环境和待验清单。
- [ugk_trainer 真机记录](docs/trainer-device-check-2026-10-20.md)：`0.1.0+2` 在 Android 16 上的一轮完整训练、锁屏/后台、保存与重启验证，含未覆盖范围。
- [阶段交接记录](docs/HANDOVER.md)：角色与约束，以及明确标记的历史交接内容。

## 目录

```
lib/domain/      训练领域：exercise / plan(TrainingPlan v1) / template / scenario(描述匹配) /
                 plan_generator(本地模板生成) / plan_validator / session(SDK 计划及节奏适配)
lib/voice/       ugk_trainer 导出入口；App 语言偏好与素材测试适配，训练语音由 SDK 负责
lib/core/        复制自 HipLab（媒体播放 WebView、本地存储、屏幕常亮），文件头注明来源
lib/chat/        对话：ChatEngine 接口、AI 回复与本地规则回退、SlotParser、
                 ChatController（会话、开场安全确认、保存计划、本地历史）、safety_script（免责声明与 4 问）
lib/ui/chat/     对话主界面：星尘背景、色调气泡、ValidatedActions 动作卡、ValidatedPlan 计划卡、已存计划抽屉
lib/ui/          训练计划(训练小组) → 跟练 → 动作库 / 设置；custom_plan_page = 原表单（对话「自己选条件」）
lib/packs/       动作小包读取（与 App 无关，可整体拷走）
assets/packs/    动作小包：每个动作一个文件夹 <id>/{pack.json, cover.jpg, demo.mp4, voice/zh/*.m4a}，
                 公共包 _common/（数字、单位、口令、提示音）+ index.json —— 格式见 docs/drill-pack-spec.md
assets/library/  templates.json（13 套模板，生成文件）
assets/media_player/ player.html/js/css（WebView 播放页）
tools/packs/     build_packs.py（封包、索引、pubspec）、validate_packs.py（校验）、migrate_v1.py（一次性迁移记录）
tools/library/   build_templates.py（模板）
tools/media/     prepare_media.py（Pose-Hub 成片转码 / 绿幕抠像 → 小包 demo.mp4 / cover.jpg）
tools/voice/     build_voice.py（edge-tts + HipLab v4.1 后处理，台词来自小包；商用前换 Azure）、audit_voice.py（逐条检测）
test/            领域测试 + 对话引擎/保存测试 + App 主流程测试；test_screens/ 截图（不随 flutter test 运行；
                 web_shots_main.dart + tools/shots/chat_shots.py 生成 docs/screenshots/chat-*.png）
docs/            评估报告、验收清单、风险、计划 schema、截图
```

## 构建

AI debug 包通过 `--dart-define=SMARTFIT_AI_TOKEN` 注入 Worker App Key，不把密钥写入源码、资产或仓库：

```powershell
flutter build apk --debug --dart-define=SMARTFIT_AI_TOKEN='<Worker App Key>'
```

当前模型为 `deepseek-v4-flash-0731`，BaseURL 为 `https://api.uuugk.win/v1`。App 使用 SDK `LlmConfig.ugkWorker` 和 `UgkWorkerAuth`，沿用原 App Key 和原设备 UUID，只发送 `X-App-Key` 与 `X-Device-Id`，不发送 `Authorization`。UUIDv4 首次成功持久化后才启用 AI；配置缺失或标识存储失败使用本地引擎。客户端 `maxRetries=0`，Agent 以 60 秒单次、360 秒整轮预算负责最多 4 次步级重试，App 390 秒外保护。门禁最多重交 2 次；读取、核对、重试及慢响应期间均可取消，作废结果不显示。

profile 使用 SDK 的 `profiles/smartfit.json`，随包副本为 `assets/coach/smartfit.json`。AI 目录由 SDK `DrillPackAdapter` 从实际随包 93 个动作构造；profile 备注中的全库 142 个动作不表示 App 已加载全库。每轮 `CoachContext` 传入已知水平、时长、保护部位及场景/器械；冲突由门禁要求重交。SDK 代码只在 SDK 仓库修改，App 不复制、内嵌或 patch SDK，不改 pub 缓存。依赖固定 SDK main 的具体提交；App 核心功能已验证，并经开哥授权合入、推送 main。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release        # 本机工具链及验收状态见 docs/acceptance.md
# 截图（使用内置字体）：flutter test test_screens/shots_test.dart --update-goldens
# 仅检查渲染：设置 SF_SCREENSHOT_DIR 为临时目录的绝对路径，避免改写文档截图
```

## 本机 Web 预览

```bash
flutter build web --release --no-web-resources-cdn
python -m http.server 8766 --bind 127.0.0.1 --directory build/web
```

打开 `http://127.0.0.1:8766`。Web 可验证界面、计划生成、跟练计时、语音和浏览器存储；动作视频目前只有封面，中文字体首次加载可能联网。Web 走查结果与 Android 待验项见 [验收记录](docs/acceptance.md)。

## 数据再生成

```bash
# 动作内容（名称、要领、剂量、台词…）直接改 assets/packs/<id>/pack.json，并升该包 version
python3 tools/library/build_templates.py
python3 tools/media/prepare_media.py --hiplab <HipLab> --green <Drive 绿幕目录>
PYTHONPATH=<edge_tts>:<numpy> python3 tools/voice/build_voice.py build   # 可加 --budget 秒数分段跑
python3 tools/voice/audit_voice.py --raw                                  # 必须 0 失败
python3 tools/packs/build_packs.py --pubspec pubspec.yaml
python3 tools/packs/validate_packs.py --decode
```

## 素材与许可

动作视频来自 Pose-Hub（mhgd3250905/3D-Pose-Hub）：46 条为 v0.2.0 深色成片（经 HipLab 冻结版本），47 条为 Pose-Hub 云盘归档的绿幕母版，本仓库抠像到同色背景。
人物派生自 Blender Studio Snow（CC BY 4.0，署名见 `assets/licenses/Drill-media-ATTRIBUTION.md`，App「关于」页展示）。
3D-Pose-Hub 与 HipLab 只作参考与素材来源，本仓库不向它们写入任何内容。
