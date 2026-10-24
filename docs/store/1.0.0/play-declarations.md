# Play 表单答案草稿

适用范围：`release/1.0` 的 **无 AI、无远程素材地址、无上传服务**基础候选。不是对后续联网版本或 `main` 将来功能的声明。填表前须以最终 AAB/真机回执复核；本轮没有在 Play 后台进行任何操作。

## Data safety

| 问题 / 数据项 | 草稿答案 | 依据与边界 |
|---|---|---|
| 是否收集或分享用户数据 | **否**，仅在最终候选满足上述配置及禁用系统备份后成立 | 本地访问的数据未发离设备；本机 WebView 回环请求不是开发者收到用户数据 |
| 健康信息 / 健身信息 | 不向开发者或第三方收集、分享 | 安全筛查只保存完成/限制训练两个状态；计划、训练时间和完成数据留在本机。隐私政策仍须解释这些本地处理 |
| 个人信息、财务信息、位置、联系人、照片/视频、音频文件、消息、浏览记录 | 不收集、不分享 | 无账号、支付、定位、通信、照片选择或录音采集功能。内置音视频素材不是用户音视频采集 |
| 应用活动、诊断和设备标识 | 不收集、不分享 | production 不开放内部性能/运行日志导出，也未接入远程行为统计或崩溃 SDK；无 AI 配置时不创建 AI 请求设备 ID |
| 传输中加密 | 不适用；无用户数据外传时按表单实际跳题处理 | 不为“本地回环 HTTP”虚构 TLS，也不勾选不存在的公网传输 |
| 用户是否创建账号 / 使用第三方账号 | 无账号创建或登录 | 不需要提供测试账号或账号删除网址 |
| 数据删除 | 本地记录由用户清除应用存储或卸载删除；无服务器账户可删 | 如果表单仍要求删除说明，填本地删除方法，不能声称提供尚不存在的云端删除接口 |
| 安全审查、加密认证或徽章 | 不声明通过任何独立认证 | 当前没有相应证书/审核证据 |

Google 对只在设备处理且不发离设备的信息与“收集”的区分见[官方 Data safety 指南](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)。仍须考虑所有已打包 SDK，而不只 App 自己的 Dart 代码。

未来如开启 AI、远程素材、同步、统计或诊断上传，需先重新核对数据类别、服务商、用途和传输，更新政策及 Data safety；不能沿用本表的“否”。

## 权限与 API

| 项目 | 本版本用途 / 建议答案 |
|---|---|
| `INTERNET` | 训练视频由同设备回环 HTTP 服务交给系统 WebView。没有向公网收集训练记录的服务配置 |
| `ACCESS_NETWORK_STATE` | 媒体组件读取连接状态；不读取位置，不建立用户画像 |
| `WAKE_LOCK` | SDK 训练服务在会话期间持有带超时上限的 CPU 唤醒锁；页面另使用亮屏锁。不是后台定位或身体传感器权限 |
| `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK` | 最终候选清单确有声明，来自固定 SDK 的 `com.ugk.trainer.TrainingSessionService`，类型为 `mediaPlayback`。用于用户主动开始的跟练语音/提示音与会话计时，须提交真实 FGS 声明，不能填“未使用前台服务” |
| AndroidX 动态接收器签名权限（如合并清单出现） | 依赖生成的内部组件隔离权限，不能当成读取用户资料的授权 |
| 相机、录音、位置、照片/视频广泛访问、联系人、短信、电话、身体传感器、活动识别、Health Connect | 未使用，不申请，相关声明选无；若最终清单出现意外权限，先处理代码/依赖，不靠表单隐瞒 |
| 广告 ID | 不使用，无广告或广告 SDK |
| 无障碍、VPN、所有文件访问、包安装/查询、后台位置 | 未实现相应产品能力，不申请特殊用途资格；真实媒体播放前台服务另按下节申报 |
| 网络明文 | 公网明文禁用，仅 `localhost` / `127.0.0.1` 本机媒体例外；不是允许任意 HTTP 服务 |

所有准确权限名称、min/target SDK、组件及 debuggable 结论最终由签名 AAB 的合并清单落定，本表不把源码 manifest 当最终产物证据。

## 媒体播放前台服务声明

父任务最终候选清单已确认 `com.ugk.trainer.TrainingSessionService` 为非导出服务，声明 `foregroundServiceType="mediaPlayback"`、`stopWithTask="true"`，以及上述两项 FGS 权限和 `WAKE_LOCK`。这是 SDK 的真实功能，不为通过扫描而删除服务或隐瞒权限。

| Console 问项 | 可审阅答案草稿 |
|---|---|
| FGS 类型 / 具体用途 | **Media Playback / 媒体播放**：用户主动开始一次带语音/提示音的健身跟练，锁屏或切到后台时继续播放指导。不要改报并未声明的 health、dataSync、location、microphone 或 full-screen intent |
| 对应 App 核心功能 | 动作/套路跟练中的本地指导音频和计时；不用于广告、自动启动的背景配乐或常驻联网 |
| 用户如何启动 | 首页选动作或套路 → 完成安全确认 → 计划页点击开始跟练 → 进入 SDK 训练播放器。不是在 App 冷启动或开机时自动播放 |
| 若服务延迟启动 | 用户已按开始，但开场提示/训练节奏不能按预期即时开始；不能将一段当前进行的指导播放当成可延后的后台任务 |
| 若系统中断 | 语音提示或提示音可能断开，锁屏/后台的会话时序也可能受调度影响，用户可能错过换动作/结束提示。这是使用理由，不是本轮已经量化证明的全部后台行为 |
| 用户如何察觉和停止 | 播放器显示进度并播放指导；SDK 创建“训练进行中”的持续通知和媒体会话。用户可返回 App 暂停/结束训练；结束、不适停止、离开播放器或销毁页面时释放服务，结束语允许短暂尾音后释放。移除任务时服务 `stopWithTask=true`。通知上的外部播放按钮未实现，不要声称可直接从通知暂停/停止 |
| 运行期限 | 绑定当前训练会话，具有会话结束/退出清理及 CPU 唤醒锁安全超时；不是无限期后台服务 |
| 演示视频链接 | **待录制并由开哥提供可访问链接；本轮尚未上传视频或通过 FGS 审核** |

