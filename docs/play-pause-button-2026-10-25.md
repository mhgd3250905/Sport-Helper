# 训练播放/暂停按钮动画（待真机确认）

基于首帧修复分支 `4a4bdbe` 继续，App 内测 `0.1.0+26`。SDK 与 App main 仍等待开哥真机确认；本任务不修改 `release/1.0`。

SDK 新增独立 `UgkPlayPauseButton`，TrainerPlayer 自动接入。两块三角逐点形变成暂停双条，保留主题底色/图标色及 76px 按钮、96px 进度环、原线宽与进度来源。包含末段形变动作、中心漫色、按压弹回、仅用户激活的波纹与触感、暂停呼吸和环头柔光。连续反向从当前值继续；真实 isPlaying 负责校准乐观点击。系统减少动态时仅保留 150ms 图标交叉淡入与颜色过渡。保留键盘和现有语言的语义标签，动画在局部重绘边界内。

固定 `ugk_trainer-v0.2.7` → `17ecbd7ada2ff37e940a03bb38949d547ef29975`；coach 0.5.0、coach_ui 0.1.2 不变，所有旧 tag 未移动。组件接口见 SDK packages/ugk_trainer/README.md。SmartFit 沿用同一会话、素材与主题注入，无 App 播放状态副本。

只做相关验证：SDK 组件 8 项及 Player/HUD 集成 13 项、App 相关 7 项；改动文件静态检查通过，正式远端 Pub 和严格锁文件校验通过，不跑全量。同步更新上一轮新增首帧素材的构建清单回执，媒体字节不变。release 构建、保留数据装机、浅深主题录屏和实际帧率结果在项目目录 deliveries/play-pause-button-20261025，未测得的性能指标不视为已通过。
