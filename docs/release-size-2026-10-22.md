# release 分包、语音统计与真机验收状态（2026-10-22）

原素材改造已按开哥批准的顺序发布：SDK main `df90e7cb3f53c919927542056dcdfd6c0a600a66`，随后 App main `8f1f3c56f12f3157ea6e1b63e9b89ea867290ba6`，均核对 GitHub main ref 一致。

后续按开哥选择增加独立内测 release。SDK trainer 0.1.6 已先发布 main `f684e02f38e652633c23fa8946a53d02b6aa3ea2`，coach 保持 0.3.3；App 两项依赖均固定该完整 SHA，无 path override。下列 APK 的运行源码为 `4fdf8ac868fbd30f40de79b9a5d0997bf7799aae`（版本 `0.1.0+12`），后续文档提交不改变 APK 运行代码。

## arm64 交付物

| 包 | APK 字节 | 十进制 MB | SHA-256 |
| --- | ---: | ---: | --- |
| production arm64 release | 55,712,099 | 55.71 | `95f1ff9a9012f5550840473b194019ab7af21b5bee270e03da30202e9a5446da` |
| internal arm64 release | 55,711,995 | 55.71 | `9c092f64b601bf60bf8f61ef7802c742248d1220d475ba8197de7b8a0638ac06` |
| 上轮 +11 debug 通用包 | 199,556,721 | 199.56 | `147b1dece85a81c1e303d98904db4d6c42c12ded820098b12b0d7e6e8e744b22` |

MB = 1,000,000 B；两个 release 包约为 53.13 MiB，Flutter 控制台显示约 53.1 MB。本文沿用前次 199.56 MB 的十进制口径。生产 arm64 比上轮 debug 通用包减少 **143,844,622 B（72.08%）**；比较同时包含 release 编译、ABI 拆分、R8/字体裁剪与内测构建配置变化，不能解释为只做了一种优化。

本机保存：

- `.buildlog/install/SmartFit-0.1.0+12-production-arm64-v8a-release.apk`
- `.buildlog/install/SmartFit-0.1.0+12-internal-arm64-v8a-release.apk`

两包均为 `release` / AOT 编译、**非 debuggable**，仅含 arm64-v8a；minSdk 24、targetSdk 36、versionName `0.1.0`、versionCode **2012**。Flutter 分 ABI 时在基础版本 12 上加入 ABI 标识，因此原始 pubspec 的 +12 与 APK 中 2012 并不冲突。签名沿用已有 Android 开发证书，apksigner v2 验证通过；这是本轮测试用 release 编译包，没有配置商店发布签名或上传商店。

## 按相同口径拆包

以下为 production arm64 包中 ZIP 条目的实际占用字节，结构/签名/对齐单列，不拿解压后大小与 APK 文件大小相加。internal 与 production 仅相差 104 B，主要分组数值相同。

| 内容 | APK 中字节 | MB | 比例 |
| --- | ---: | ---: | ---: |
| 695 条训练语音 | 15,662,531 | 15.66 | 28.11% |
| 动作视频、封面、缩略图和清单 | 14,769,392 | 14.77 | 26.51% |
| 一套 arm64 Flutter release 引擎 | 11,581,856 | 11.58 | 20.79% |
| App / Flutter 框架及 Dart 依赖的 AOT 代码 | 8,455,056 | 8.46 | 15.18% |
| 中文字体、图标字体 | 2,815,172 | 2.82 | 5.05% |
| Android DEX 代码 | 1,003,093 | 1.00 | 1.80% |
| 其他文件与原生插件 | 1,044,619 | 1.04 | 1.88% |
| ZIP 结构、签名和对齐 | 380,380 | 0.38 | 0.68% |
| **合计** | **55,712,099** | **55.71** | **100%** |

独立检查确认 debug Kernel、VM snapshots、Vulkan validation 库均为 **0 文件 / 0 B**；仅一套 ABI。MaterialIcons 字体从 1,645,184 B 裁剪到 2,816 B（未压缩大小）。

两个最终 APK 的 413 项训练素材与源文件逐项 SHA 一致，原始合计仍为 14,883,430 B；32 段视频仍为 13,035,872 B。旧 pack 视频/封面、cutout 均未打包。695 条语音也逐项核对 SHA 与源一致，合计 15,662,531 B；没有转码。新文档、CSV 和 JSON 报告不在 Flutter assets 中。

机器可读明细、最大文件及各组解压/压缩大小见 [APK JSON](reports/apk-release-size-2026-10-22.json)，可用 `tools/media/report_release_apks.py` 复跑。

## 三种架构均已构建

