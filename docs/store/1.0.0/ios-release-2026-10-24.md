# SmartFit iOS 1.0.0 (25) 本机发布记录

状态：**TestFlight `1.0.0 (25)` 已上传、处理完成并保存出口合规，当前显示“准备提交”；未提交 App Store 审核**。2026-10-24 18:42（Asia/Shanghai）Xcode 确认上传成功，18:49:45 观察到处理完成，19:01 保存合规答案，19:02:26 刷新核对后状态仍为“准备提交”。尚未分配测试群组或安装测试。

## 候选与范围

- Bundle ID：`com.ugk.smartfit`；版本 `1.0.0`，Build `25`，仅 iPhone，最低 iOS 15。
- 发布运行源码：`release/1.0@638d4917d57ed662d5bb4133efeda33ce5907120`。继承 Windows 已保存的 +25 原界面、93 项训练内容和 SDK 固定版本。
- 两项 SDK 依赖均为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`；`pubspec.lock` 未改，未新增依赖。
- 用户本轮已明确修正为：**保持原界面，不填写 AI Key**。因此原 AI 设置和文案仍保留，不再执行最初隐藏 AI 入口的要求。构建不传 AI Key、AI endpoint 或 dart-define 配置文件；仅设置公开素材 CDN。
- 本轮未修改 `lib/`、Android、版本常量或依赖。团队专属签名配置、账户、证书、描述文件及产物只留本机，不进入 Git。

## 已推送的代码

| 分支 | 提交 | 内容 |
| --- | --- | --- |
| `release/1.0` | `7b12627ee5bc729e58de9b4ad362c0eccb6de1aa` | 仅 iPhone、Automatic 签名方式、SmartFit 显示名、本机媒体网络例外及训练后台音频；发布守卫只允许这些 Info.plist 改动 |
| `release/1.0` | `638d4917d57ed662d5bb4133efeda33ce5907120` | 用已有且已批准的 App 图标替换 Flutter 启动占位图，限制启动图为 144pt；没有新生成或改画图标 |
| `main` | `5b65cd7eab90ccfca32f88752965b0309604a180` | 已同步上述 iOS 平台配置与 production scheme；main 的后续 SDK、Android 和共享业务代码保持原状 |

main 与 release 已分叉开发，本次仅同步 iOS 文件，没有把 release 的旧 SDK、版本和业务代码覆盖到 main。发布包始终从 `release/1.0` 构建。

## 工具链和验证

本机使用 README 明确兼容的 Flutter **3.44.7 / Dart 3.12.2**，Xcode **26.6 (17F113)**，CocoaPods **1.16.2**。依赖采用工程既有 Swift Package Manager 集成。

- `flutter pub get --enforce-lockfile` 成功，lock 未变化。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub`：435 通过、13 跳过；跳过项不声明为通过。
- 发布合同检查：8 项通过；`git diff --check`、两个 plist / project 文件语法检查通过。
- 启动页 `ibtool` 编译：0 error、0 warning。
- iOS Simulator Debug 及 iPhone arm64 Release 原生编译通过。
- 6.7 英寸及 6.5 英寸模拟器分别实际完成安全确认 → 选择“运动前热身” → 连续训练 → 自然完成，两轮结果均为 **5 分钟 / 6/6 动作**，未观察到崩溃。
- 默认“仅在 Wi-Fi 下载”策略会阻止模拟器的非 Wi-Fi 网络获取未内置示范。运行时读取得到 `Waiting for Wi-Fi`；关闭该模拟器内的开关后视频正常显示。没有修改 App 默认策略、SDK 或 pub 缓存。
- 解析后的原生 App 为 `UIDeviceFamily = [1]`、`UIBackgroundModes = [audio]`、`NSAllowsLocalNetworking = true`；未添加相机、麦克风、定位用途说明。
- 原生 Release 含 6 份可解析的隐私清单，各份 Tracking 为 false。常见 token / 私钥模式扫描未发现匹配，未发现 `.env` 或私钥 / 证书导出文件；这不替代最终签名 IPA 验包。

