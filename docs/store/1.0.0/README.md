# SmartFit 1.0 发布资料

当前发布版本为 **1.0.0+25**，AAB源码 `9d7bcff629be8c33bed6e12b0285314ad514f9d6`，已完成构建、真机简测和送审。2026-10-24 14:49提交编号1，15:45刷新确认后台记录 **15:02已发布Alpha封闭测试**；不是公开Production。包哈希和完整范围见[版本台账](../../version-management.md)、[验收记录](../../acceptance.md)及[版本存档](../../reports/version-save-1.0.0+25-2026-10-24.json)。

原有界面和完整93项训练元数据范围保留，仅修正生产素材发布配置、两处资料适配，并在设置的既有隐私区增加公开政策链接。本目录其他声明/清单保留准备阶段草稿语境，最终完成状态以本页和版本存档为准；不能把草稿待办当成尚未上传，也不能把简测写成全项验收。

| 项目 | 当前事实 / 配置 |
|---|---|
| 发布分支 | `release/1.0`，原界面基线 `main@f5332bf`；本分支处理上架/审核问题，修复后再合回 main |
| Android 身份 | `com.ugk.smartfit`，首版免费下载；当前无购买或订阅。以后增加会员不要求改为付费下载，但须另实现结算并更新声明 |
| Play 条目 | SmartFit 智能健身助手；应用 ID `4974885907919443404`；开发者公开名称 **Bboy Ug1yk**（不是对法定名称的推断） |
| SDK | `ugk_coach 0.3.3` / `ugk_trainer 0.1.6`，均固定 `f684e02f38e652633c23fa8946a53d02b6aa3ea2` |
| AI | 不注入 API Key；原 AI 入口和本地规则回退保留，不提供在线 AI 回复 |
| 素材 | 根据用户明确授权发布 App 既有完整93项范围；其他无 App 训练元数据的动作不因此自动放行。见 [发布授权记录](production-media-authorization.json) |
| 两项适配 | `s-figure4` 仰卧脚踩地版的四条相关提示/语音；`w-dead-bug` 每次交替节奏4秒；已随打包源码提交并校验 |
| 远程素材 | `https://smartfit-media.pages.dev/v0.3.0-app/`，沿原按需下载及 SHA/字节校验；不是 AI 接口或密钥 |
| 隐私 / 条款 / 支持 | [隐私](https://smartfit-store.pages.dev/privacy/) / [条款](https://smartfit-store.pages.dev/terms/) / [支持](https://smartfit-store.pages.dev/support/)；邮箱 `mhgd3250905@gmail.com` |

## 已完成的后台准备

2026-10-24，用户授权由 Agent 操作 Play、YouTube 和 Cloudflare，并分别明确同意创建应用声明和 IARC 条款。Play 应用设置已完成 **11/11**；目标受众为13–15岁、16–17岁和成年人；当前免费、无广告、无需登录、非政府、无金融功能，健康类别为活动与健身。IARC 问卷已完成，后台生成 ESRB Everyone、PEGI 3 等分级；内容分级不是把目标受众改成儿童。

Alpha 封闭测试已选后台可提供的178个国家/地区，独立测试名单仅加入账号本人邮箱；送审时0人选择参与，当前没有新增参与证据。正式发布需先满足后台实际要求的 **至少12人连续参与14天封闭测试**；不能用本地验收或名单人数代替实际参与。

中英文文案、正式图标/置顶图、4张+25真实手机截图和[约75秒演示](https://www.youtube.com/watch?v=tJ6BGgvRjWA)已最终保存，FGS选择媒体播放并使用该视频。视频为真实开始、后台语音、返回暂停和提前结束，已验证匿名可播；合成指导语音和3D示范如实披露。App内隐私/条款正文已实际打开，公开网站与素材站已部署。

Data safety已按Cloudflare素材请求更新：App interactions和设备/其他标识均收集/分享、非临时处理、必需，用途为应用功能及防欺诈/安全/合规、HTTPS；不声称上传本地聊天/健康回答/完整训练记录，也不承诺网络安全日志自动删除。

## 历史候选及更正

- `1.0.0+23` 曾引入新首页和隐藏 AI 的方案，已按用户指示撤销，不能上传或复用其截图。
- `1.0.0+24` 恢复原界面、无 Key，并已上传到 Play 的 **HOLD 草稿，未送审、未分发**。Google 已解析 min24/target36。其生产清单189项均待发布，导致真机动作库0；原验收完整包为开启素材预览的 `internal / 2022`，不能拿内测演示冒充生产包。
- +24 时保存的 Data safety “不收集/不分享”只对应当时无远程素材源的候选。+25 增加 Cloudflare HTTPS 素材请求后必须重新核对并更新，不能直接继承。

## 后续发布工作

1. 组织真实测试者参与已发布的封闭测试，达到12人连续14天后申请正式发布资格。
2. 记录实际测试/审核反馈；仅在release/1.0修正上架问题，修复后另行合回main。当前没有Production公开发布事实。
3. 连续>20分钟、广泛设备矩阵和iOS专项仍未覆盖，不以本次2/8提前结束简测或75秒演示替代。

[商店文案](store-listing.json)、[Play 声明](play-declarations.md)、[隐私中文](privacy-policy-zh-CN.md) / [English](privacy-policy-en-US.md)、[素材清单](assets-manifest.json)、[事实依据](evidence-and-sources.md)、[Mac 接力](mac-handoff.md) 构成本目录。签名密钥、密码和本机登录态不得进入本目录或 Git。
