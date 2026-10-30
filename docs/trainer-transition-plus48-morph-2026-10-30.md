# +48 卡片展开式训练过渡（2026-10-30）

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

SDK pop后独立Navigator OverlayEntry继续380ms缩回，背景在240ms内淡出；到位后真实源图恢复、海报再120ms交叉淡出。来源卡不可见则260ms整层1→.94淡出。visualCompleted包含整个回程尾段，完成记录只在它结束后插一次：240ms上浮12px/淡入且布局高度平滑展开，列表300ms easeOutCubic滚到该记录。

回程期间通过来源route的LocalHistoryEntry接管返回键，避免误退下层页；重复点击/返回/后台会清理overlay。进入取消不完成startGate，不启动或保存会话；后台发生在慢保存期间，晚成功也直接终态，不新建挂起的回程。直接卸载清理Ticker和FrameRecorder。减少动效进入/退出只用150ms交叉淡化，保留原图；退出页面淡化与chrome共用同一段150ms，pop后不再追加第二段。减少动效慢保存超过400ms时，可见的宿主层维持24px等待指示，数据仍由SDK保存；失败恢复完整SDK完成页。有限控制器使用AnimationBehavior.preserve，避免系统再次压缩已选定的150ms。

图文页保留其来源route和实际媒体槽，先释放预览再push训练；回程后恢复预览。聊天owner仍执行started的AI恢复/记忆门禁，在visualCompleted后接收一次finished。

## 验证与交付（收束中）

定向实际SDK回归覆盖门禁、每层区间/曲线、保存失败、自然完成、生命周期和原生媒体迟到释放；聊天与图文回归覆盖完成记录一次、第一帧锚点保持和预览恢复。全量测试/analyze、源码SHA、两种APK与验包结果将在最终源绑定回执完成后补入；当前不预填成功结果。

交付目录 `E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus48-morph/`，保留旧交付目录不覆盖。本机ADB没有设备，真机进出各5次的UI/Raster最大值和手机录屏待远程安装后采集；软件30fps逐帧演示另列，不能当作性能或真机验收。

方案比较参考 Flutter 官方维护的 [OpenContainer 实现](https://github.com/flutter/packages/blob/main/packages/animations/lib/src/open_container.dart) 及其 [BSD许可证](https://github.com/flutter/packages/blob/main/packages/animations/LICENSE)。本轮使用已有Flutter原语自行实现Rect/Overlay生命周期，不引入第三方转场依赖，也不复制其容器UI；避免默认容器飞行与SDK分块chrome时序相互叠加。
