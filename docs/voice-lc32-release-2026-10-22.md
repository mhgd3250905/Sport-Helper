# AAC-LC 全量转换与 arm64 release（2026-10-22）

开哥试听后已选 **LC，全量转换**。695 条现已转换为 AAC-LC / 32,000 bit/s / 单声道 / 22.05kHz，
原件和字体保持不变。App 已接入新资源路径和实测解码时长，测试与 APK 核验通过。
分支 `feat/voice-aac-comparison`，运行源码提交 `77b06a907ec13dda4ba52df5d35a6daff182d8f7`。
**尚未合并或推送；Android/iOS 实际设备播放与连续训练验收尚未执行。**

## 实际体积

| 内容 | 原来 B | 当前 B | 减少 |
|---|---:|---:|---:|
| 695 条 M4A，含封装 | 15,662,531 | 9,256,276 | 6,406,255 B / 40.90% |
| production arm64 release APK | 55,712,099 | 49,384,431 | 6,327,668 B / 11.36% |
| internal arm64 release APK | 55,711,995 | 49,384,327 | 6,327,668 B / 11.36% |

MB = 1,000,000 B。新的 production arm64 包为 **49.38 MB**（约 47.10 MiB），
前后均为实际 release/AOT、`--split-per-abi` 的 arm64-v8a 包，不能与 debug 通用包混比。
新运行清单 337,431 B，随 APK 压缩打包；详细转换审计不在 assets 内。
新 M4A 加运行清单原始合计 9,593,707 B。

两包均为 `0.1.0+13`，aapt 的 arm64 versionCode 为 **2013**，minSdk 24、targetSdk 36，
没有 debuggable 属性。签名沿用项目已有开发证书，apksigner v2 校验通过。
没有上传商店、云素材或远程发布。

| 交付物（项目 `.buildlog/install/`） | SHA-256 |
|---|---|
| `SmartFit-0.1.0+13-lc32-production-arm64-v8a-release.apk` | `05c312e6073c8fe78f273fb9c849f17f224c46b815518c995140953ec3e0d30b` |
| `SmartFit-0.1.0+13-lc32-internal-arm64-v8a-release.apk` | `31ac8157c6e7bd1ea2d4654ef4dbedabd0d41c11417a5fad0cfe21b2a397b741` |

后续有设备时使用独立内测包 `com.ugk.smartfit.internal` 验收，生产仍为 `com.ugk.smartfit`。
内测保留已批准的待审核素材预览和局域网 HTTP，生产门禁不变。
当前 LAN 地址仍为 `192.168.71.116`，构建配置主/备 8778/8779 指向 release 目录，
本轮没有为了语音转换启动素材下载或调用 AI。

## 包内占用（与上轮相同口径）

下表使用 production APK 的 ZIP 条目实际占用，结构、签名、对齐另列；总和精确等于 APK 文件字节。

| 内容 | APK 占用 B | MB | 比例 |
|---|---:|---:|---:|
| 动作视频、封面、缩略图和清单 | 14,769,392 | 14.77 | 29.91% |
| arm64 Flutter release 引擎 | 11,581,856 | 11.58 | 23.45% |
| 695 条 LC 语音 | 9,256,276 | 9.26 | 18.74% |
| App/Flutter/Dart AOT 代码 | 8,455,056 | 8.46 | 17.12% |
| 中文与图标字体 | 2,815,172 | 2.82 | 5.70% |
| 其他文件与原生插件 | 1,120,301 | 1.12 | 2.27% |
| Android DEX | 1,003,093 | 1.00 | 2.03% |
| ZIP 结构、签名和对齐 | 383,285 | 0.38 | 0.78% |
| **合计** | **49,384,431** | **49.38** | **100%** |

语音省 6,406,255 B；清单、资产注册和其他文件净增 75,682 B，ZIP 结构等净增 2,905 B，
所以最终 APK 净省 6,327,668 B。其他主要组大小未变；AOT 文件内容已更新，恰好仍在相同大小的分配页内。
没有通过删除 ABI ZIP 条目改造旧 APK，实际按架构重新构建。

## 素材与集成

