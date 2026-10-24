# Mac / iOS 接力：release/1.0

Mac 本轮已完成 iPhone 专属配置、原生编译、分发 IPA 验包与上传 `1.0.0 (25)`，运行源码为 `638d491`；App 记录已创建，TestFlight 处理状态以 [2026-10-24 iOS 本机发布记录](ios-release-2026-10-24.md) 为准。本轮用户再次确认保留原界面，只是不填写 AI Key；iOS 专属改动已同步 main，未覆盖 main 后续业务开发。

目标版本 **1.0.0+25**，打包源码 `9d7bcff629be8c33bed6e12b0285314ad514f9d6`；其后文档保存提交不改变运行代码或版本。保留原界面和完整93项范围，包含用户批准的生产素材配置/资料适配及必要政策链接。Android已完成简测并于2026-10-24 15:02发布到Alpha封闭测试（本次15:45刷新确认），不是Production公开发布。**Windows没有构建、签名、安装或提交iOS包；Android结果不等于iOS通过。**

## 源码和依赖

1. 在 Mac 干净工作副本获取 `origin/release/1.0`；保留已有改动，不 reset、不覆盖。首次跟踪用 `git switch --track origin/release/1.0`，已有分支用 `git switch release/1.0` 和 `git pull --ff-only origin release/1.0`。
2. 记录 `git rev-parse HEAD`。Android +25打包源码固定为 `9d7bcff629be8c33bed6e12b0285314ad514f9d6`，后续文档保存提交的HEAD不必与它相等；用 `git merge-base --is-ancestor 9d7bcff629be8c33bed6e12b0285314ad514f9d6 HEAD` 确认祖先关系，并以 `git diff --name-only 9d7bcff629be8c33bed6e12b0285314ad514f9d6..HEAD` 确认仅文档差异。若出现运行代码、资源、依赖或平台配置变化，应按新源码重新验收，不能沿用原包证明。不要从后续继续开发的main打此候选。
3. `pubspec.yaml` 和 App 版本常量应为 `1.0.0+25`。若 Apple 已占用此 build，先按发布台账递增，不复用。
4. `ugk_coach 0.3.3`、`ugk_trainer 0.1.6` 均固定 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`。运行 `flutter pub get --enforce-lockfile` 并确认 lock 无变化；不带 Windows path override。

## 构建

共享 `production` scheme 对应 Debug/Release/Profile-production 配置，原 Runner 配置保留。Windows 的配置合同检查不能替代 Mac 实际编译。

在 `ios/Runner.xcworkspace` 核对 Apple Team、`com.ugk.smartfit`、provisioning 和发布证书。Apple 签名材料由 Mac 私下保管，不复制 Android 上传密钥，不进 Git。

```sh
flutter analyze
flutter test
flutter build ipa --release --flavor production --build-name 1.0.0 --build-number 25 --dart-define=SMARTFIT_MEDIA_PRIMARY_URL=https://smartfit-media.pages.dev/v0.3.0-app/
```

媒体 HTTPS 地址是公开内容分发源，不是 AI 服务地址；必须保留 `v0.3.0-app/` 末尾斜线，其兄弟 `v0.3.0/` 保存视频。**不传 `SMARTFIT_AI_TOKEN`、AI endpoint 或包含旧开发 Key 的 dart-define 文件，不启用 `UGK_INTERNAL_MEDIA_PREVIEW` / `SMARTFIT_INCLUDE_PENDING_MEDIA`。**

## Mac 实际核验

- 签名、Bundle ID、版本、源 SHA、固定 SDK、无 API Key；生产可见完整93项，而不是空库或内测越过资格检查。
- 原对话安全确认、本地规则/模板、动作库、开始跟练、完成记录；已修资料与实际示范/语音一致。
- 非内置素材走公开 HTTPS、SHA/字节验证及失败回退；Wi-Fi策略、缓存、断网和内置动作符合原逻辑。
- WKWebView 本机媒体与公开政策页、语音/提示音、锁屏/后台、横竖屏及权限行为；Android 通过不能替代 iOS 通过。
- 原 AI 入口可见但空 Key 不提供在线回复；不恢复已废弃的新首页/隐藏入口方案。
- A2 图标、App 内隐私/条款入口、iOS Privacy Manifest、App Store 数据声明与 CDN 实际网络行为一致；不能套用 +24 “无远程素材源”声明。
- 从实际 iOS 包截取 iPhone 素材；保留平台默认备份说明，不冒称已关闭备份。

测试、导出、上传 TestFlight、提交 App Store 是独立平台步骤。本轮授权的 Google Play/YouTube/Cloudflare操作不自动变为 Apple 后台授权。
