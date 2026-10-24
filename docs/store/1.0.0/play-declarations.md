# Play 表单答案草稿

适用范围：`release/1.0` 目标候选 **1.0.0+25**。保留原对话首页、完整93项 App 动作范围和本地规则；用户已明确允许修正生产发布资格、figure4四条相关提示/语音及 dead-bug 4秒节奏，并增加必要政策入口。AI Key 为空；远程素材改用 Cloudflare HTTPS。**+25 构建、真机验证、视频、YouTube上传和 Play 送审尚未在此文确认完成。**

2026-10-24 后台实际：+24 已上传 HOLD 草稿而未送审；设置完成10/11，IARC问卷已完成，受众13+、首版免费、Alpha地区178个、测试名单仅本人邮箱。此前“未操作Play后台”和“无远程素材源”是 +24 前的历史状态，不能用作当前 +25 填表依据。

## Data safety：+25 的填报口径

+24 的“不收集、不分享”是无远程素材源历史候选的已保存答案，**不可沿用到 +25**。+25 的媒体及政策页面HTTPS请求向Cloudflare暴露IP、请求时间、User-Agent/HTTP元数据和可能含动作标识的资源路径。以下为主任务已确定的 +25 更新口径，仍须由实际Console保存和最终包网络验证落定，不能写成已经更新后台或已获Google批准。

| Console 数据项 / 问项 | +25 答案及范围 |
|---|---|
| 是否收集或分享必须披露的数据 | **是** |
| Device or other IDs / 设备或其他标识 | **收集：是；分享：是**。对应网络IP及请求技术数据，不是App主动附加本地UUID |
| App activity → App interactions / 应用活动→应用互动 | **收集：是；分享：是**。对应所请求的素材/页面路径及动作资源交互，不是上传完整训练完成记录 |
| 是否仅临时处理 | **否 / non-ephemeral**；不承诺无日志或仅在内存中处理 |
| 是否为用户提供选择 | **必需 / Required**：相关联网素材/页面请求所需的网络处理；不因Wi-Fi策略或不打开页面而把该处理填作可选收集 |
| 用途 | **应用功能；防欺诈、安全与合规** |
| 传输中加密 | **是，HTTPS**；本机回环不作为公网传输，系统备份按平台实际条件另述 |
| 位置 | 不利用IP推导位置，不申报未实现的定位采集；不读取GPS或后台位置 |
| 健康问答、完整计划与完成记录、聊天/AI记忆 | 保存在本机，不附加给CDN；不将这些内容误报为已上传。请求路径可能含动作标识已按App interactions披露 |
| 本地设备UUID | 无Key不发AI请求，不附加到媒体CDN；不能把这一事实推出IP未传输 |
| 删除 | 本地数据由系统清除存储/卸载管理；网络安全/访问日志不承诺App内自动删除或保证立即远程擦除。支持邮箱可受理资料处理请求，按实际规则答复 |
| 账号 | 无账号创建/登录，无测试凭据或虚构的云端账号删除接口 |
| 独立安全认证 / 徽章 | 不声明未获得的认证 |

Cloudflare作为分发服务的处理范围、请求路径与IP已按上述口径保守申报收集/分享，不笼统套用“CDN全为豁免处理商”。Android默认系统备份/迁移在隐私政策独立披露；allowBackup=true本身不证明App主动上传，也不证明所有平台备份满足同一豁免。

