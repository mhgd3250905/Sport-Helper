# +48 卡片展开式训练过渡（2026-10-30）

+48设计已获开哥真机确认；运动卡顿由[+49性能候选](trainer-transition-plus49-performance-2026-10-30.md)继续。本页保留+48原时点源码、APK与软件证据，未因此合并main。

分支 `codex/trainer-transition`，从文档提交 `3c2030623a7e0dc22d4aeea642f68abe13912866` 继续，版本保持 `0.1.0+48` / internal arm64 2048。本记录取代之前所有 +48 过渡方案；原 c0 包、接口摸排和诊断回执按历史保留。

## 当前实现与授权

三个 SDK 包及 coach override 统一锁 `c97a79a5f03ba1f46f017b995f7f8d97fb3016a9`，锁文件只有这三个 Git 依赖的 ref/resolved-ref 变化。SDK 仓库和依赖缓存源码不改。main 保持 +47 `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`；release/1.0 不动。只提交候选，完成后等待开哥真机确认，再另行合并推送；不打 tag。

## c0 退出硬切和列表跳动的代码原因

手机动画设置经开哥确认均为 1×，本次不把系统缩时作为原因。旧 `PlayerPage` 在 route completed 之前只显示占位舞台，320ms 后整棵挂载 TrainerPlayer，控件在同一帧出现。旧 easeOut 淡入在100ms已达0.836、200ms达0.996，放大了“先空舞台、再硬出控件”的观感。

提前结束旧流程先冻结画面等待保存，成功才 pop，保存期间没有控件退场。正常260ms reverse 并没有被其他 pop 路径跳过，SDK子树的 TickerMode 也不会停 Navigator 的路由时钟；但 easeIn 淡出/0.06小位移前100ms只移动约4.16逻辑像素，明显变化集中在末段。reverse 开始时又把任意暂停视频帧换成第0帧海报，增加了一次内容切换。230ms保存等待和130ms跳动是用户录屏描述，不是本机重新量出的设备时间。详细软件对照见[原核查报告](trainer-transition-plus48-redesign-audit-2026-10-30.md)。

旧 finished 消息虽然在 route.completed 后插入，reverse 列表的新 row 却立即占据完整布局高度。旧 CoachAppear 仅改变绘制位置与透明度，不改变占高；原受控样本在offset=0/100均上移81逻辑像素，scroll offset未变。未找到固定130ms的第二次滚动定时器。本轮对完成行连同边距/时间标记从零占高展开，并在同一流程内滚动，消除首帧跳变。

## 进入、退出和绘制层级

TrainingRoute 为 opaque=false、进出0ms的路由，不叠加路由淡入。真实 TrainerPlayer 从0ms挂载，startGate阻止SDK计时、语音、recorder和hold，宿主同时禁止挂载ExerciseVideo。点开始即预缓存首帧。

进入海报按实测源图Rect到SDK真实媒体槽Rect插值，420ms easeInOutCubicEmphasized、圆角20→0；背景280ms easeOutCubic淡入。源图由宿主的公开媒体builder登记，不查SDK私有State、不复制布局公式、不用Hero。没有来源时，海报320ms从1.04归位并淡入，仍等560ms启动。

SDK地板强制不透明，前280ms让已挂载的真实SDK保留布局但暂不绘制；背景完全显示时开放绘制。海报也在280ms从外部飞行层交接到宿主mediaBuilder中的同Rect层：它位于SDK地板之上、真实控件之下，避免一张最上层海报遮住正在进场的胶囊和提示卡。整个普通舞台不做Opacity；每块控件由SDK独立变换。海报解码宽度固定为最终显示宽×DPR，Rect变化不重复解码。

| 层 | 起点 | 时长 | 完成 | 变化 |
| --- | ---: | ---: | ---: | --- |
| 顶部卡 | 280ms | 200ms | 480ms | y=-12→0，easeOutCubic |
| 下一个/不舒服 | 300ms | 200ms | 500ms | y=-8→0，easeOutCubic |
| 提示卡 | 320ms | 200ms | 520ms | y=+16→0，easeOutCubic |
| transport/问题标记 | 340ms | 200ms | 540ms | y=+16→0，easeOutCubic |
| 暂停 | 340ms | 220ms | 560ms | scale .85→1 easeOutBack；opacity easeOutCubic |

