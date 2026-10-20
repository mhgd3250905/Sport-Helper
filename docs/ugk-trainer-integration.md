# SmartFit 接入 ugk_trainer

2026-10-20，分支 `feat/ugk-trainer-integration`，开发包 `0.1.0+2`。尚未合入或推送 main，未完成真机验收。

## 依赖与包端修复

`pubspec.yaml` 以 Git 引入 `mhgd3250905/ugk-3d-pose-sdk`，子目录 `packages/ugk_trainer`，并以相同提交引入根包 `ugk_coach`（仅使用计划编解码，没有启用 AI）。最初上游基线为 `68c3f32389749c04ad61a06af96e4b9841ccce87`。

集成固定到本机 SDK 修复提交 `ea00ff7f2a4b7f46274b70708a45b435f269f993`，位于 SDK 分支 `feat/trainer-save-reliability`：同步保存异常后允许重试；完成、关闭与系统返回都等待保存成功，失败时保留相同结果与重试入口；连续返回不会重复弹出路由。SDK 包静态分析无问题，96 项测试通过。

**该 SDK 提交尚未推送。** 本机解析依赖时仅在该次命令的 Git 环境中把 SDK URL 映射到本机 SDK 仓库，实际仍从 Git 提交建立 Pub 缓存，未修改全局 Git 配置、没有 path override。提交受审阅期间，新环境尚不能从 GitHub 获取该 SHA。获准发布后先推送 SDK 提交，再在没有本地映射的环境确认依赖可获取，之后才能合入 SmartFit。不能把本机成功解析等同于远端可复现。

## App 保留的职责

`lib/domain/session.dart` 只保留计划/动作库适配和时长估算委托，阶段构建及绝对时钟由 SDK 负责。现有计划 JSON、模板生成、规则对话与安全入口不变。

`lib/ui/player_page.dart` 包装 `TrainerPlayer`，注入中文 `TrainerStrings`、SmartFit 深浅色 token 与本地字体、动作名称/要点、深浅色视频及封面、现有 `ExerciseVideo` 媒体组件和静态星空。完成页通过反馈插槽保留 App 的完成标记动画；其他页面的自绘图标保留，训练控件使用 SDK 图标。播放页使用 App 新增的单色通知小图标。

`lib/voice/` 的队列、脚本、runner、播放控制器与输出均导出 SDK 实现；仅保留 App 的语言偏好存储转换及测试素材适配。App 使用一个 `JustAudioVoiceOutput`，App 退出时释放。跟随 App 映射中文；没有英文语音素材时降级为提示音与画面，不拼接半句中文。

`trainerRhythms` 只从实际 `repSeconds` 建立节奏。缺失时不补自动计时节奏，计次动作必须点「完成本组」。计划预估时长仍可估算，不能作为自动结束依据。

`AppStore.saveSession` 按 `sessionId` 覆盖保存完整 `SessionResult`，兼容原 `smartfit.state.v1` 及旧 `HistoryEntry`。写入串行，成功落盘后才更新训练结果内存；失败向 SDK 冒泡供重试。完成后的聊天反馈使用播放器返回的结果，不依赖历史列表条数增长。SDK 的 `completedExercises` 沿用经过动作数的语义；具体完成、跳过、未到达及组数保存在 `items`，不能把跳过训练解释为逐项做完。

## Android 与 Play Console

服务 `com.ugk.trainer.TrainingSessionService`、类型 `mediaPlayback`，以及 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`WAKE_LOCK` 权限应由插件 manifest 合并，不在 App 重复声明服务。

官方入口是 Play Console「应用内容 → 前台服务权限」，为 SmartFit 单独声明媒体播放。依据：[Google Play 前台服务声明要求](https://support.google.com/googleplay/android-developer/answer/13392821?hl=zh-Hans)、[Android 前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types?hl=zh-cn)。本次没有提供 Console 应用条目或登录入口，以下是可审阅草稿，**未提交声明**。

| 表单内容 | 草稿 |
| --- | --- |
| 类型 | 媒体播放 `TYPE_MEDIA_PLAYBACK` |
| 功能 | 用户主动开始跟练后，持续播放本地语音训练指导、动作节拍和提示音；切到后台或手动锁屏时仍需听到当前训练的音频。 |
| 用户影响 | 系统若暂停训练音频，用户会丢失换侧、休息结束与结束训练提示，无法按正在进行的训练流程跟练。 |
| 启停方式 | 在前台点击开始训练时启动，通知显示训练正在进行；训练结束或退出后停止。需用真机确认行为与说明一致。 |
| 演示材料 | 待录制：开始训练 → 显示常驻通知 → 切后台/锁屏仍有训练音频 → 返回暂停/继续 → 完成并查看保存记录 → 服务通知消失。提交前替换为可访问的视频链接。 |

## 验证记录

SDK：`flutter analyze --no-pub` 无问题；`flutter test --no-pub --reporter expanded` 96 项通过。App：`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=2 --reporter expanded` 156 项通过；`flutter build apk --debug --no-pub`、`flutter build web --release --no-pub` 均成功（Web 提示 CupertinoIcons 字体未打包，未阻断构建）。合并 manifest 检查通过：单个 `mediaPlayback` 服务、3 项所需权限、`exported=false`、`stopWithTask=true`。APK ZIP 完整性、SDK 静音素材和通知图标检查通过，签名验证通过，证书与上一测试包相同。

新包仅保存在 `.buildlog/install/SmartFit-ugk-trainer-0.1.0+2-debug.apk`，未安装、未上传、未公开发布。大小 203,720,356 bytes；包名 `com.ugk.smartfit`，versionName `0.1.0`、versionCode `2`，minSdk 24、targetSdk 36，三 ABI。SHA-256：`7fd8c50b521090dd9bf60e2a332f266729c44bdab3e10936ff6de8e7bb4d24fd`。debug 签名证书 SHA-256：`3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`。

日志在本机忽略目录 `.buildlog/trainer-final-tests.log`、`trainer-sdk-tests.log`、`trainer-android-debug.log`。这些是本次分支的自动化结果，与设备验收分别记录，详见 [acceptance.md](acceptance.md)。

新增 App 接入回归覆盖缺节奏手动完成、自然结束与同 ID 重载、深浅主题/视频/封面/暂停、无英文素材降级；存储回归覆盖旧数据、重试、并发写入与完整结果保存。

## 待验门槛

用户已明确目前没有真机。以下全部保留未验证，不以 Flutter 测试或构建成功替代：

- 从真实模板完整完成一次训练，人工听语音、计次/换侧/休息时序，确认示范视频与镜像。
- 手动锁屏、后台、恢复、音频中断及耳机拔出；确认通知和服务在训练结束后停止。
- 完成后查看记录，重启 App 再核对，保存失败重试不新增重复记录。
- 确认 Play Console 应用及权限，录制演示，审阅声明后提交。

真机验收通过、依赖远端可获取并经开哥同意后，才能合入 main 并推送。没有创建新发布标签，release 正式签名仍沿用原待办。
