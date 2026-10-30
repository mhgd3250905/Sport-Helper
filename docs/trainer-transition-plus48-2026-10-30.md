# +48 训练路由过渡与提前结束（2026-10-30）

## 当前 +48 卡片展开式训练候选（2026-10-30）

本轮按最新版完整交接接入 SDK `c97a79a5f03ba1f46f017b995f7f8d97fb3016a9` 的 startGate/chromeAnimation/onExitStarted/beforeExitPop；进入560ms、退出控件250ms及舞台380ms+120ms，路由本身0ms。真实训练UI从开始即挂载，门禁前无视频、计时或语音；图文来源页保留，完成记录在缩回结束后平滑插入。候选源码 `ccdf1b1729ee6365edb3669aaacae320c23bd49f` 已通过全量 **798/798（0跳过/失败）**、analyze **0问题**；release **42,628,010B**、profile **59,584,897B**，同签名、ZIP/ELF 16KB、JNI及无MP4检查通过。浅深软件视频已交付，真机UI/Raster最大值仍待测。最终源绑定、产物和待验边界见[新版+48记录](trainer-transition-plus48-morph-2026-10-30.md)。旧c0候选及652接口摸排仅保留作历史；main/release不动，不合并、不推送、不打tag，等待开哥真机确认。

候选分支 `codex/trainer-transition`，基于 +47 main `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`，版本 `0.1.0+48` / internal arm64 2048。按本次指令，完成验证及交付后等待开哥远程真机确认，未获确认前不合入或推送 main；不打 tag，不改 `release/1.0`、SDK 源码及原工作树。

## 实现与边界

`pubspec.yaml` 的三包及 coach override 统一固定 `652135f532bac1a06fbf133dc497692d6b44c78a`；`pubspec.lock` 只更新这三个 SDK 的 ref/resolved-ref，没有升级其他依赖。版本号与性能报告中的 SDK 身份同步更新。SDK 媒体目录与上一 pin 字节相同；原 Noto、静态图、语音与 chime 保留，无 MP4 的瘦身门禁继续执行。

`TrainingRoute` 进入 320ms、easeOutCubic、纵向 0.06→0；透明度使用 0–70% 的 Interval。退出 260ms、easeInCubic，按退出时间向下移动并淡出。禁用下层路由 secondary transition，不缩放或加暗；系统 `disableAnimations` 开启时进出均为 0ms。

SDK 的 training 模式会在 `initState` 启动时钟和语音。因此进入动画期间不挂载 `TrainerPlayer`：使用主题背景、公开 `TrainerStageFloor` 和现有 `ExerciseFrameZero` 静态图片，完成后才挂载真实训练页。SDK 没有公开的媒体矩形计算器，宿主使用与固定 pin 对齐的纯几何适配，并以真实媒体插槽的矩形测试约束，覆盖安全区与文字缩放；不复制 SDK 控件、播放器或私有 State。首动作经现有公开 SessionBuilder 适配获取，兼容 segment。

Flutter 的 Hero 首帧会在 `offstage` 布局期间临时将路由 animation 代理设为 completed；进入门禁同时要求实际 onstage，不能把这个预布局当作 320ms 已结束。入场中途返回则从当下位置与透明度开始反向，避免切换曲线造成瞬跳。问题标记截图在途返回后也重查会话结束和当前路由门禁，防止保存期间迟到表单抢占 SDK 要退出的路由。

路由开始 reverse 后，`mediaBuilder` 直接替换为同一首帧规则的图片，不挂载 `ExerciseVideo`。真实画面出帧前的海报及 200ms easeOutCubic 淡出沿用现有实现。训练媒体保留 SDK 暂停画面：弹窗覆盖或提前结束关闭子树 TickerMode，不再被误当作离页而销毁当前帧；实际路由退出和 App 后台仍释放媒体。

提前结束的确认、引擎停止、冻结画面、400ms 延迟小转圈、保存成功 pop receipt、失败完成页重试均由 SDK 652135f 执行。宿主仍等待写盘成功，不提前 pop。无 feeling 的提前结束 receipt 与 onFinished 首次保存相同，跳过重复写盘；自然完成或用户选择了 feeling 的 receipt 继续原有保存流程。冻结画面的重复 media build 不再误记成 replay，不重启训练日志。

聊天与图文入口在 push 返回后继续等待 `route.completed`。Flutter 的 popped future 会在 reverse 开始时返回；等待 overlay 真正移除后，才追加一次 `_chat.finished` 或恢复原图文预览，避免在过渡中改变下层内容。

## 验证与交付状态

