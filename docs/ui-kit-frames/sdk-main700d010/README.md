# SDK main700 同脚本逐帧公开证据

当前供测试 APK 的 **software/source B 为 `de0bd432ec85f055206792b921964630739fd137`**；本目录为随后独立的文档发布，不能将 docs 提交号冒充 APK 源码号。三包实际解析 SDK `700d0100f1cb42ef122e774a6ee0076d1916b5e5`；基准 `13c0bb4cc24982be50bbb2471fc83ace6f64e40b`。

**117/130 对帧像素完全相同；13 帧共 299 个不同像素，单帧最多 81，最大通道差 59/255。严格零像素门禁未通过，也未达到全部抗锯齿候选规则；Hark 验收仍待裁决。** 本次不擅自修改 renderer、尺寸、颜色、时长或曲线来压平差异。

同一 frozen driver/input、逻辑412×915、DPR2.625、同字体/素材，浅深各65帧，两边 capture tests 均2/2通过。基准新增130帧中的原58张，与历史基准逐字节一致；source B 这58张与基准也全部0像素差。新增标签进入/退出边界全0；等待/状态、出卡过渡及真实训练路由原采样全0。

实际 bubble 子树 RepaintBoundary 始终 **4**（排除 App/router 捕获层）。legacy 真正的 SfAlphaAsset 裁切 painter 数量逐帧相同，动作 label/image 标志、清除讨论按钮 label/button/tap 全同。严格语义矩形有26帧不同，仅为局部矩形浮点尾数，最大绝对差 **1.4210854715202004e-14 逻辑像素**；原始值保留，未用四舍五入或容差隐藏。

源码对照推断：旧 `ClipOval(Stack(Transform.scale(image)))`；SDK builder 路径移除公共 ClipOval，而宿主 ClipOval 位于每图 Transform 内。缩放与裁切次序变化，与中间态剪影边缘差异吻合。**这只是源码支持的因果推断，未做补偿实验证明，也未宣称已修复。**

- [130 对原图审阅索引](frame-index.md)：每帧 base/new 链接、像素数与诊断图入口。
- [13 帧逐项说明](13-frame-differences.md)：theme、时间、阶段、像素数、bbox、maxDelta、共同推断。
- [全部逐帧像素表](pixel-diff.md) / [完整 RGBA 与严格语义原值](pixel-diff.json)。
- [原始 source-bindings](source-bindings.json) / [来源与发布 SHA 映射](publication-map.json) / [公开目录完整性索引](publication-integrity.json)。
- [base 收据](base-receipts/run.json) / [new 收据](new-receipts/run.json)：实际命令、源码/编译输入 hash、exit0；相邻日志给出2/2捕获结果。
- [差异说明](review-notes.md) / [原 delivery README](original-delivery/README.md)。

`base/` 与 `new/` 各130张完整原PNG，`review/` 保留13张分析放大板（base / SDK / 精确RGBA差异红mask），原ROI [100,220,205,320] nearest-neighbor放大6倍。完整原PNG从未改写。legacy两张原alphaThumbnail、完整原index/bounds与来源APK SHA记录在 source-bindings，未造图或改边界。

## 原始字节与 Git 文本

原 delivery 完整保留，未向其中写入。本目录复制其293个必要文件；不复制运行缓存和失败工具轮。PNG、capture-manifest、pixel-diff、source-bindings、run/config 等所有现有 JSON 均保留原字节及字段。原 `source-bindings.json` SHA256 为 `21b8455adc71276571606ed0ed28d910491e07de94ddf79884cfb1a3cd28f0a8`，公开副本完全相同。

publication-map 逐文件记录 original/published 路径、字节数、SHA256及换行变换；若文本被统一LF，会明确记录，不能当作raw原件。本批来源文本本已LF，因此293个复制文件全部为字节相同。原README单独放到 original-delivery/README.md，根README及frame-index为本次新增公开说明。局部 .gitattributes 固定文本LF，JSON不走文本规范化、PNG为binary，保证Git checkout后的复核含义一致。

原 source-bindings / artifact-integrity 中的相对路径和SHA属于**原 delivery 命名空间**；例如原README需经publication-map定位到 original-delivery/README.md。publication-integrity负责本公开目录的最终字节。两份原始JSON均未为迁就公开目录而改字段或重算旧收据。

本目录是 widget capture 文档，不建立真机性能、profile overlay或手机验收结论。当前APK的构建/签名等证据由软件B的独立门禁提供，不能从逐帧图推断真机已通过。
