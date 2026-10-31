# 历史记录：+51 SDK 接口缺口（迁移前静态核对）

<!-- sdk-main700d010-current:start -->
## +51 SDK main700d010 当前状态（2026-11-01）

**用户已反馈真机验收通过，并要求停止测试。** 已停止测量，换装同源 +51 release。13 帧非零的量化事实和原记录保留，0 像素目标仍未达，Hark 独立回执未记录；不合 main、不动 release/1.0、不打 tag，不自行改参数。

当前三包 pin `700d0100f1cb42ef122e774a6ee0076d1916b5e5`，运行接入已切 SDK 生成卡 / 交付过渡 / focus，版本 `0.1.0+51`。源码 B `de0bd432ec85f055206792b921964630739fd137`，实际模型运行 A `7548ee00955f3811fb9c18139503bb7f04abc11a`；A→B 仅 11 个帧工具文件，14 项模型输入 SHA 不变。SF 全量 **822/822、0 skip**，analyze --fatal-infos **0 issue**。

浅深 130 对帧：117 对零差，13 对共 299 像素，单帧最多 81 / 通道最大 59；原 58 对与新增 focus 边界全 0。SDK 4 个 RepaintBoundary 保留。5 次独立真实生成全部交付无反问、排程 ±10%；24 LLM / 24 HTTP，input 254462 / output 8058。首 case 手动 10 reps 估算 30 秒按授权不失败；missing goal 参数修复单列，duration recovery=0，未覆盖失败恢复分支。

包回执：release: artifact_verified; profile: artifact_verified。原生 profile：stopped_by_user_after_reported_acceptance；用户反馈通过按明确消息记录，不再补测等待态 overlay 或完整视频。原生手机内容不入仓。详见 [本轮总报告](sdk-ui-kit-plus51-main700d010-2026-10-31.md)。以下旧 pin / 暂缓迁移 / 旧验收条件均为历史记录，以本节和报告界定当前状态。
<!-- sdk-main700d010-current:end -->


基准：SF `13c0bb4cc24982be50bbb2471fc83ace6f64e40b`。
SDK 锁定：`caa6817c51b3cb09c46909288d83aa88bdc2dbd4`。

## 计划讨论标签：当前 pin 无法同时满足全部迁移与外观零变化

SF `lib/ui/chat/plan_focus_label.dart` 使用 `SfIcon(SfGlyph.bookmark)` 和
`SfIcon(SfGlyph.close)`。`SfGlyph` 是枚举，`SfIcon` 用 CustomPainter 画路径；
不是 IconData，也没有相应字体字形。

SDK `packages/ugk_coach_ui/lib/src/plan_focus_label.dart` 的构造参数只有
`IconData icon` 与 `IconData clearIcon`，内部直接构造 Icon，未调用已有
`CoachUiBuilders.icon`。因此不能把 SF 现有图标原样传入。使用 Material 默认图标、
另做图标字体或叠加绘制均不能视为已满足外观零变化。

需要 SDK 提供可选 Widget/builder（或接入现有主题 icon builder），保留现有默认行为。
新接口合入 SDK main 后应由用户提供/确认新的完整 pin；本分支不私改 SDK 或使用 path override。
按用户后续裁决，保留 SF 标签实现，不虚报迁移完成。

用户已选择先补 SDK 接口并另给新的 main pin。在此之前保留标签和剪影当前实现。
由于 bubble 没有 Widget renderer，而 SDK 交付过渡仅识别直接 SDK bubble child，
不能只把旧剪影 Widget 塞回新 bubble，也不能将旧 bubble 直接接在新过渡下。
因此当前运行链暂保留整套旧 bubble/过渡；已完成的 SDK 接入以准备 patch、
主题映射和像素 probe 保留，新 pin 后一起切换并重导对应帧。没有复制或改写 SDK。

## 生成卡片剪影：当前生产库与旧素材的能力不同

SDK CoachTaskBubble 接收 `ImageProvider? Function(String)`，内部直接绘制 Image，
并排除图片语义。SF SfAlphaAsset 对 `posehub-r1/` 资源也是原图绘制，生产 SDK-bound
动作库可用相同 DefaultAssetBundle/AssetImage 接入。

旧 `assets/app_test_pack/` 分支的 SfAlphaAsset 还会按 alpha bounds/sourceRect 裁剪，
并保留动作名语义。ImageProvider 入口无法直接复用这个 Widget。若这条旧路径也须完全
兼容，需要 SDK 提供可选 cutout renderer/builder，继续允许原来的 ImageProvider 入口。
本分支不通过修改素材、去掉裁剪或新造图片处理逻辑来掩盖差异。

## 可以独立继续

三包严格锁定、原 execution 周期投影与含准备时长对账、生成/交付的其余接入、
公有 TrainerSlideRoute 的宿主诊断桥、基准帧捕获及真实 5/10/20 分钟生成验证。
以上静态核对尚不代表逐帧或设备验收通过；Hark 确认前不出 release APK/profile overlay。