两次构建均实际使用 `flutter build apk --release --split-per-abi --no-pub --flavor <flavor>`，没有只对通用包删除 ZIP 条目。

| ABI | production APK 字节 | internal APK 字节 |
| --- | ---: | ---: |
| armeabi-v7a | 53,304,951 | 53,304,847 |
| arm64-v8a | 55,712,099 | 55,711,995 |
| x86_64 | 57,169,919 | 57,169,815 |

原始构建输出在 `build/app/outputs/flutter-apk/`，arm64 交付物已另名保留在 `.buildlog/install/`。生产构建约 190.0 s，内测构建约 101.4 s，不据此作设备性能结论。

## 生产门禁与独立内测

默认 flavor 为 `production`，保留 `com.ugk.smartfit`，仅允许已审核动作，网络配置禁止普通 HTTP、保留播放器 loopback 白名单。当前素材全待审核，因此生产目录为空是门禁的预期结果。

内测 flavor 为 `internal`，独立 ID `com.ugk.smartfit.internal`、名称“智能健身助手·内测”，可与原 App 共存并隔离数据。开哥明确批准内测 release 预览后，才在此构建中开启 `UGK_INTERNAL_MEDIA_PREVIEW=true` 与 `SMARTFIT_INCLUDE_PENDING_MEDIA=true`，并允许局域网 HTTP。App 和共用 SDK 复用同一编译策略：普通 release/profile 不放行；internal flavor 与显式预览开关须同时成立，repository 还额外要求 `allowPending=true`。Flutter 工具注入真实 `FLUTTER_APP_FLAVOR`，拒绝用同名环境或自定义 define 冒充 flavor。

已经直接解析两份 APK 中的网络 XML：production base cleartext=false、仅 127.0.0.1 / localhost 例外；internal base cleartext=true。两者都未打开 debuggable。内测包配置本机 `http://192.168.71.116:8778/v0.3.0-app/` 与备用 8779，服务根必须指向 `E:/AII-3D/3D-Pose-Hub/release`，未上传云存储。需要测试时按原素材记录中的只读服务脚本启动，不能假定跨会话服务器一直运行。

构建入口 `tools/coach/build_release.ps1` 从原本机文件读取 Worker app key，仅以 dart-define 注入，不打印、不入仓。production 参数遇到 HTTP 地址会直接拒绝。普通与内测参数、HTTP 拒绝路径已用不含真实 key 的替身构建器测试；实际两次 release 编译也均成功。

## 语音：只统计，未修改

全部 695 条已经是 **AAC-LC / M4A / 44.1 kHz / 单声道**，有效加权音频码率约 65.293 kbps（流码率中位 64.865 kbps），所以“改成单声道”本身没有额外收益。总时长 **1,811.650 秒（30.194 分钟）**；单条 min / median / P90 / max 为 **0.380 / 2.330 / 4.870 / 7.090 秒**。

| 目标 | 含开销比较预算 | 可节省 |
| --- | ---: | ---: |
| AAC 单声道 32 kbps | 8.12–9.06 MB | 6.60–7.54 MB（42.1–48.1%） |
| Opus 单声道 24 kbps | 6.31–7.24 MB | 8.43–9.35 MB（53.8–59.7%） |

这些是总时长 × 目标码率再加短文件封装/首尾帧敏感性预算，**没有转码实测，不是音质结论或大小保证范围**。AAC 24/48 与 Opus 16/32 的其他比较点、容器开销、所有单条时长/码率和前后 SHA 在 [语音统计说明](voice-size-2026-10-22.md)、[695 条 CSV](reports/voice-clips-2026-10-22.csv) 与 [JSON](reports/voice-size-2026-10-22.json)。资产 inventory 前后完全一致。

## 验证与未完成项

- App 新运行源码：`flutter pub get --enforce-lockfile` 通过，静态分析 0 issue，全量 **265 项测试通过**。
- trainer 0.1.6：**145 项通过**，静态分析 0 issue；独立 Dart AOT 实际编译执行的 18 种 mode/flavor/opt-in 矩阵 **18/18 通过**。coach 运行代码未变。
- 新配置及真实 APK 已独立只读复审；资产和语音内容逐项验证。两份 arm64 APK 的 v2 签名均通过。
- **真机连续训练 >20 分钟未执行**：ADB 未列出设备，开哥确认目前没有真机。没有用编译、AOT 矩阵、组件测试或模拟器替代此结论。已准备 [真机验收清单](physical-release-acceptance.md)，后续需用本次 internal arm64 release 运行 ≥21 分钟，验证视频、预取、计时、真机听音、记录及稳定性。

本机详细日志在 `.buildlog/release-size/`。当前交付范围已完成 release 构建/分包与统计，设备验收仍待真实设备。
