# +50 main 同步、升版及新 release（2026-10-31）

按用户安排先同步最新 main。远端 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b` 已通过 PR #6 合入原始生成卡提交 6ef2e3a，本地从 2309de3 快进到该提交；远端当时版本仍为 +49。随后仅纳入既有版本字段变更，得到本轮打包和测试源码 `4ef76006d47e06cdeacdcdc77a647436284ab98f`，版本 **0.1.0+50 / internal arm64 2050**。

生成卡三个文件及整个 lib 与 6ef2e3a 保持一致，四个 RepaintBoundary 原样保留，未调整动画、曲线、尺寸、颜色或入口。与上一份实际 profile/release 源 be2e29b 比较，全部公共运行输入和测试输入指纹一致。SDK 三包及 coach override 仍锁定 `66dd98a549c1ff5fedecb626a7c88583090a1440`；整份 pubspec.lock 与合入后的远端 main 不变。

## 在 main 重新执行的门禁

全量 **861/861 通过，0 失败、0 跳过**；`flutter analyze --no-pub --fatal-infos` **0 问题**。固定 Flutter 3.44.7，严格 offline/enforce-lockfile 通过，官方语义目录和匿名 HTTPS 素材验证实际执行。新 APK 从本轮 main 源码重新构建，没有将旧候选 APK 改名充作 main 构建。

| 项目 | 实际产物 |
| --- | --- |
| APK | `SmartFit-main-0.1.0+50-4ef7600-internal-arm64-v8a-release.apk` |
| 包身份 | com.ugk.smartfit.internal，0.1.0，2050，release arm64 |
| 大小 | 42,657,546B / 42.658MB，小于 45,000,000B |
| SHA-256 | `a968a41484ad05097758e1d15195e5f1d26bed0d89ed5ad628c5c4b77d8fe42e` |
| 证书 SHA-256 | `3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`，沿用现有开发证书 |
| 二进制门禁 | 签名、ZIP/ELF 16KB、Storage JNI、仅 arm64、非 debuggable 全部通过 |
| 资源门禁 | ZIP/AssetManifest 无 MP4；原 Noto、438 张索引图片、219 张 SDK 站姿及静态/音频保留 |
| 独立复验 | validation-release.json 通过，绑定源码、完整测试、实际 APK 身份与哈希 |

## 真机证据边界

本轮没有安装或测试手机。先前 Android 16 / 2602BRT18C 的 profile 等待截图仍作为同一实现的历史证据：UI/Raster 均未见红条，图中最大值 1.6ms/3.8ms。原 profile 源为 be2e29b，原图与观察保留在 `E:/AII-3D/3D-Sport-AI/deliveries/task-bubble-fidelity-overlay-20261031/`。不能把该旧截图写成新 main APK 再次真机验收，也不能扩展到深色、完整流程或持续帧率。

## 主线与交付状态

生成卡功能已经位于远端 main 的 PR #6 合并提交；本次 +50 升版和后续 README/docs 台账提交仅在本地主线完成，**尚未推送、未打 tag**。远端仍以本轮读取的 13c0bb4 为准，不将本地完成记成远端已同步。

本地后续文档提交不改变本包的 `4ef76006d47e06cdeacdcdc77a647436284ab98f` 构建来源。最终本地 main 完整 SHA、文档差异、远端状态及其他 refs 未变见仓库外 `final-main-receipt.json`，避免自引用。

新产物和原始门禁位于 `E:/AII-3D/3D-Sport-AI/deliveries/task-bubble-fidelity-plus50-main-20261031/`。原候选分支、工作树和旧交付物全部保留，release/1.0 与 SDK 源码未操作，不清理、不 reset。