560ms最后一层到达终态后才完成startGate并挂视频，第一帧前仍显示同一海报；出帧淡出沿用现有200ms。

关闭确认、自然完成点完成、系统返回统一从onExitStarted启动250ms线性chrome反向；静态海报替换视频并卸载播放器，保存同时进行。beforeExitPop只等退场future，不重复保存。失败捕获于宿主实际保存回调，SDK完整完成页和重试保留，宿主问题按钮恢复显示。

自然完成点“完成”时，SDK的真实完成页按chrome淡出，宿主用公开theme将其Scaffold底色设为透明，让已缓存的最后动作海报从下层显露，避免250ms末尾才突然冒出一张图；完成页内容及保存仍归SDK。

SDK pop后独立Navigator OverlayEntry继续380ms缩回，背景在240ms内淡出；到位后真实源图恢复、海报再120ms交叉淡出。来源卡不可见则260ms整层1→.94淡出。visualCompleted包含整个回程尾段，完成记录只在它结束后插一次：240ms上浮12px/淡入且布局高度平滑展开，列表300ms easeOutCubic滚到该记录。

回程期间通过来源route的LocalHistoryEntry接管返回键，避免误退下层页；重复点击/返回/后台会清理overlay。进入取消不完成startGate，不启动或保存会话；后台发生在慢保存期间，晚成功也直接终态，不新建挂起的回程。直接卸载清理Ticker和FrameRecorder。减少动效进入/退出只用150ms交叉淡化，保留原图；退出页面淡化与chrome共用同一段150ms，pop后不再追加第二段。减少动效慢保存超过400ms时，可见的宿主层维持24px等待指示，数据仍由SDK保存；失败恢复完整SDK完成页。有限控制器使用AnimationBehavior.preserve，避免系统再次压缩已选定的150ms。

图文页保留其来源route和实际媒体槽，先释放预览再push训练；回程后恢复预览。聊天owner仍执行started的AI恢复/记忆门禁，在visualCompleted后接收一次finished。

## 验证与交付（候选已就绪，待开哥真机确认）

打包与全量测试源码为 **`ccdf1b1729ee6365edb3669aaacae320c23bd49f`**，版本 **0.1.0+48 / internal arm64 2048**，包名 `com.ugk.smartfit.internal`。SDK 三包、coach override、锁文件和“关于”页身份均为 **`c97a79a5f03ba1f46f017b995f7f8d97fb3016a9`**。后续收束只改 README/docs；最终文档 HEAD 与打包源码的区别由交付目录 `final-closeout.json` 记录，不把文档提交冒充重新构建。

固定 Flutter 3.44.7 全量 **798通过、0跳过、0失败**，`flutter analyze` **0问题**，严格离线锁解析通过，非SDK依赖不变。source fingerprint `d50d70cb08be57dd0e72fabc6f9b9d2597151466afbd5bf35192803500dcd030`；公开构建输入2705项，内容身份 `61a87e5a48700ac36760a4d7aa04ba68fe075cb18a2ff13ed0f1ad1d6796d1c8`。测试、软件图帧和两个APK都绑定同一源码/输入。

逐阶段回归覆盖：560ms最后一层终态以及计时/语音/视频门禁；进入与退出区间/曲线；提前结束保存与finished各一次、缩回结束后再插入；保存失败恢复完整完成页和问题按钮；自然完成显露最后动作海报；来源不可见回退、150ms减少动效、后台/返回/重复点击和晚到原生媒体清理；图文页返回后预览恢复；聊天offset=0/100时插入首帧无跳变。构建辅助工具另有20项单测通过，软件逐帧采集1项通过，均不叠加进798项App测试。

### 两种内测包