依据：[官方Data safety定义](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)、[Android Auto Backup](https://developer.android.com/identity/data/autobackup)、[Cloudflare隐私政策](https://www.cloudflare.com/privacypolicy/)。未来启用AI、会员结算或其他联网服务时再次更新；本版本不因未来可能收费而申报当前不存在的购买功能。

## 权限与 API

| 项目 | 本版本用途 / 建议答案 |
|---|---|
| `INTERNET` | 本机回环媒体播放、Cloudflare HTTPS素材下载和公开政策页。下载/页面会产生上述网络元数据，不上传完整训练记录 |
| `ACCESS_NETWORK_STATE` | 媒体组件读取连接状态；不读取位置，不建立用户画像 |
| `WAKE_LOCK` | SDK 训练服务在会话期间持有带超时上限的 CPU 唤醒锁；页面另使用亮屏锁。不是后台定位或身体传感器权限 |
| `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK` | 已核验+24清单确有声明；+25保持同一固定SDK并须重新验最终清单。服务来自固定 SDK 的 `com.ugk.trainer.TrainingSessionService`，类型为 `mediaPlayback`。用于用户主动开始的跟练语音/提示音与会话计时，须提交真实 FGS 声明，不能填“未使用前台服务” |
| AndroidX 动态接收器签名权限（如合并清单出现） | 依赖生成的内部组件隔离权限，不能当成读取用户资料的授权 |
| 相机、录音、位置、照片/视频广泛访问、联系人、短信、电话、身体传感器、活动识别、Health Connect | 未使用，不申请，相关声明选无；若最终清单出现意外权限，先处理代码/依赖，不靠表单隐瞒 |
| 广告 ID | 不使用，无广告或广告 SDK |
| 无障碍、VPN、所有文件访问、包安装/查询、后台位置 | 未实现相应产品能力，不申请特殊用途资格；真实媒体播放前台服务另按下节申报 |
| 网络明文 | 公网明文禁用，仅 `localhost` / `127.0.0.1` 本机媒体例外；不是允许任意 HTTP 服务 |

所有准确权限名称、min/target SDK、组件及 debuggable 结论最终由签名 AAB 的合并清单落定，本表不把源码 manifest 当最终产物证据。

## 媒体播放前台服务声明

历史+24候选清单已确认 `com.ugk.trainer.TrainingSessionService` 为非导出服务，声明 `foregroundServiceType="mediaPlayback"`、`stopWithTask="true"`，以及上述两项 FGS 权限和 `WAKE_LOCK`。这是固定SDK的真实功能；+25应按最终合并清单确认，不为通过扫描删除服务或隐瞒权限。

| Console 问项 | 可审阅答案草稿 |
|---|---|
| FGS 类型 / 具体用途 | **Media Playback / 媒体播放**：用户主动开始一次带语音/提示音的健身跟练，锁屏或切到后台时继续播放指导。不要改报并未声明的 health、dataSync、location、microphone 或 full-screen intent |
| 对应 App 核心功能 | 动作/套路跟练中的本地指导音频和计时；不用于广告、自动启动的背景配乐或常驻联网 |
| 用户如何启动 | 在原对话首页完成安全确认 → 按原规则/模板准备计划或浏览动作 → 计划页点击开始跟练 → SDK 训练播放器。不是在 App 冷启动或开机时自动播放 |
| 若服务延迟启动 | 用户已按开始，但开场提示/训练节奏不能按预期即时开始；不能将一段当前进行的指导播放当成可延后的后台任务 |
| 若系统中断 | 语音提示或提示音可能断开，锁屏/后台的会话时序也可能受调度影响，用户可能错过换动作/结束提示。这是使用理由，不是本轮已经量化证明的全部后台行为 |
| 用户如何察觉和停止 | 播放器显示进度并播放指导；SDK 创建“训练进行中”的持续通知和媒体会话。用户可返回 App 暂停/结束训练；结束、不适停止、离开播放器或销毁页面时释放服务，结束语允许短暂尾音后释放。移除任务时服务 `stopWithTask=true`。通知上的外部播放按钮未实现，不要声称可直接从通知暂停/停止 |
| 运行期限 | 绑定当前训练会话，具有会话结束/退出清理及 CPU 唤醒锁安全超时；不是无限期后台服务 |
| 演示视频链接 | **待从实际+25生产包录制；用户已授权Agent上传YouTube并填写真实可访问链接。当前未录制/上传，也未通过FGS审核** |

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
- 公开隐私URL已部署：https://smartfit-store.pages.dev/privacy/ ，英文 /privacy/en/。+25代码增加原设置隐私区的可点击政策/条款入口；页面真机加载仍待最终包核验。Google 的健康政策要求可公开访问的政策网址，以及 App 内政策链接或正文。[政策原文](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en)

## 其他 App 内容：实际后台与当前候选

| 项目 | 已保存事实 / 后续边界 |
|---|---|
| App access | 已声明无需登录、无凭据；按真实安全确认、本地计划、动作示范和训练流程审核，不指示审核员虚假回答健康问题 |
| 广告 | 已声明不含广告，无广告SDK |
| 当前购买 / 订阅 | 无；当前免费下载。以后会员订阅与免费下载安装不冲突，但实现后必须另更新Billing、隐私和商店声明 |
| 社区 / 用户交互 / UGC | 无公开社区、用户间交流、内容发布或交换 |
| 政府 / 金融 | 已声明非政府、无金融产品和服务 |
| 健康 | 已保存 Activity and Fitness / 活动和健身；没有医疗设备、诊断/治疗或Health Connect能力 |
| IARC | 用户明确同意IARC条款后已完成问卷。其他所有应用类型；联机内容选是（策划的补充动作素材），无暴力/色情/冒犯性语言/药物/年龄限制商品、无定位共享/数字购买/现金奖励/浏览器；后台生成ESRB Everyone、PEGI 3、USK所有年龄段等。不是App发布审核已通过 |
| 目标受众 | 已保存13–15岁、16–17岁、18岁以上；不改为仅成年人，也不针对13岁以下儿童营销。内容分级与受众选择分开 |
| 价格 / 地区 | 首版免费下载；Alpha选择后台178个国家/地区。没有正式生产分发事实 |
| 测试门槛 | 当前名单仅本人邮箱，0人选择参与；必须真实招募至少12人连续参与14天后再申请正式版权限，不能凭名单条目或本地验收替代 |
| 支持 / 开发者 | mhgd3250905@gmail.com；公开名称Bboy Ug1yk，不臆造法定主体 |
| 隐私 / 网站 | https://smartfit-store.pages.dev/privacy/ ； https://smartfit-store.pages.dev/ ，公开无需登录 |

## 审核说明可用草稿

中文版：

> SmartFit 1.0.0+25 沿用已验收版本的原对话首页、动作库、计划和训练播放器，无需账号。首次在对话中完成安全说明及风险确认后，可使用本地规则和模板安排计划并跟练。原 AI 入口与设置保留可见，本候选不提供在线 AI 回复；部分动作内置，其他示范通过HTTPS按需下载。请沿本地计划、动作示范和训练路径验收。当前无购买或付费订阅；原设置隐私区提供公开政策入口。此说明须在+25实际验证后再用于送审。

English:

> SmartFit 1.0.0+25 retains the accepted conversational home, exercise library, plans, and workout player. No account is required. Complete the original safety conversation, then use local rules and templates to prepare and follow a workout. Existing AI entrances and settings remain visible, but online AI replies are not provided by this candidate. Some demonstrations are bundled and others are downloaded over HTTPS. Review the local planning, demonstration, and workout flow. There are no purchases or subscriptions in the current version. Public policy links are in the existing privacy section of Settings. Use these instructions for submission only after build25 is actually verified. The interface and voice guidance are primarily in Simplified Chinese.
