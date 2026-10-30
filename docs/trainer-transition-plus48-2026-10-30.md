# +48 训练路由过渡与提前结束（2026-10-30）

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