| 模式 | arm64 APK | 大小 | SHA-256 |
| --- | --- | --- | --- |
| release | [SmartFit-trainer-transition-0.1.0+48-ccdf1b1-internal-arm64-v8a-release.apk](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-trainer-transition-0.1.0+48-ccdf1b1-internal-arm64-v8a-release.apk) | 42,628,010B / 42.63MB / 40.65MiB | `8e9069a761092bcbdba9e3c661877c9199482bdf7f21d40c2b776178878f62c4` |
| profile | [SmartFit-trainer-transition-0.1.0+48-ccdf1b1-internal-arm64-v8a-profile.apk](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-trainer-transition-0.1.0+48-ccdf1b1-internal-arm64-v8a-profile.apk) | 59,584,897B / 59.58MB / 56.82MiB | `4d6db18e9c9512b92503a83c0adda314f2736413263c7ad3f7ffa2d21cc94d81` |

两个APK均已重新核对真实aapt包身份、源码指纹和配置身份、相同签名、ZIP及ELF 16KB、存储JNI、AssetManifest与ZIP无MP4、1737项保留图片/语音以及原Noto字体。签名证书SHA-256为 `3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`。release较+47基线增加29,904B，仍低于45,000,000B。profile含调试/分析运行时，独立核对5个原生库及官方Flutter VM service的JAR→merged→stripped→APK链，不继承旧c0的来源回执；release为4个原生库。

验包回执：[release](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/validation-release.json)、[profile](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/validation-profile.json)；[全量测试与源码绑定](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/tests-source-binding.json)；[profile官方运行时来源](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/profile-vmservice-origin.json)。两种包均保留现有AI/媒体正式配置，未进行手机安装、保留数据升级或真机播放验收。

### 浅深色逐帧演示

| 主题 | 进入 | 退出 |
| --- | --- | --- |
| 浅色 | [进入](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-plus48-entry-light-software-30fps.mp4) | [退出](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-plus48-exit-light-software-30fps.mp4) |
| 深色 | [进入](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-plus48-entry-dark-software-30fps.mp4) | [退出](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/SmartFit-plus48-exit-dark-software-30fps.mp4) |

以上是**实际Flutter/SDK界面的软件fake-time采集**，每步33,333μs并编码为30fps，进入18帧、退出25帧（含250ms控件退场、380ms缩回、120ms海报尾段及完成记录起点）。使用真实主题、字体、海报和SDK控件；媒体解码由测试替身代替。它们说明软件时序和画面层级，**不是手机录屏、实际刷新率或帧耗时证明**。[图帧及视频哈希清单](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/software-visuals.json)明确记录此边界。

### 真机待验与历史保留

ADB检查没有连接设备；开哥此前已说明无本机设备，改由远程安装反馈。进出各5次profile采样尚未执行：**UI最大帧耗时未测、Raster最大帧耗时未测**，不得填0或声称≤16ms。真机30fps进入/退出录屏也待安装后采集。当前状态为“候选软件验证完成、待真机确认”，未合并、未推送、未打tag；main仍为 `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`，release/1.0及SDK仓库不动。

普通动画保持560ms进入、250ms控件退场、380ms缩回及120ms交叉淡化；系统减少动效才选150ms。展开卡的SDK hero已不显示时，宿主不飞行不可见的旧hero，按无可用起点规则走fallback，不读取私有布局。

中间检查与旧交付均保留，不用失败记录冒充成功：早期两条旧交互测试按新的图文路由所有权更新后恢复全量；减少动效总时长和自然完成海报连续性完善后重新全量；首轮构建被“关于页仍显示旧SDK”门禁拦截，修正并加一致性测试后重跑至798项；第二次验包缺少用户已批准的字体保留政策，补入原政策及来源记录后重新构建。最终仅接受上面ccdf1b1绑定的两个新APK，旧APK、失败日志及各轮测试归档均未覆盖。

交付目录 `E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/`。旧 `trainer-transition-plus48` 与 `trainer-transition-plus48-redesign-audit` 目录只保留原时点证据。

方案比较参考 Flutter 官方维护的 [OpenContainer 实现](https://github.com/flutter/packages/blob/main/packages/animations/lib/src/open_container.dart) 及其 [BSD许可证](https://github.com/flutter/packages/blob/main/packages/animations/LICENSE)。本轮使用已有Flutter原语自行实现Rect/Overlay生命周期，不引入第三方转场依赖，也不复制其容器UI；避免默认容器飞行与SDK分块chrome时序相互叠加。
