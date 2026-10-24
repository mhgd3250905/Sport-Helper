# SmartFit 1.0 原界面发布草稿

状态：仅发布准备，**未上传、未保存 Play 后台配置、未提交审核**。本目录不代表上架或审核已通过。

| 项目 | 本轮约定 |
|---|---|
| 发布分支 | `release/1.0`，从 `main@f5332bf` 建立；仅处理上架/审核问题，修复后再合回 `main` |
| App / Android 身份 | SmartFit / `com.ugk.smartfit`，不可在首次上传后另换包名 |
| 候选版本 | `1.0.0+24`；实际 AAB 版本、签名与源提交须以父任务产物回执为准 |
| SDK | `ugk_coach 0.3.3`、`ugk_trainer 0.1.6`；均固定 `f684e02f38e652633c23fa8946a53d02b6aa3ea2` |
| 配置 | 恢复已验收 `main@f5332bf` 的原界面和功能，不注入 API Key；原聊天、AI 入口、AI 记忆设置与本地规则回退保持原样，不保证空 key 的联网 AI 路径可用 |
| 支持邮箱 | `mhgd3250905@gmail.com` |
| 发布主体 / 隐私 URL | 待开哥补齐，不填造身份或网址 |

## 文字与表单

- [store-listing.json](store-listing.json)：中英文标题、短描述、长描述；英文稿明确当前界面和语音主要为简体中文。
- [privacy-policy-zh-CN.md](privacy-policy-zh-CN.md)、[privacy-policy-en-US.md](privacy-policy-en-US.md)：隐私正文草稿，含近期对话/安全问答、本地设备 UUID、训练记录、系统备份可能性及删除方式。
- [play-declarations.md](play-declarations.md)：Data safety、权限、健康声明、广告、账号、内容分级和年龄答案草稿。
- [evidence-and-sources.md](evidence-and-sources.md)：代码依据、SDK依据、官方政策核对和适用边界。
- [assets-manifest.json](assets-manifest.json)：正式 A2 图标来源、真实截图拍摄项目、Feature Graphic 规格及当前准备状态。最终文件和哈希由实际生成/拍摄步骤补齐。
- [mac-handoff.md](mac-handoff.md)：Mac 从同一分支核对版本、SDK、无 AI 配置后编 iOS 包；不含签名私密值。

## 提交前必须补齐或确认

1. 与 Play 开发者账号一致的正式发布主体名称。
2. 承载最终政策的公开、无需登录且非地域受限 HTML 网址；本地 Markdown 不能当成已公开的隐私政策 URL。
3. 开哥确认目标受众、国家地区、商店定价与最终 IARC 问卷。草稿不代替账号/商业选择。
4. 确认截图来自恢复原界面的 `1.0.0+24` 签名候选，不使用已废弃的 +23 新首页截图；素材不得含私人记录、通知、账号或测试菜单。
5. 核对最终 AAB 清单、未注入密钥、签名和主流程证据。原代码公开服务地址及可见 AI 文案保持不变，不再承诺包中没有服务地址或所有 AI 入口均隐藏。
6. 检查 Play 账号是否有封闭测试、账号验证或其他平台门槛；本轮没有登录后台，不能代替开哥确认。

本分支没有发布权限：由开哥在 Google Play 自行填写、上传和提交。上传密钥、密码与 App Store 签名材料不进入本目录或 Git。
