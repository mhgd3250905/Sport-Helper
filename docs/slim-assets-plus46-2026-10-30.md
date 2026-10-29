# +46 资源瘦身候选（2026-10-30）

`codex/slim-assets` / `0.1.0+46`（internal arm64 2046）从已验收 +43 的 main `94e924fe287770f56d4e8ceeedd521e2871267da` 独立开展。SDK 三包、coach override 均锁 `b490eec43b408a8a35ce81a7830833bc6a3ff278`，整份锁文件不变；+44 guide-lite、+45 task-bubble-v2 独立保留，不依赖或合并。

移除 191 个内置 MP4，保留 941 份静图及 JSON；视频先查可信缓存，缺失再下载。图文页保留 main 版式，初始零解码器，点击后仅一个实例；真实首帧出帧后海报以 200ms 淡出。离线显示 `cloud_off_rounded` 20px，提示“连上网络后可以播放视频”2 秒，可再次点击重试。

训练预取并发 2，不阻塞开始；缺视频仍用 frame0，计时、语音继续。下载后同一播放器在首图后静音循环，公开位置查询观察到真实 native 回绕才揭图；位置不可读则保留首图，缓存命中正常出帧。暂停停止查询，后台和退出释放。优先可信 playbackPoster；SDK 219 张 standing 的正式索引逐项定义 frameIndex=0。

App PoseHub 跨版本统一 300,000,000B LRU，播放时按完整命名空间 pin；旧缓存按可信元数据、字节数及 SHA 收编。未知文件保留并占预算，无法腾空间时拒绝新增；图片、JSON、未发布下载及个人数据保留。SDK legacy fallback 缺发布 hook，不能把本 internal 路径的上限承诺泛化到所有 SDK 模式。

品牌设计源移至 `design/brand-source/`；About 复用同图 iOS B180 PNG（37,564B），保持 56dip。AGP 压缩 APK 中的 `.so`，保持 ELF 对齐；安装时解压，占用与下载体积分别核对。参见 [Android 原生库打包说明](https://developer.android.com/guide/practices/page-sizes#update-the-packaging-of-your-shared-libraries)。

695 条旧语音（15,662,531B）仍被 pack.files、工具与测试引用，原本未进入 APK，保留且不计作本轮 APK 节省；5 个 chime 继续使用。字体对比中数字更窄、粗字变化已交用户选择，当前保留 Noto，尚未验收。

全量 Flutter 705/705、0 跳过，analyze 0 问题；素材导入工具另有 22 项 Python 回归通过。覆盖缺网训练完成、零自动播放、单实例与释放、下载复用、预取顺序/并发、跨版本冷启动/LRU/pin/未知文件和元数据安全。缺媒体主地址的 internal/release 构建门禁已用 Gradle dry run 正反核验，实包另检查 ZIP 与 AssetManifest 零 MP4。

证据目录：`E:/AII-3D/3D-Sport-AI/deliveries/slim-assets-plus46/`。完整提交、实际 APK、签名/16KB/JNI、体积差值和字体原图分别见 `validation.json`、`release-apk.json`、`apk-size-comparison.json`、`font-comparison-source.json`；不以软件截图认定真机验收。main、release/1.0、SDK 及 +44/+45 保留原状；未推送、打 tag 或安装设备。
