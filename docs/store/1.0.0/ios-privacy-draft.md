# iOS App Privacy 填写草稿

核对日期：2026-10-24。适用 `release/1.0` 的 `com.ugk.smartfit` / `1.0.0+25`。这是供开哥复核的答案草稿，尚未保存到 App Store Connect，也不代表已提交审核。

本轮用户已确认保留原界面，只是不注入 AI Key；原 AI 记忆设置和说明仍可见。构建仅配置公开素材 CDN，不传 `SMARTFIT_AI_TOKEN`、AI endpoint 或 dart-define 配置文件。空 Key 走本地规则引擎，不创建 AI 客户端。

## 建议答案

| 问题 / 数据类型 | 草稿答案 | 依据与限制 |
| --- | --- | --- |
| 是否收集数据 | 是，按 CDN 网络数据保守申报 | 不能因为 AI 关闭就填“不收集”；Cloudflare 可处理 IP、请求路径、时间和 User-Agent |
| Identifiers → Device ID | 是；用途 App Functionality；与用户关联；不用于 Tracking | 以网络 IP 用于内容分发、安全及防滥用为保守映射。App 本机 UUID 不附加到素材请求；不得说 UUID 已上传。上线前核对实际 CDN 日志与关联方式 |
| Usage Data → Product Interaction | 是；用途 App Functionality；与用户关联；不用于 Tracking | 请求的素材路径可包含动作 ID，能够反映观看的动作；不是上传完整训练历史 |
| Health / Fitness / Sensitive Info | 不申报云端收集本地训练记录和安全问答 | 问答、计划、训练结果存在本机。此结论依赖空 Key、本地引擎和未加入其他上传组件；不代表设备上没有这些数据 |
| 联系信息、照片、录音、位置、联系人、购买 | 未发现本版本主动采集上传 | 当前没有相机、麦克风、定位、HealthKit、广告或购买入口。用户主动发出的外部支持邮件须按实际支持处理另行核对 |
| 跨 App / 网站 Tracking | 否 | 未接入定向广告、广告归因或数据经纪商用途；不需要 ATT 提示 |
| 隐私政策 URL | `https://smartfit-store.pages.dev/privacy/` | 现有公开正文主要面向 Android，并描述原 AI 入口；开哥送审前需补充 iOS、平台备份和最终 CDN 数据处理范围 |

“与用户关联”暂按保守答案填写：当前没有在收集前匿名化 IP / 请求元数据的证据。若后续拿到真实 CDN 配置和日志证据，应按实际情况修订，而不是直接继承此草稿。App Privacy 与 Android Data safety 的选项和定义不同，不能照搬全部字段。

## 本地核查事实

- 原生 Release 构建已通过；解析后的 `UIDeviceFamily = [1]`、版本 `1.0.0 (25)`。
- 没有相机、麦克风或定位用途说明；`UIBackgroundModes = [audio]` 用于训练语音，`NSAllowsLocalNetworking` 用于设备回环播放器。
- Release App 含 6 份可解析的 `PrivacyInfo.xcprivacy`：Flutter、shared_preferences_foundation、webview_flutter_wkwebview、connectivity_plus、wakelock_plus、package_info_plus。各份 Tracking 均为 false。
- UserDefaults 及 Flutter 的 FileTimestamp / SystemBootTime 理由由随包隐私清单提供；最终仍须对签名 IPA 重验，不能用源码清单替代归档检查。
- 对未签名 Release App 的常见 GitHub token、私钥、OpenAI 风格 token 模式扫描未发现匹配；未发现 `.env`、`.key`、`.pem`、`.p12` 或 `.pfx` 文件。这不是对任意未知秘密的数学证明。
- 还未完成最终 TestFlight Build 的真机网络、拒绝权限、后台语音和系统备份验证；不得标为已通过。

## 官方依据

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)：包含第三方数据处理、仅本机处理、IP 按用途分类、请求后保留及关联定义。
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)：App Store Connect 填写入口。
- [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)：本地资源例外。
- [UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)：后台音频声明。