定向过渡回归 61 项已通过，覆盖浅深与减动效、1×/1.5× 首图矩形、320ms 前零启动、进入取消、关闭/返回两种早退、400ms 慢保存、失败重试、迟到 native create/截图、一次保存/总结、图文恢复及帧记录。原训练流程、自然完成、快速动作切换、布局、日志和按需媒体的定向兼容回归 23 项也通过。这些是全量中的测试子集，不重复相加。生产代码定向 Dart analyze 0 问题。完整候选测试、全量 analyze、构建和签名/16KB/JNI 的最终结果以本轮源绑定回执为准，不沿用 +47 的数量或 APK 身份。

交付目录：`E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48/`。release 与 profile 分开记录实际包体、签名、编译源码和公开输入指纹；后续若仅 README/docs 收束，文档提交不冒称新的 APK 编译源码。

用户已确认本机没有真机，接受远程安装后反馈。因此本轮进出各五次的 UI/Raster 最大帧耗时 **待真机采集**，没有填入桌面、模拟器或合成帧数据。profile 包通过现有性能报告导出实际 FrameTiming，路由自动标记 `trainingRouteEntry` / `trainingRouteExit`，目标为两线程最大值均 ≤16ms，超出须按原始值回报。构建和软件回归不能替代这一验收。

main、release 分支和 SDK 的最后观察由外部保护范围回执记录。候选完成不自动视作真机通过或获准合并。

## 最终软件验证与产物

实现与测试源码 **`c0a0fc0bf26a4955cc1bfe4e7f943e1a487594db`**。全量 **773/773、0 跳过、0 失败**，`flutter analyze --no-pub` **0 问题**；使用实际 SDK 652135f 的官方目录、交付开关和真实匿名 HTTPS 媒体冒烟。严格锁解析通过，非 SDK 依赖没有变化。日志和 `tests-source-binding.json` 保留精确输入与 SHA。

| 模式 | arm64 APK | 字节数 | SHA-256 |
| --- | --- | ---: | --- |
| release / 2048 | `E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus48\SmartFit-trainer-transition-0.1.0+48-c0a0fc0-internal-arm64-v8a-release.apk` | 42,602,114 | `c97397beb7c7338350a3a5e79d941d73bba8935fa82512817914cc873767fe8d` |
| profile / 2048 | `E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus48\SmartFit-trainer-transition-0.1.0+48-c0a0fc0-internal-arm64-v8a-profile.apk` | 53,506,134 | `3503faeea6ed7d364234fec27371793db08955f999d348ed8e40b7e2c6e8938c` |

两包证书 SHA-256 相同：`3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`；ZIP/ELF 16KB、存储 JNI、无 MP4、保留 1,737 份静态/音频以及原 Noto 字节检查通过。release 比 +47 增加 4,008B，仍低于 45,000,000B。profile 使用独立的引擎与 VM 服务资源，不按 release 体积衡量；其实际 debuggable=true。

profile 首轮编译已成功，外部校验曾误套 release 的四库集合。现按模式精确核对：release 四库；profile 五库，额外 `libvmservice_snapshot.so` 逐字核对固定 Flutter 引擎的官方 Gradle artifact→merged，以及 AGP stripped→APK 来源链。原失败诊断保留在 `profile-gate-r1-c0a0fc0/`，恢复只重做检查和复制，没有重编或改写 APK，前后 SHA 相同。来源回执为 `profile-vmservice-origin.json`。首次全量的旧系统栏固定 350ms 等待失败也保留在 `full-checks-r1-dcd7fcc/`；按实际路由完成等待修正后，773 项全量重跑通过。

本次收束提交 **只更新 README.md/docs/**，APK 和测试的源码始终为上述实现提交，不将后续文档提交改称编译源码。候选分支完整最终 HEAD 由交付目录 `candidate-closeout.json` 记录；两包独立检查分别写入 `validation-release.json` 与 `validation-profile.json`。Git 内精确台账见 [reports/trainer-transition-plus48.json](reports/trainer-transition-plus48.json)。

| 真机采集项 | 要求 | 本轮实际结果 |
| --- | --- | --- |
| 进入过渡 | 5 次，UI/Raster 最大值各 ≤16ms | 待远程真机回传，未采样 |
| 退出过渡 | 5 次，UI/Raster 最大值各 ≤16ms | 待远程真机回传，未采样 |

远程步骤见交付目录 `REMOTE-DEVICE-CHECK.md`：先用 release 核对体验；再用 profile 通过现有“设置→性能报告”保留原始 JSON，分别核对 `trainingRouteEntry` / `trainingRouteExit` 的 `uiBuild.maxUs` 与 `raster.maxUs`（除以 1000 为 ms）。不以 P99 代替最大值，不丢弃第一遍进入或超时帧。

**候选保留未合并、未推送，等待开哥真机明确同意。** main 保持 `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`，release/1.0 与 SDK 源码不动，没有 tag 或设备操作。软件验证不是手机播放、物理释放时延或保留数据安装的验收。
