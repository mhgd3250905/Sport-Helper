# 同脚本逐帧复现

使用 Flutter **3.44.7**、逻辑 **412×915**、DPR **2.625**；输出 PNG 为 1082×2402。捕获调用目标提交的实际生成卡、出卡过渡、讨论标签、PlanCard 和训练路由，不绘制替代 UI，不需要 API key，不请求模型，也不操作手机。

SDK `700d0100f1cb42ef122e774a6ee0076d1916b5e5` 正式 slots 迁移使用新增的 `capture_slots_test.dart`，SHA256 为 **`a4b94ee1f946f026b70e1104eaad286e938756b4caff0e9bc3a4dc62bb2f7feb`**。新增 `inputs-slots.json` SHA256 为 **`d11d6afe55fba10de8a8e81105b8f3f5ded338a86577c9e1436816ee6fe39e18`**。两提交运行这些完全相同的字节；只切换公开构造适配。当前 `capture_adapter.dart` 是实际 SDK bubble/delivery/focus 接入，剪影与图标直接调用生产的 `smartfitTaskCutouts`、`smartfitPlanFocusIcon`、`smartfitPlanFocusClearIcon`，训练退出使用实际公开路由控制。

基准仍固定为 **`13c0bb4cc24982be50bbb2471fc83ace6f64e40b`**，使用 `capture_adapter_base.dart.template`。新源码从捕获时实际 HEAD 写入收据，并在捕获前后检查 HEAD、lib/android/assets/test/pubspec/lock 等编译输入未变；正式新帧须在包含应用迁移与工具的提交上运行。对已有资料只读，每次输出和证据目录必须是新的路径。

130 对帧为浅色、深色各 65 帧。原 58 帧名称、输入和采样点保留；新基准对历史 `docs/ui-kit-frames/base` 的这 58 张 PNG 逐张执行 SHA256 字节断言。新增每主题 36 帧：

| 类别 | 相对起点采样（毫秒） | 边界依据 |
| --- | --- | --- |
| 当前 PoseHub 首图揭示 | 179 / 180 / 181 / 305 / 429 / 430 / 431 | 原实现先收缩 180，再揭示 250 |
| 当前 PoseHub 交叉淡入 | 899 / 900 / 901 / 1025 / 1149 / 1150 / 1151 | 原实现停留 900，交叉淡入 250，一个周期 1150 |
| 历史 legacy 首图揭示 | 同首图七点 | 实际 SfAlphaAsset 和原始 alpha bounds |
| 历史 legacy 交叉淡入 | 同轮换七点 | 同一原始两张图片、原始裁切 |
| 讨论标签进入 | 0 / 1 / 179 / 181 | 原 180ms，另保留原始 90 / 180ms 帧 |
| 讨论标签退出 | 0 / 1 / 119 / 121 | 原 120ms，另保留原始 60 / 120ms 帧 |

每帧额外记录实际 bubble 子树中的 `RepaintBoundary` 数量，断言始终为 **4**，不计 App/router 的捕获边界。记录真实剪影图像的动作语义、image 标志和语义矩形，以及清除讨论标签按钮的 label/button/tap。首图 430ms 与交叉淡入 1025ms 断言原动作语义仍可访问；legacy 同时断言实际使用了裁切 CustomPaint。相同采样脚本对两边都启用语义收集，原 58 帧的历史字节断言验证该收集没有改变渲染。

`legacy-alpha/manifest.json` 记录可追溯的 **SmartFit +31 / `5efb3e0`** 原始 APK、完整 APK SHA256、zip 条目、原图片 SHA256、宽高和边界。只保留 h-squat、w-bird-dog 的两张原 alphaThumbnail（共 **27,880 字节**）及原始完整 index/alpha-bounds；未生成、重绘、改色或修改 bounds。测试 AssetBundle 在原资产键提供这些原字节，其余请求仍委托给生产 PoseHubAssetBundle。该 fixture 验证真实历史渲染分支，不代表当前动作目录重新分发旧素材。

先准备两个工作树及各自 lockfile 对应的依赖缓存。launcher 严格执行离线 `pub get --enforce-lockfile`，源文件或锁文件变化立即停止。参数中工具、素材根和历史基准从本评审分支取；工作树、Flutter、缓存和新输出路径可迁移：

```text
python tools/ui_kit_frames/capture_frames.py --variant base --checkout ../sf-slots-base-13c0bb4 --driver tools/ui_kit_frames/capture_slots_test.dart --tools-subdir tools/ui_kit_slots_frames --adapter tools/ui_kit_frames/capture_adapter_base.dart.template --inputs tools/ui_kit_frames/inputs-slots.json --legacy-fixture-root tools/ui_kit_frames/legacy-alpha --historical-base docs/ui-kit-frames/base --flutter <flutter-3.44.7/bin/flutter> --pub-cache <pub-cache> --output ../capture-slots/base --evidence ../capture-slots/base-receipts
python tools/ui_kit_frames/capture_frames.py --variant new --checkout ../sf-slots-new --driver tools/ui_kit_frames/capture_slots_test.dart --inputs tools/ui_kit_frames/inputs-slots.json --legacy-fixture-root tools/ui_kit_frames/legacy-alpha --historical-base docs/ui-kit-frames/base --flutter <flutter-3.44.7/bin/flutter> --pub-cache <pub-cache> --output ../capture-slots/new --evidence ../capture-slots/new-receipts
python tools/ui_kit_frames/compare_frames.py --base ../capture-slots/base --new ../capture-slots/new --output ../capture-slots/pixel-diff
```

launcher 只创建缺失的捕获工具和同字节素材，遇到同路径不同字节即停止。当前计划六个动作所需的 **12 张 cover/thumbnail 原图、135,798 字节** 仍由 `media-inputs.json` 校验并按需恢复；tools 中的复现副本不在 pubspec 声明范围，这不代表完整发布资产已经准备。`planSource.path` 和 legacy APK 绝对路径是来源记录，复现时不会读取它们；计划 JSON、必要素材和 metadata 已保留于工具中。原计划剂量、动作、文字与原 58 帧完全相同；应用实际时长文案若因本次节奏语义变化产生差异，比较仍如实统计。

像素比较需要 Pillow 和 NumPy，本轮使用 **Pillow 12.3.0、NumPy 2.4.2**。比较逐张验证 PNG SHA，统计每帧完整 RGBA 不同像素数、通道差和边界，不裁剪、不遮罩、不忽略动态区域。抗锯齿候选仅为描述统计，语义矩形和裁切计数也原样比较。全零仅说明这套输入的像素与记录语义一致，不能代替 Hark 逐帧验收、真机性能或完整发布门禁。

原 58 帧工具仍保留：`capture_test.dart` SHA256 `81f80b15fbfc34526aca03c18e835c0234553f064c9a46ab4543c5f65ac6f154`，`inputs.json` SHA256 `a2c6df4c3e5dd8f3acab967ab835b15b0d9c6db3f98c318c0d8fcb705d490711`。`b27ffe0` 等早期阶段保留宿主 bubble/delivery/focus，仅切路由；那些已保存的输出和收据属于历史阶段。`capture_adapter_sdk_candidate.dart.template` 是旧的预备 ImageProvider 适配，不能用来代表当前正式 Widget slots 接入。
