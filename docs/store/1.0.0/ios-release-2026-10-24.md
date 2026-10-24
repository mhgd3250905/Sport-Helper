# SmartFit iOS 1.0.0 (25) 本机发布记录

状态：**ARCHIVED，尚未导出 IPA / 上传 TestFlight / 提交审核**。以本文最新回执为准，不能把 Android 的发布结果或 Xcode 归档成功当成 TestFlight 已可用。

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
- CLI `flutter build ipa` 已完成归档，但导出返回 `No Accounts`、`No profiles for 'com.ugk.smartfit' were found`，当前 IPA 数为 0。Flutter 命令自身可能返回 0，因此已额外检查 IPA 是否实际生成。
- Xcode GUI 中已确认开哥账号及 `kai sheng` 团队存在。Organizer 能访问 App Store Connect，正在使用 Custom → App Store Connect → Export；已关闭自动管理版本 / Build 号，并跳过自动新建 App 记录。
- Organizer 停在 Automatically manage signing，后续会创建或更新 App ID / 描述文件。需先完成用户确认的 Bundle ID / App 记录创建步骤，再继续导出和验包。
- 截图目录：`build/ios-release-evidence/screenshots/`，不提交 Git。6.7 英寸为真实 1290×2796，6.5 英寸为真实 1242×2688，均通过 `simctl io screenshot` 获取，没有缩放造图。这些是模拟器 Build 25 预检素材，不是 TestFlight 真机验收证明。
- 两种尺寸均已保存动作库、训练中和完成页，共 6 张。下载包：`build/ios-release-evidence/SmartFit-1.0.0-25-iPhone-screenshots.zip`（9,166,755 bytes，SHA-256 `75088d5d51b355da819236cf30758f518839fe152fc93788b820e81859a70b5a`）；本地候选元数据为同目录的 `candidate-manifest.json`。
- 隐私填写草稿：[ios-privacy-draft.md](ios-privacy-draft.md)。尚未在 ASC 保存 App Privacy 答案。

## Apple 后台与授权边界

指定的 Playwright MCP profile 位于 `/Users/shengkai/.local/share/ugk-browser/chrome-profile`。用户已授权重启原占用浏览器，当前已由 MCP 接管并完成用户亲自认证。没有复制 Cookies、密码、token 或 profile 内容。

已在 `kai sheng` 团队应用列表核对：尚无 SmartFit。已准备但未提交的新建表单为：

| 字段 | 待确认值 |
| --- | --- |
| 名称 | SmartFit 智能健身助手 |
| Bundle ID | com.ugk.smartfit |
| 平台 / 主要语言 | iOS / 简体中文 |
| SKU / 访问权限 | smartfit-ios-1.0 / 页面默认完全访问权限 |

用户尚待确认注册 Bundle ID 并创建该 ASC 记录。未点击“创建”，未上传 IPA，未开启测试员通知、外部 Beta Review、正式 App Review 或公开发布。

下一步：获得记录身份确认 → 注册 / 创建记录 → Organizer 自动签名导出 → 验签、核对身份 / Profile / 隐私清单并记录 IPA SHA-256 → 上传同一 IPA 到 TestFlight → 等待 Apple 处理并交付 Build 状态。正式审核由开哥操作。
