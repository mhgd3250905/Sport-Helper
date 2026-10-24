# 基础版文字与表单的事实依据

核对日期：2026-10-24。范围是 `release/1.0` 的无 AI 基础候选；构建与真机最终结果以父任务生成的签名产物回执为准。

## 仓库与 SDK

| 事实 | 可复核来源 |
|---|---|
| 无 key 默认入口不创建聊天首页；AI 设备身份仅在显式配置可用时创建 | [lib/main.dart](../../../lib/main.dart)，`aiConfig.enabled` 条件和 `BasicHomePage` 分支 |
| key 和 HTTPS service URL 必须同时显式提供；默认都空 | [ai_coach_config.dart](../../../lib/chat/ai_coach_config.dart)，`fromEnvironment` / `enabled` |
| 本地训练首页、固定套路、上次计划和最近训练 | [basic_home_page.dart](../../../lib/ui/basic_home_page.dart) |
| 安全确认仅写入两个结果状态 | [safety_check_page.dart](../../../lib/ui/safety_check_page.dart)，`acceptSafety`；[app_store.dart](../../../lib/data/app_store.dart)，`safetyAccepted` / `safetyBlocked` / `_encodeState` |
| 训练结果、历史、计划和偏好在本机存储 | [app_store.dart](../../../lib/data/app_store.dart)，`saveSession` / `_encodeState`；[local_state_storage.dart](../../../lib/core/storage/local_state_storage.dart)，`SharedPreferencesLocalStateStorage` |
| 无远程素材默认源，地址只能从构建环境注入 | [training_media_config.dart](../../../lib/app/training_media_config.dart)，`baseUrls` |
| 公网明文禁止，localhost/127.0.0.1 仅本地媒体例外 | [network_security_config.xml](../../../android/app/src/main/res/xml/network_security_config.xml) |
| 禁用系统云备份和设备迁移备份 | [AndroidManifest.xml](../../../android/app/src/main/AndroidManifest.xml)，`allowBackup=false` / `fullBackupContent=false`；[data_extraction_rules.xml](../../../android/app/src/main/res/xml/data_extraction_rules.xml)，各存储 domain exclusion |
| 无账号、广告、支付、统计 SDK 的基础依赖盘点 | [pubspec.yaml](../../../pubspec.yaml)；仍须检查最终包及完整传递依赖，不能只靠直接依赖列表下结论 |
| AI、诊断、性能设置按构建能力隐藏 | [about_page.dart](../../../lib/ui/about_page.dart)，`aiConfig.enabled` / `RuntimeLog.instance.enabled` / `FrameRecorder.buildEnabled` |
| 删除本地数据的方法及非医疗说明在设置中展示 | [about_page.dart](../../../lib/ui/about_page.dart)；[safety_script.dart](../../../lib/chat/safety_script.dart) |
| SDK 精确来源 | pubspec 的两个 Git ref、lock 中 resolved-ref 均应为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`；该提交包版本为 coach 0.3.3 / trainer 0.1.6 |
| 正式图标来源 | [A2 采用记录](../../icon-fullbody-zoom-2026-10-24.md)、[生产默认选择](../../../tools/branding/production-icon-selection.json)、[生成来源](../../../tools/branding/fullbody-zoom-provenance.json) |
| 动作媒体和字体来源说明 | [Drill-media-ATTRIBUTION.md](../../../assets/licenses/Drill-media-ATTRIBUTION.md)、[NotoSansSC-OFL.txt](../../../assets/licenses/NotoSansSC-OFL.txt) |

固定 SDK 的 native 媒体下载器仅在 `baseUrls` 中存在源时发起相应 HTTP 请求；空源不产生公网素材请求。内置 WebView 播放器使用回环媒体和限制性 CSP。没有将“存在 INTERNET 权限”等同于“必定收集数据”。此静态事实仍需最终候选配置和真机行为核对。

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

## 尚不能写成“通过”的项目

- 没有后台证据，不能称应用条目已创建、上传成功、审核中或已发布。
- Markdown 正文不是公开隐私政策网址；主体名称尚未补齐。
- Windows 的 Xcode 文件检查不等于 Mac/iOS 编译、签名或真机通过。
- 真实截图必须来自最终候选；不能复用旧 AI 界面、历史内测包截图或生成的假界面。
- Data safety 的“无收集”前提是最终包无 key、无 AI/媒体远程 URL、无自动上传及有效的备份禁用配置；任何一项变化均需重做声明。