## 本地产物

- 最终归档：`build/ios/archive/Runner.xcarchive`，源码 `638d491`，约 219.6 MB。最终归档已消除默认启动图占位警告。
- CLI 曾返回 `No Accounts` 和缺少分发描述文件；Xcode GUI 中账号及 `kai sheng` 团队实际存在。已通过 Organizer 自动签名完成分发资源准备和 IPA 导出，无需重新登录或手动导出私钥。
- **实际上传的 IPA**：`build/ios/ipa/SmartFit-1.0.0-25-upload/smartfit.ipa`，**53,355,310 bytes**，SHA-256 **`49d279d7713f81cc7425716546e6528b8097e24d8efb3b4afe469c9127d2dd0c`**。
- 本机未安装 Transporter，使用 Organizer Custom → App Store Connect → Upload；关闭自动管理版本 / Build 号。点击 Upload 前已定位该次 Xcode pipeline 的实际临时 IPA，独立验包并保留逐字节一致的副本；上传后临时包哈希仍一致。初次本地导出稿已移到本机私密构建目录，避免与实际上传包混淆。
- 最终验包通过：`codesign --verify --deep --strict`、Bundle / 版本 / Build、arm64、`get-task-allow=false`、`beta-reports-active=true`、显式匹配 `com.ugk.smartfit` 的 App Store 分发描述文件、无调试设备限制、6 份隐私清单语法。常见 token / 私钥及秘密文件检查未发现凭据；符号文件中一次宽泛匹配已核实为 C++ `highp` 函数标识符，加入标识符边界后无凭据匹配。
- 截图目录：`build/ios-release-evidence/screenshots/`，不提交 Git。6.7 英寸为真实 1290×2796，6.5 英寸为真实 1242×2688，均通过 `simctl io screenshot` 获取，没有缩放造图。这些是模拟器 Build 25 预检素材，不是 TestFlight 真机验收证明。
- 两种尺寸均已保存动作库、训练中和完成页，共 6 张。下载包：`build/ios-release-evidence/SmartFit-1.0.0-25-iPhone-screenshots.zip`（9,164,711 bytes，SHA-256 `d63a4462919eb78a801f8576bcdb311a536ca71fc8c120421f35c41916a3233d`）；本地候选元数据为同目录的 `candidate-manifest.json`。
- 隐私填写草稿：[ios-privacy-draft.md](ios-privacy-draft.md)。尚未在 ASC 保存 App Privacy 答案。

## Apple 后台与授权边界

指定的 Playwright MCP profile 位于 `/Users/shengkai/.local/share/ugk-browser/chrome-profile`。用户已授权重启原占用浏览器，当前已由 MCP 接管并完成用户亲自认证。没有复制 Cookies、密码、token 或 profile 内容。

用户已明确确认注册 Bundle ID 并创建以下记录；现已在 `kai sheng` 团队完成：

| 字段 | 已创建值 |
| --- | --- |
| 名称 | SmartFit 智能健身助手 |
| Bundle ID | com.ugk.smartfit |
| 平台 / 主要语言 | iOS / 简体中文 |
| SKU / 访问权限 | smartfit-ios-1.0 / 页面默认完全访问权限 |

