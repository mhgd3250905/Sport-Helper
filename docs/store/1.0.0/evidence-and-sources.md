# 原界面候选文字与表单的事实依据

核对日期：2026-10-24。当前目标为 `release/1.0` / **1.0.0+25**。已验收原界面基线为 `main@f5332bf`；用户已明确允许生产素材配置及两处资料适配，保持完整93项范围。仅在设置既有隐私段落增加必要政策入口。+25最终构建、签名、网络声明、真机和送审以主任务实际回执为准，不能把本页作为这些步骤已完成的证明。

历史：+23新首页/AI隐藏/禁备份方案已撤销；+24恢复原界面并已上传Play HOLD草稿而未送审，Google读到min24/target36，真机却因全部189发布资格false而空库。原完整验收包为internal2022开启素材预览，不能拿它冒充生产素材/演示。用户随后明确允许修正生产素材配置和两处适配。

## 仓库与 SDK

| 事实 | 可复核来源 |
|---|---|
| 原对话首页保留，设备 UUID 仍在本机创建 | [lib/main.dart](../../../lib/main.dart)，`DeviceIdentity.loadOrCreate` 和 `ChatHomePage`；不再承诺无 key 时隐藏入口或不创建身份 |
| 空 key 不启用 AI；公开服务地址保持原版 | [ai_coach_config.dart](../../../lib/chat/ai_coach_config.dart)，`fromEnvironment` / `enabled`；`baseUrl` 不是密钥 |
| 本地规则/模板及原计划交互 | [rule_chat_engine.dart](../../../lib/chat/rule_chat_engine.dart)、[chat_home_page.dart](../../../lib/ui/chat/chat_home_page.dart) |
| 安全状态与安全对话都可能在本机保存 | [chat_controller.dart](../../../lib/chat/chat_controller.dart)，`_safetyAnswer` / `_user` / 对话保存；[app_store.dart](../../../lib/data/app_store.dart) 的安全状态及 `chat` 字段 |
| 训练结果、历史、计划和偏好在本机存储 | [app_store.dart](../../../lib/data/app_store.dart)，`saveSession` / `_encodeState`；[local_state_storage.dart](../../../lib/core/storage/local_state_storage.dart)，`SharedPreferencesLocalStateStorage` |
| 素材源由构建环境注入；+25配置公开HTTPS分发 | [training_media_config.dart](../../../lib/app/training_media_config.dart)，`baseUrls`；`SMARTFIT_MEDIA_PRIMARY_URL=https://smartfit-media.pages.dev/v0.3.0-app/`。其兄弟目录保存视频，SDK仍校验SHA/字节 |
| 公网明文禁止，localhost/127.0.0.1 仅本地媒体例外 | [network_security_config.xml](../../../android/app/src/main/res/xml/network_security_config.xml) |
| 保留原默认系统备份，可能发生云备份或设备迁移 | [AndroidManifest.xml](../../../android/app/src/main/AndroidManifest.xml) 恢复原版，不再加入禁备份字段/自定义排除规则；不能承诺记录永不离开设备 |
| 无账号、广告、支付、统计 SDK 的基础依赖盘点 | [pubspec.yaml](../../../pubspec.yaml)；仍须检查最终包及完整传递依赖，不能只靠直接依赖列表下结论 |
| 原 AI 记忆入口/隐私文案保留，仅增加政策链接；诊断功能仍按原构建能力 | [about_page.dart](../../../lib/ui/about_page.dart)、[legal_policy_page.dart](../../../lib/ui/legal_policy_page.dart)；政策页仅允许本站HTTPS、关闭JS并拒绝WebView权限请求 |
| 媒体播放前台服务真实进入 App 训练路径 | [player_page.dart](../../../lib/ui/player_page.dart) 直接使用固定 SDK 的 `TrainerPlayer`，未关闭其默认 `keepAlive=true`。SDK `lib/src/ui/trainer_player.dart` 的初始化/重播调用 `TrainingHold.begin`，完成、停止和 dispose 释放；暂停/恢复同步媒体状态 |
| SDK Android 服务与权限 | 固定 SDK `packages/ugk_trainer/android/src/main/AndroidManifest.xml` 声明 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`WAKE_LOCK`，以及非导出 `TrainingSessionService`、`foregroundServiceType=mediaPlayback`、`stopWithTask=true`；+24实际AAB合并清单确认存在；+25须重新确认 |
| Dart / Android 桥接及生命周期 | SDK `lib/src/platform/training_keep_alive.dart`：`TrainingHold` 通过 `ugk_trainer/training_session` 通道发 start/setPlaybackState/stop；Android `UgkTrainerPlugin.kt` 转交 `TrainingSessionService.kt`；服务使用持续训练通知、可选 MediaSession、带超时 CPU wake lock，并在 finish/onDestroy/任务移除时清理 |
| 非医疗说明与安全确认在设置中展示；删除说明在公开政策 | [about_page.dart](../../../lib/ui/about_page.dart)、[safety_script.dart](../../../lib/chat/safety_script.dart)；公开隐私政策描述系统清除存储/卸载和备份限制，不虚构App内一键删除全部记录 |
| SDK 精确来源 | pubspec 的两个 Git ref、lock 中 resolved-ref 均应为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`；该提交包版本为 coach 0.3.3 / trainer 0.1.6 |
| 正式图标来源 | [A2 采用记录](../../icon-fullbody-zoom-2026-10-24.md)、[生产默认选择](../../../tools/branding/production-icon-selection.json)、[生成来源](../../../tools/branding/fullbody-zoom-provenance.json) |
| 动作媒体和字体来源说明 | [Drill-media-ATTRIBUTION.md](../../../assets/licenses/Drill-media-ATTRIBUTION.md)、[NotoSansSC-OFL.txt](../../../assets/licenses/NotoSansSC-OFL.txt) |

固定SDK下载器在配置的 `baseUrls` 中请求子清单/视频，验证字节和SHA后才启用。+24为空源；+25改为公开Cloudflare HTTPS，不能继续说“没有公网素材请求”。请求使分发方接触IP、时间、HTTP元数据和带动作ID的路径，不附加App UUID、聊天、安全答案、完整计划/训练记录或AI记忆。系统WebView政策页也产生普通网站请求。主任务已确定+25将设备/其他标识及App interactions均申报收集/分享Yes、非ephemeral、Required，用途为应用功能及防欺诈/安全/合规，传输HTTPS；不利用IP推导位置，不上传安全问答或完整训练完成记录，不提供网络安全日志自动删除承诺。该更新须在Console实际保存，不等于Google已批准。

生产资格采用 [用户授权记录](production-media-authorization.json) 中的App完整93项范围，不是把上游189项一律放行。93视频/695语音的完整性核查不等同临床安全、全部画面或人耳试听全部通过。已确认适配项是 s-figure4脚踩地版对应四条旧抱腿提示/语音，以及 w-dead-bug 新视频每次4秒、旧元数据3秒。实际修复和验证应分别记录，不回写上游尚未执行的审核状态。

`lib/core/platform/screen_awake.dart` 中“无 manifest service / 无需 Play 声明”的注释描述较早的单独亮屏守卫，不能覆盖当前 App 使用的 SDK 训练播放器：SDK 的 `ScreenAwake` 与 `TrainingHold` 是实际链路。FGS 必须按最终清单如实申报，不能据遗留注释填成没有前台服务。

静音边界也需要如实呈现：SDK 的 `mediaPlayback: voice || chimes` 控制 MediaSession 是否公开，但默认 `keepAlive` 仍会启动固定 `mediaPlayback` 类型 Service。暂停会更改媒体状态，但服务仍跟随会话保留。静态代码不能证明这两条路径已满足全部审核条件；需实际演示及必要性复核，不把“有 FGS 权限”当成 Google 已批准用途。

## 当前官方资料

以下均为 2026-10-24 查询的 Google / Flutter 官方资料，未使用论坛代替政策。Console 的具体问题可能依账号、功能和政策更新变化；用户已授权Agent代办，本目录用实际后台回执区分已保存、已上传、已送审和已发布。

| 官方来源 | 本草稿使用的结论 |
|---|---|
| [Data safety 填报指南](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) | 声明需覆盖 App 与 SDK 的真实数据实践；只在设备内处理而不外传的数据与“收集”有区别 |
| [用户数据政策](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en) | 数据使用、共享、保留、删除和第三方代码处理应透明，政策须与实际一致 |
| [Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en) | 健身相关产品需健康声明及可公开访问的隐私政策，App 内也要可读；不作未经支持的医疗宣传 |
| [健康应用分类](https://support.google.com/googleplay/android-developer/answer/13996367?hl=en) | 运动与健身功能属于健康健身范围；安全风险提示不使本产品成为诊断/治疗工具 |
| [商店预览素材规范](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) | 图标、截图和 Feature Graphic 有明确规格，素材须准确反映真实功能 |
| [目标 API 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) | 以当日提交要求及目标设备为准；当前+24实际已被Play解析为target36，+25仍须读最终清单确认 |
| [Flutter Android 发布说明](https://docs.flutter.dev/deployment/android) | AAB 上传签名与用户下载的 App Signing 有区别；签名材料须私下保管 |
| [前台服务声明说明](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en) | 为真实使用的 FGS 类型描述功能、被延迟/中断的影响并提供触发流程演示视频；mediaPlayback 展示用户主动开始音视频播放 |
| [Android 前台服务类型](https://developer.android.com/develop/background-work/services/fgs/service-types#media) | `mediaPlayback` 及对应权限用于后台音视频播放，不是相机、录音、健康传感器或数据同步权限 |
| [Device and Network Abuse](https://support.google.com/googleplay/android-developer/answer/16559646?hl=en) | FGS 应与核心功能、用户可感知/主动发起及可停止的有限任务相符；不是任意常驻保活的许可 |
| [Android Auto Backup](https://developer.android.com/identity/data/autobackup) | 默认可备份 SharedPreferences 和应用文件；单凭allowBackup=true不能证明开发者主动收集，亦不能推断所有平台备份均满足同一豁免；政策须披露实际边界 |

## 实际后台 / 网站事实

- Play条目已创建，App ID `4974885907919443404`，公开开发者名称Bboy Ug1yk。
- +24 AAB已被Google接收并解析，保存为HOLD草稿，**没有送审、测试分发或Production发布**。
- 设置已完成10/11；中英文文案与图标/置顶图保存为草稿，缺实际+25截图。IARC状态已完成（ESRB Everyone、PEGI3等）；受众13+，首版免费。
- Alpha已选178地区，测试名单仅本人邮箱，0人选择参与。后台要求至少12人连续14天真实封测后申请Production权限。[官方门槛](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)
- 隐私、条款、支持页在 https://smartfit-store.pages.dev/ 已公开部署；媒体地址为 https://smartfit-media.pages.dev/v0.3.0-app/ 。网络可用性及最终包下载结果须看相应实际回执，不以写下URL代替通过。

## 尚不能写成“通过”的项目

- +25还未在此文确认为已构建、签名核验或真机通过，不能套用+24产物哈希/测试数字。
- 没有已录制或上传YouTube的真实生产训练/FGS视频链接；不使用+23假首页、+24空库诊断或internal2022流程冒充+25素材。
- Windows配置检查不等于Mac/iOS编译、签名、真机或Apple后台通过。
- 当前保存的+24无远程源Data safety答案须更新到上述+25口径；此文不代表Console已保存新答案。不能承诺无日志/纯临时处理，也不能把所有本地健康记录误报为CDN上传。
- FGS用途草稿不等于FGS审核通过；真实有声、后台、暂停/静音及结束路径的必要性和实际行为须由最终包演示。
