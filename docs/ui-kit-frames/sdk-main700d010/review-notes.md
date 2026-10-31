# SDK700 剪影帧差异说明

基准 `13c0bb4` 与正式源码 `de0bd432`，同一 driver/input、412×915、DPR 2.625。两边各 130 帧；两边 capture tests 均 2/2 通过。

**117/130 帧像素完全相同；13 帧共 299 个不同像素，单帧最多 81，最大通道差 59/255。严格零像素门禁未通过，也未满足全部抗锯齿候选规则。**

原 58 帧在新 baseline 与历史 baseline 逐字节相同，SDK700 对这 58 帧的不同像素数也全部为 0。新增标签进入/退出边界帧全部为 0；差异只出现在新增的剪影首揭示和交叉淡入中间点。未修改生产 renderer 或任何动效数值。

| 帧 | 不同像素 | 最大通道差 | 物理像素 bbox（右/下不含） |
| --- | ---: | ---: | --- |
| light/posehub-reveal-305ms.png | 2 | 8 | [188, 282, 189, 284] |
| light/posehub-crossfade-901ms.png | 5 | 1 | [119, 238, 189, 284] |
| light/posehub-crossfade-1025ms.png | 25 | 37 | [115, 236, 188, 287] |
| light/legacy-reveal-181ms.png | 1 | 1 | [115, 249, 116, 250] |
| light/legacy-reveal-305ms.png | 34 | 21 | [112, 243, 190, 293] |
| light/legacy-crossfade-901ms.png | 13 | 8 | [113, 243, 189, 291] |
| light/legacy-crossfade-1025ms.png | 81 | 59 | [111, 243, 194, 298] |
| light/legacy-crossfade-1149ms.png | 2 | 2 | [113, 249, 116, 279] |
| dark/posehub-reveal-305ms.png | 3 | 3 | [188, 281, 189, 284] |
| dark/posehub-crossfade-1025ms.png | 20 | 7 | [115, 236, 188, 287] |
| dark/legacy-reveal-305ms.png | 27 | 9 | [112, 243, 190, 293] |
| dark/legacy-crossfade-901ms.png | 11 | 3 | [113, 246, 189, 291] |
| dark/legacy-crossfade-1025ms.png | 75 | 21 | [111, 243, 194, 298] |

源码对照显示旧实现为 `ClipOval(Stack(Transform.scale(SfAlphaAsset)))`，新 SDK builder 路径移除公共 ClipOval，宿主返回的 ClipOval 位于每图 Transform 内。裁切相对于缩放的位置改变，与中间态剪影边缘的差异吻合；这是源码支持的原因推断，尚未通过改代码做补偿实验。按要求先报告，交 SDK/Hark 裁决。

实际 bubble 子树 RepaintBoundary 两边均为 **4**；legacy 裁切 CustomPaint 数量每帧一致，1025ms 为两张原图的两个 painter。动作 label/image 标志和标签清除按钮 button/tap 全部相同。严格语义矩形比较有 26 帧不同，仅为局部矩形的浮点运算尾数，最大绝对差 **1.4210854715202004e-14 逻辑像素**；原始值仍保留在 pixel-diff.json，未取整或以容差掩盖。

legacy 输入来自 manifest 可追溯的 +31 APK 两张原 alphaThumbnail，原始完整 index/bounds 与图片 SHA 均已断言，没有造图或改边界。

`review/` 为非验收替代图的诊断放大板：原图物理 ROI [100,220,205,320]，nearest-neighbor 放大 6 倍，左右为原 baseline/SDK 像素，红色面板仅显示精确 RGBA 不同像素。完整原图仍在 base/new，未改写。

完整每帧表见 pixel-diff.md；原始统计、语义矩形、SHA 与源码绑定见 pixel-diff.json / source-bindings.json。手机、profile 性能与 Hark 验收均不由这组测试建立。
