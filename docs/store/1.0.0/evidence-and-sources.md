# 原界面候选文字与表单的事实依据

核对日期：2026-10-24。当前为 `release/1.0` / `1.0.0+24`，界面与功能恢复 `main@f5332bf`，仅不注入 API Key。此前 +23 新首页、AI 隐藏和备份禁用方案均已撤销，不作为当前依据。最终产物和真机结果由父任务回执记录。

## 仓库与 SDK

| 事实 | 可复核来源 |
|---|---|
| 原对话首页保留，设备 UUID 仍在本机创建 | [lib/main.dart](../../../lib/main.dart)，`DeviceIdentity.loadOrCreate` 和 `ChatHomePage`；不再承诺无 key 时隐藏入口或不创建身份 |
| 空 key 不启用 AI；公开服务地址保持原版 | [ai_coach_config.dart](../../../lib/chat/ai_coach_config.dart)，`fromEnvironment` / `enabled`；`baseUrl` 不是密钥 |
| 本地规则/模板及原计划交互 | [rule_chat_engine.dart](../../../lib/chat/rule_chat_engine.dart)、[chat_home_page.dart](../../../lib/ui/chat/chat_home_page.dart) |
| 安全状态与安全对话都可能在本机保存 | [chat_controller.dart](../../../lib/chat/chat_controller.dart)，`_safetyAnswer` / `_user` / 对话保存；[app_store.dart](../../../lib/data/app_store.dart) 的安全状态及 `chat` 字段 |
| 训练结果、历史、计划和偏好在本机存储 | [app_store.dart](../../../lib/data/app_store.dart)，`saveSession` / `_encodeState`；[local_state_storage.dart](../../../lib/core/storage/local_state_storage.dart)，`SharedPreferencesLocalStateStorage` |
| 无远程素材默认源，地址只能从构建环境注入 | [training_media_config.dart](../../../lib/app/training_media_config.dart)，`baseUrls` |
| 公网明文禁止，localhost/127.0.0.1 仅本地媒体例外 | [network_security_config.xml](../../../android/app/src/main/res/xml/network_security_config.xml) |
| 保留原默认系统备份，可能发生云备份或设备迁移 | [AndroidManifest.xml](../../../android/app/src/main/AndroidManifest.xml) 恢复原版，不再加入禁备份字段/自定义排除规则；不能承诺记录永不离开设备 |
| 无账号、广告、支付、统计 SDK 的基础依赖盘点 | [pubspec.yaml](../../../pubspec.yaml)；仍须检查最终包及完整传递依赖，不能只靠直接依赖列表下结论 |
| 原 AI 记忆入口/隐私文案保留，诊断功能仍按原构建能力 | [about_page.dart](../../../lib/ui/about_page.dart)；空 key 不删除原 UI |
| 媒体播放前台服务真实进入 App 训练路径 | [player_page.dart](../../../lib/ui/player_page.dart) 直接使用固定 SDK 的 `TrainerPlayer`，未关闭其默认 `keepAlive=true`。SDK `lib/src/ui/trainer_player.dart` 的初始化/重播调用 `TrainingHold.begin`，完成、停止和 dispose 释放；暂停/恢复同步媒体状态 |
| SDK Android 服务与权限 | 固定 SDK `packages/ugk_trainer/android/src/main/AndroidManifest.xml` 声明 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`WAKE_LOCK`，以及非导出 `TrainingSessionService`、`foregroundServiceType=mediaPlayback`、`stopWithTask=true`；父任务最终 AAB 合并清单确认存在 |
| Dart / Android 桥接及生命周期 | SDK `lib/src/platform/training_keep_alive.dart`：`TrainingHold` 通过 `ugk_trainer/training_session` 通道发 start/setPlaybackState/stop；Android `UgkTrainerPlugin.kt` 转交 `TrainingSessionService.kt`；服务使用持续训练通知、可选 MediaSession、带超时 CPU wake lock，并在 finish/onDestroy/任务移除时清理 |
| 删除本地数据的方法及非医疗说明在设置中展示 | [about_page.dart](../../../lib/ui/about_page.dart)；[safety_script.dart](../../../lib/chat/safety_script.dart) |
| SDK 精确来源 | pubspec 的两个 Git ref、lock 中 resolved-ref 均应为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`；该提交包版本为 coach 0.3.3 / trainer 0.1.6 |
| 正式图标来源 | [A2 采用记录](../../icon-fullbody-zoom-2026-10-24.md)、[生产默认选择](../../../tools/branding/production-icon-selection.json)、[生成来源](../../../tools/branding/fullbody-zoom-provenance.json) |
| 动作媒体和字体来源说明 | [Drill-media-ATTRIBUTION.md](../../../assets/licenses/Drill-media-ATTRIBUTION.md)、[NotoSansSC-OFL.txt](../../../assets/licenses/NotoSansSC-OFL.txt) |

固定 SDK 的 native 媒体下载器仅在 `baseUrls` 中存在源时发起相应 HTTP 请求；空源不产生公网素材请求。内置 WebView 播放器使用回环媒体和限制性 CSP。没有将“存在 INTERNET 权限”等同于“必定收集数据”。此静态事实仍需最终候选配置和真机行为核对。

`lib/core/platform/screen_awake.dart` 中“无 manifest service / 无需 Play 声明”的注释描述较早的单独亮屏守卫，不能覆盖当前 App 使用的 SDK 训练播放器：SDK 的 `ScreenAwake` 与 `TrainingHold` 是实际链路。FGS 必须按最终清单如实申报，不能据遗留注释填成没有前台服务。

静音边界也需要如实呈现：SDK 的 `mediaPlayback: voice || chimes` 控制 MediaSession 是否公开，但默认 `keepAlive` 仍会启动固定 `mediaPlayback` 类型 Service。暂停会更改媒体状态，但服务仍跟随会话保留。静态代码不能证明这两条路径已满足全部审核条件；需实际演示及必要性复核，不把“有 FGS 权限”当成 Google 已批准用途。

## 当前官方资料

以下均为 2026-10-24 查询的 Google / Flutter 官方资料，未使用论坛代替政策。Console 的具体问题可能依账号、功能和政策更新变化，由开哥填表时复核。

| 官方来源 | 本草稿使用的结论 |
|---|---|
| [Data safety 填报指南](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) | 声明需覆盖 App 与 SDK 的真实数据实践；只在设备内处理而不外传的数据与“收集”有区别 |
| [用户数据政策](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en) | 数据使用、共享、保留、删除和第三方代码处理应透明，政策须与实际一致 |
| [Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en) | 健身相关产品需健康声明及可公开访问的隐私政策，App 内也要可读；不作未经支持的医疗宣传 |
| [健康应用分类](https://support.google.com/googleplay/android-developer/answer/13996367?hl=en) | 运动与健身功能属于健康健身范围；安全风险提示不使本产品成为诊断/治疗工具 |
| [商店预览素材规范](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) | 图标、截图和 Feature Graphic 有明确规格，素材须准确反映真实功能 |
| [目标 API 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) | 2026-08-31 起普通新手机 App 提交须 target API 36 或更高；最终产物仍须读清单确认 |
| [Flutter Android 发布说明](https://docs.flutter.dev/deployment/android) | AAB 上传签名与用户下载的 App Signing 有区别；签名材料须私下保管 |
| [前台服务声明说明](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en) | 为真实使用的 FGS 类型描述功能、被延迟/中断的影响并提供触发流程演示视频；mediaPlayback 展示用户主动开始音视频播放 |
| [Android 前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types#media) | `mediaPlayback` 及对应权限用于后台音视频播放，不是相机、录音、健康传感器或数据同步权限 |
| [Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en) | FGS 应与核心功能、用户可感知/主动发起及可停止的有限任务相符；不是任意常驻保活的许可 |
| [Android Auto Backup](https://developer.android.com/identity/data/autobackup) | 默认可备份 SharedPreferences 和应用文件；云备份、端到端加密及恢复随系统/用户条件变化，不能因为无 API Key 就推定不存在外传 |

## 尚不能写成“通过”的项目

- 没有后台证据，不能称应用条目已创建、上传成功、审核中或已发布。
- Markdown 正文不是公开隐私政策网址；主体名称尚未补齐。
- Windows 的 Xcode 文件检查不等于 Mac/iOS 编译、签名或真机通过。
- 真实截图必须来自恢复原界面的 +24 候选；不使用 +23 新首页截图或生成的假界面。可见 AI 入口是原 UI 的一部分，不作为截图错误删除。
- 空 key 只能证明未启用 AI 请求，不能推出所有数据永不离设备；Data safety 已分别说明原对话/UUID、本地处理和默认系统备份的判断边界，不擅自勾全局“无收集”。
- 最终清单确含媒体播放 FGS。用途草稿和视频拍摄清单已补，但未附演示视频链接、未在 Console 填报，也没有 FGS 审核通过证据；静音/暂停路径尚需必要性与真机行为复核。
