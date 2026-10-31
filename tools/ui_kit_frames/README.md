# 同脚本逐帧复现

冻结的 `capture_test.dart` SHA256 为 `81f80b15fbfc34526aca03c18e835c0234553f064c9a46ab4543c5f65ac6f154`，输入 `inputs.json` SHA256 为 `a2c6df4c3e5dd8f3acab967ab835b15b0d9c6db3f98c318c0d8fcb705d490711`。使用 Flutter **3.44.7**。捕获不需要 API key，不请求模型、不操作手机。

从包含本工具的评审分支运行 launcher，`--checkout` 指向要编译的独立工作树。基准固定为 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b`；本阶段新源码固定为 `b27ffe06b7ed0338d379b0474f458679eb282e2f`。两边使用同一 driver、同一 JSON、同一字体和参数，只切换公开构造适配。本阶段 active bridge 保留 SF 生成卡／过渡／讨论标签，通过同名宿主路由接到 SDK `TrainerSlideRoute`。`capture_adapter_sdk_candidate.dart.template` 仅为后续接入准备，不属于本阶段运行路径。

先准备两个工作树及各自 lockfile 对应的依赖缓存（首次可按项目惯例执行 `flutter pub get`）。launcher 随后严格执行离线 `pub get --enforce-lockfile`，锁文件或源文件变化立即停止。示例中的 Flutter 路径与缓存路径请换成本机实际目录；输出与证据目录必须是新的空路径。

```text
python tools/ui_kit_frames/capture_frames.py --variant base --checkout ../sf-base-13c0bb4 --flutter <flutter-3.44.7/bin/flutter> --pub-cache <pub-cache> --output ../capture-replay/base --evidence ../capture-receipts/base
python tools/ui_kit_frames/capture_frames.py --variant new --checkout ../sf-new-b27ffe0 --flutter <flutter-3.44.7/bin/flutter> --pub-cache <pub-cache> --output ../capture-replay/new --evidence ../capture-receipts/new
python tools/ui_kit_frames/compare_frames.py --base ../capture-replay/base --new ../capture-replay/new --output ../capture-replay/pixel-diff
```

launcher 在目标工作树中仅创建缺失的捕获工具和已校验的输入图片；遇到同路径不同字节会停止，不覆盖 App 源码。原目录清单、字体与数据由目标提交提供；本工具额外保留该固定计划六个动作需要的 **12 张 cover/thumbnail 原图，共 135,798 字节**，其路径、大小和 SHA256 在 `media-inputs.json` 中。图片仅为 golden 的离线输入，未重绘、改色或改写素材索引；tools 中的复现副本不在 pubspec 的声明范围。launcher 只恢复这套捕获输入需要的同字节素材，不代表完整发布资产已经准备好。

捕获目录中的两份 `capture-manifest.json` 记录逻辑 412×915、DPR 2.625、物理 1082×2402、帧/字体/driver/输入 SHA256、源码提交与编译输入。`inputs.json` 的 `planSource.path` 是原稿来源记录，运行时不会读取该机器路径；计划 JSON 已完整冻结在同一文件中。

像素比较需要 Python 的 Pillow 与 NumPy，本轮使用 **Pillow 12.3.0、NumPy 2.4.2**。比较保留每帧 RGBA 不同像素数、通道差和边界；全零也只说明这套输入的像素一致，不能代替全部迁移、可访问性、真机性能或 Hark 验收。