- ASC App ID：**`6826550088`**；[App 记录](https://appstoreconnect.apple.com/apps/6826550088) / [TestFlight](https://appstoreconnect.apple.com/apps/6826550088/testflight/ios)。
- App Store 版本草稿已保存为 **1.0.0 / 准备提交**，与包身份一致。没有点击“添加以供审核”。
- 18:42 上传成功；TestFlight 处理完成后曾提示缺少出口合规。19:01 保存答案后，**版本 1.0.0，构建版本 25，准备提交，90 天后过期**；刷新后“缺少出口合规证明”计数为 0。
- 未添加测试员或群组，未开启测试通知、外部 Beta Review、正式 App Review 或公开发布。App Privacy 答案与截图已准备在本机，尚未代开哥保存 / 提交商店隐私声明。

出口合规已按素材下载的 `Dart HttpClient` / 标准 TLS 实现选择“标准加密算法”，并根据开哥明确回复“本次不向法国分发”将法国问题保存为“否”。分类依据 [Dart 3.12.2 的 SecureSocket 实现](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/bin/secure_socket_filter.cc)；[Apple 文档](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)列出标准算法与法国分发的文稿要求。此处保存的是合规问卷，未代选 App Store 国家 / 地区；送审地区需与该答案一致，将来开放法国前重新核对。

本轮上传与合规操作已完成，无需再提供账号、密钥或附件。后续由开哥安排测试群组与真机验收，复核正式商店资料、隐私声明和发布地区，再自行提交 App Store 审核。

## 后续商店草稿准备

开哥随后要求继续推进，并明确确认保存 ASC 草稿。2026-10-24 已通过同一 Playwright 登录态保存副标题、“健康健美”类别、推广文本、描述、关键词、支持和营销 URL、审核备注、无需登录设置、Build 25 关联及手动发布。重新打开页面后，文本与本地填写稿逐项一致，构建与设置保留；没有提交审核。

原六张截图已上传到对应大屏分组。ASC 当前额外将 6.1/6.3 英寸的中等灵动岛显示屏列为必填，因此补拍相同运行源码的 iPhone 15 Pro / iOS 26.5 真实界面三张（1179×2556），未改像素或缩放原图。本轮再次实际完成本地计划 → 训练 → 自然完成，结果 5 分钟 / 6/6 动作，未观察到崩溃。19:40:39 刷新媒体管理后，三个分组各显示 3/10 张截图，无尺寸或上传错误。补拍使用模拟器，不是最终 TestFlight 真机验收；测试后模拟器已关闭。

新增完整截图包 `build/ios-release-evidence/SmartFit-1.0.0-25-all-iPhone-screenshots.zip`，12,857,865 bytes，SHA-256 `36735405be4a9cf6b57d037662d59a274da9e34edb55393d21dcef1f493c9bcd`；原六张包与实际上传 IPA 均保持原哈希。详情见 [商店草稿交接](ios-submission-handoff.md) 及 [字段与九张截图校验信息](ios-app-store-draft.json)。[iOS 政策补充稿](ios-policy-supplement-draft.md) 仍在本机待复核，未部署网站；版权、审核联系人、最终隐私声明、年龄分级及分发地区仍留待定稿，未添加测试群组或邀请。

## 开哥授权推进正式审核后的状态

2026-10-24，开哥进一步明确授权 Agent 推进正式 App Review，覆盖此前由开哥自行送审的边界；公开正式发布仍未授权，继续采用手动发布。

- 已完成并保存 13+ 年龄分级、含许可第三方素材的内容版权声明、非受监管医疗设备声明；重新打开 App 信息页确认保留。
- 已设置免费定价，关闭 Mac 与 Apple Vision Pro 兼容供应，按仅 iPhone 范围保存；国家/地区供应范围尚未保存，等待开哥回复本轮范围问题，法国继续排除。
- 两类隐私标签答案和政策 URL 已保存到 ASC 草稿，20:44:51 核对保留，尚未点击隐私“发布”。双语 iOS 政策与支持页的站点源码及直接上传包已准备，链接和浏览器检查通过；Cloudflare Dashboard 停在登录页，已请开哥亲自登录，未复制认证数据或部署网站。
- 已执行一次 Apple“添加以供审核”校验，实际返回必填资料缺失，**没有进入审核队列**。版权主体与审核联系人仍为空，隐私标签仍待发布；校验指出的内容版权页面级保存现已补齐并刷新验证。
- 待开哥提供版权显示名、私下填好审核联系人、确认分发范围并完成 Cloudflare 登录后，可继续政策发布、最终校验及送审；同一审核动作不再重复索要授权。

最新详细结果见 [送审交接](ios-submission-handoff.md)、[隐私记录](ios-privacy-draft.md) 与 [待部署政策站](site/README.md)。运行代码、Build 25 分发 IPA 及其哈希保持不变；没有把模拟器截图写成 TestFlight 真机验收。
