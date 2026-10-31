# +51 SDK 接口缺口（迁移前静态核对）

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