English description draft:

> The media playback foreground service supports a workout the user explicitly starts. It keeps locally stored spoken exercise guidance and chimes available when the user locks the screen or leaves the activity, while the current workout timer continues. Deferring the service would delay the guidance the user just requested; interrupting it could cut off exercise-change or completion cues. The app presents workout progress and a training notification. The user can return to the player to pause or end the session. The service is released when the session ends or the player is left, with a short allowance for closing audio. It is not started for advertising, background music on app launch, or remote data collection.

实际实现边界：`TrainerPlayer.keepAlive` 默认开启；即使语音和提示音均关闭，固定 SDK 仍会持有该类型的训练服务，`mediaPlayback` 布尔仅控制系统媒体会话状态，并非 Service 启动开关。暂停时会同步暂停状态，但服务仍跟随会话保留。因此不能把答案写成“只在声音开启或每一段有声播放期间启动”。静音/暂停路径的必要性及持续时间需结合真机证据和 Play 反馈复核，本草稿不保证 Google 会接受所有路径。

演示视频拍摄清单（不是已完成证据）：

1. 显示最终候选身份，打开 App，按正常按钮选择动作/套路并进入训练；不要自动启动音频冒作用户操作。
2. 在语音/提示音开启的真实训练中展示可听见的指导与计时。
3. 切到后台或锁屏，展示仍在播放的真实音频及系统训练通知/媒体会话，再回到播放器；Android 不同通知展示规则应如实录制。
4. 在 App 内暂停/继续，再明确结束或离开训练，展示音频和服务通知停止。不要伪造通知外部控制按钮。
5. 视频仅用非私人测试记录，不展示密钥、序列号、账号通知或其他应用的私人画面。提供审核人员可访问的真实视频链接，不能把本地文件路径或本清单当成链接。

Google 要求 Android 14+ 的已用 FGS 类型提供用途、延迟/中断影响及触发流程演示，详见[FGS 声明说明](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)；mediaPlayback 对应后台音视频播放，见[Android 类型定义](https://developer.android.com/develop/background-work/services/fgs/service-types#media)。是否批准由 Play 审核决定，不等于静态 allowlist 或 AAB 扫描通过。

## 健康与医疗声明

- 属于健康健身相关应用，应填写 Health apps declaration；不能选“没有健康功能”。
- 功能选择建议：**Activity and Fitness / 活动与健身**。只提供一般动作、固定套路、计时和本地完成记录。
- 不选医疗设备、诊断、治疗、远程医疗、医疗研究、健康记录云端管理、营养或减重服务等未实现功能。
- 无穿戴设备、相机动作捕捉、健康平台接入或传感器精度声明。
- 安全筛查只用于保守限制训练，不是疾病诊断、风险评分或医疗建议。
- 商店中英文描述及 App 内均保留一般健身与非医疗器械说明；不能宣传治病、疗效、康复保证或自动纠正姿势。
- 隐私政策正文已准备；**公开 HTML URL 尚缺**。Google 的健康政策要求可公开访问的政策网址，以及 App 内政策链接或正文。[政策原文](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en)

## 其他 App 内容

| 项目 | 草稿答案 / 需开哥确定的部分 |
|---|---|
| 应用访问权限 / App access | 所有本版本核心功能无需登录；无凭据。训练先完成安全确认；风险回答“是”会保守限制训练，不得指导审核员虚假回答健康问题 |
| 广告 | 不含广告 |
| 应用内购买 / 订阅 | 无 |
| 社区 / 用户互动 / UGC 分享 | 无公开社区、用户间聊天、发布或交换内容 |
| 新闻、政府、金融、赌博等声明 | 无对应功能；以后台实际问项为准 |
| 内容分级 | 由开哥完成 IARC。代码未见赌博、付费随机奖励、公开交流或暴力玩法；健身人体/肌肉教学图像需按实际素材回答，不代填最终评级 |
| 目标年龄 | **待开哥确定**。本版本未宣称面向儿童，也未完成儿童定向合规评估；不可为了绕开问卷随意选择年龄 |
| 国家/地区、免费或付费、分发设备 | **待开哥确定**；现有构建以手机验证为主，不声称已验证平板、Wear OS、TV 或汽车 |
| 商店支持邮箱 | `mhgd3250905@gmail.com` |
| 隐私政策 URL / 发布主体 | **待开哥提供**；不能填写本地路径或占位域名 |

## 审核说明可用草稿

中文版：

> SmartFit 1.0 为无需账号的基础健身跟练版。首页可选择动作或固定训练套路。首次开始训练前会展示安全说明及四项风险确认；安全状态不允许训练时仍可浏览示范。正常流程为选择动作/套路、开始跟练、完成后查看本地训练记录。此版本不开放聊天或联网生成，不提供付费订阅。所有审核步骤均可在 App 内正常进入。

English:

> SmartFit 1.0 is an account-free basic workout app. Choose an exercise or a fixed routine from the home screen, review the safety information, and complete the safety check before starting training. If training is restricted by the safety check, demonstrations remain available for browsing. The normal flow is selection, timed practice, completion, and local workout history. This version has no chat, online generation, or subscription. The current interface and voice guidance are primarily in Simplified Chinese.
