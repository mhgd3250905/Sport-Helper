# SDK700 同脚本逐帧证据

基准 **13c0bb4cc24982be50bbb2471fc83ace6f64e40b**；正式应用/捕获源码 **de0bd432ec85f055206792b921964630739fd137**；三包实际解析 SDK **700d0100f1cb42ef122e774a6ee0076d1916b5e5**。这组输出独立保存，没有覆盖旧证据。

**117/130 帧像素完全相同，13 帧共 299 个不同像素，单帧最多 81，最大通道差 59/255。严格零像素门禁尚未通过，Hark 未验收。**

两提交使用同 driver `a4b94ee1f946f026b70e1104eaad286e938756b4caff0e9bc3a4dc62bb2f7feb`、同输入 `d11d6afe55fba10de8a8e81105b8f3f5ded338a86577c9e1436816ee6fe39e18`、逻辑412×915、dpr2.625、同字体/素材。浅深各65帧；base/new两边 capture tests 均2/2通过，HEAD/编译输入前后未变。

原58帧在新base与历史base逐字节一致；SDK700这58帧亦全部0像素差（含等待/状态/出卡/讨论标签/训练进退）。新增标签边界帧全部0。非零差异仅在新增剪影首揭示/交叉淡入中间点；见 [13帧逐项说明](13-frame-differences.md)、[全部130帧表](pixel-diff.md)、[原始像素与语义统计](pixel-diff.json)。

实际bubble子树 RepaintBoundary 两边始终 **4**，不计App/router捕获层；legacy实际裁切painter计数逐帧相同。严格语义矩形比较26帧不同，仅为最大1.4210854715202004e-14逻辑像素的浮点尾数；动作label/image标志、讨论清除label/button/tap全部相同。原始矩形值仍保存，没有用取整/容差将严格比较伪装为0。

源码对照推断为公共圆裁切与逐图缩放的层级次序变化；它与差异位置吻合，但没有擅自修改renderer或动效做补偿。来源、SHA、真实legacy素材index/bounds、语义、运行边界计数及推断证据均见 [source-bindings.json](source-bindings.json)。

- `base/`、`new/`：每边130张完整原PNG及浅深两份manifest。
- `base-receipts/`、`new-receipts/`：严格lock日志、capture日志、完整编译输入hash、实际命令和exit0。
- `review/`：13张诊断放大图。左base、中SDK、右精确RGBA差异红色mask，原ROI [100,220,205,320] nearest-neighbor放大6倍；原始PNG未改。
- [review-notes.md](review-notes.md)：差异与语义说明。
- `failed-base-handle-lifecycle/`：第一轮工具退出时SemanticsHandle生命周期失败的完整留档，不作为正式通过证据；修复仅test-body try/finally dispose。

本证据来自Flutter widget capture，不是手机截图，也不是profile性能数据。未出包、未操作设备、未合main/发布分支。Hark裁决仍待完成。