新文件：`assets/voice_lc32/v1/<pack>/zh/<line>.m4a`，
运行清单：`assets/voice_lc32/v1/manifest.json`。
原 `assets/packs/*/voice/zh/*.m4a` 全部保留在仓库，但不再打包。
每条清单记录目标路径、字节、SHA-256、声明时长、实测解码时长及原件路径/哈希。
`assets/packs/index.json` 的 `voiceBundle` 固定该清单字节和 SHA-256：
`5ebcf4211e44ca17930c8426a33bb3df932db0929d5caebd123b0e2d81c756c4`。

播放仍走共用 `ugk_trainer` → `just_audio`，没有复制播放器或下载逻辑进 SmartFit。
App 的 `VoiceLibrary` 包装原语义源，只覆盖音频路径和时长；文本、动作名、报数拼接、队列及 5 个提示音沿用原实现。
`total()` 使用新解码时长，避免仍按旧 `pack.ms` 调度。
运行清单不完整、重复、格式不符或越界路径都会拒绝加载。

`build_packs.py` 根据索引固定的变体生成 pubspec，后续生成不会重新加入旧语音。
如果原语音被重新合成或目标被改动，会因源/目标哈希不同而拒绝打包，避免旧声音配新字幕。

两种编码试听及全量都使用同一 FDK AAC 配置。全库保持源完整解码 PCM，不做裁剪、归一、变速或变调。
因为源 AAC 帧尾填充，新文件声明总时长为 1,819.725 秒（原声明总时长 1,811.650 秒）；
新解码相对源 PCM 最多增加 23.220ms 填充，不拿该差异冒充内容变长。
10 条获选 LC 样件与对应全量文件的 AAC 音频 payload SHA-256 完全相等。

## 验证

- 695/695 编码 profile LC、单声道、22.05kHz、完整解码及哈希通过；幂等复跑 695/695 只校验复用。
- 原件 inventory 前后 SHA-256 均为 `770d3dd7037f5f38d7cac8d5dbf2a88d5dd93f806cc7013813bf0b892821b29d`。
- 新 APK 逐项检查 695 条目标哈希、0 条旧语音、5 个原提示音、清单原字节与索引 pin；AssetManifest 注册与目标清单一致。
- 413 份动作素材逐项哈希不变，原始合计 14,883,430 B，仍只有 32 个内置视频；没有加入旧 pack 视频/封面或 cutout。
- `flutter pub get --offline --enforce-lockfile` 通过，依赖锁无变化。宿主默认镜像与 lockfile 的 pub.dev 不同，校验时仅在当前进程指定 `PUB_HOSTED_URL=https://pub.dev` 和原缓存目录，没有更新依赖。
- `flutter analyze --no-pub`：0 issue；`flutter test --no-pub`：**269 项通过**，包括真实 App 资源注册、完整语音映射、新时长求和及现有训练流程。
- 转换安全测试 4 项、打包变体/过期源/损坏目标测试 3 项通过；原 pack 校验 `--on-demand-media --decode` 为 0 error。
- 两份 APK 均为 arm64 release/AOT、无 debug kernel/VM snapshots/VkLayer，签名通过。

机器可读证据：

- [695 条转换审计](reports/voice-lc32-2026-10-22.json)
- [production APK 前后占用](reports/apk-lc32-production-size-2026-10-22.json)
- [internal APK 前后占用](reports/apk-lc32-internal-size-2026-10-22.json)

## 字体与设备验收

字体按用户前提跳过进一步子集。它已是 GB2312 加应用字符的子集，静态再裁会影响“咖啡、熬夜、焦虑”等动态聊天用字。
字体 SHA-256 保持 `93c0808b4374c84021581cd80ad5d5cae67303d91411d81211e77126d1e5b5ca`。

[Android 官方支持格式](https://developer.android.com/media/platform/supported-formats) 包含 AAC-LC、8–48kHz、mono/stereo 与 M4A；
[Apple 音频文档](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html) 说明 AAC 播放支持。
当前共享播放器在 Android 使用 Media3，在 iOS 使用 AVPlayer。以上是格式与实现依据，**不算实际设备播放验收**。

本机没有连接 Android 真机或运行中的模拟器，没有 iOS/Xcode 环境。
Android/iOS 的实际听音、首尾/间隔与后台切换仍需设备确认；真机连续训练 >20 分钟按开哥要求留待有设备。
验收方法见 [真机清单](physical-release-acceptance.md)。在实际平台播放尚未确认前，不宣称双平台播放验收通过。

本轮已完成转换、App 接入和可交付 release；合并 main、推送仍待开哥同意。
