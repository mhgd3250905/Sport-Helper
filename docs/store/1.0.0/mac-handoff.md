# Mac / iOS 接力：同一基础版发布分支

仅说明 Mac 端后续构建方法。**Windows 本轮没有构建、签名、安装或提交 iOS 包。**

## 版本和源码

1. 在 Mac 的干净工作副本获取 `origin/release/1.0`。已有改动先保留，不 reset、不覆盖。
2. 首次跟踪该分支时使用 `git switch --track origin/release/1.0`；已存在则 `git switch release/1.0` 后 `git pull --ff-only origin release/1.0`。
3. 核对 `git rev-parse HEAD` 与本轮交付回执的 release SHA。Mac 不从会继续开发的 `main` 打此基础候选。
4. `pubspec.yaml` 和 App 版本常量应为 `1.0.0+24`。若 Apple 平台已占用这个 build，需先核实并按发布规则增加，不能复用旧 build。
5. `ugk_coach 0.3.3`、`ugk_trainer 0.1.6` 均固定 Git commit `f684e02f38e652633c23fa8946a53d02b6aa3ea2`。执行 `flutter pub get --enforce-lockfile`，不可运行升级命令；确认 `git diff -- pubspec.lock` 为空。

## 构建

仓库包含共享 `production` scheme 及对应 Debug/Release/Profile-production 配置；原 Runner 配置保留。父任务在 Windows 仅检查 XML/PBX 配置合同，Mac 仍须实际编译验证。

在 `ios/Runner.xcworkspace` 中核对 Runner 的 Apple Team、`com.ugk.smartfit` Bundle ID、provisioning 和发布证书。Apple 签名材料只由 Mac 端保管，不从 Android 上传密钥复制，也不进入 Git。

```sh
flutter analyze
flutter test
flutter build ipa --release --flavor production --build-name 1.0.0 --build-number 24
```

此候选**不注入 API Key 或旧开发密钥 dart-define 文件**。沿用已验收 `main@f5332bf` 的原界面与功能，原公开服务地址、可见 AI 入口和本地规则回退不做重设计。不要调用会注入密钥的历史包装脚本，也不要把 Windows 本地覆盖配置、SDK 工作树路径或 Android keystore 搬到 Mac。

## Mac 端必须实际核验

- 签名、Bundle ID、版本与源 SHA；无 API Key 注入。
- 原对话式安全确认、本地规则/模板计划、动作库、训练、完成和记录。
- AI 入口和记忆设置保持原样可见，空 key 不提供在线 AI 回复；不套用已经废弃的新首页/隐藏入口验收要求。
- WKWebView 的本机媒体播放、音频、前后台、横竖屏与权限实际行为；不能用 Android 通过替代 iOS 通过。
- 图标为已批准 A2，iOS 隐私说明/Privacy Manifest 和 App Store Connect 数据声明与实际包一致。
- 从实际 iOS 候选获取截图；不要把 Android 截图冒作 iPhone 截图。
- 保留原平台备份行为并在对应隐私声明中准确描述，不能沿用已撤销的“系统备份关闭”承诺。

测试、导出、上传 TestFlight 和提交 App Store 是不同步骤。此任务没有授权任何 Apple 后台操作；需要由开哥安排 Mac 端签名与后续平台步骤。
