# +49 训练进出动画性能候选（2026-10-30）

**0.1.0+49 / internal arm64 2049**，分支 `codex/trainer-transition`。打包/全量测试源码 `c1d1c3994061cb451bed2b92501a665dc0bd61e4`；SDK三包及override仍锁 `c97a79a5f03ba1f46f017b995f7f8d97fb3016a9`，整份锁文件与3934da7相同。全量 **827/827、0跳过/失败**，analyze **0问题**；release **42,657,842B**、profile **53,609,054B**，同签名、16KB及JNI检查通过。+48设计时长/曲线/编排保留；新增内部近10次FrameTiming与复制页面。真机指标尚未采集，候选未合并、未推送、未打tag；main/release/1.0与SDK源码未改。

本轮从文档提交 `3934da7c546c8cb161a6c450baed5ce8513dc973` 继续。+48真机反馈确认了“卡片动作主体展开/缩回”的设计，同时指出运动卡顿；本候选继续性能验证，不把设计确认当作帧耗时验收。main仍为 `d8d6db76fc631f47afbf3740f67d2d00ebfff2f6`，release/1.0保持原状，不操作SDK仓库。工作树为 `E:/AII-3D/3D-Sport-AI/Sport-Helper-trainer-transition`。

## 定位方法与边界

先在+48实际Flutter/SDK界面用WidgetTester、Dart VM Timeline和官方debug build/layout/paint hooks采集进入/退出各5次，再采+49同场景。步长33,333μs，390×844/DPR1，原始每帧数据及inclusive/exclusive span保留。[+48定位](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/BASELINE-SOFTWARE-ANALYSIS.md)、[完整前后对照](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/SOFTWARE-BEFORE-AFTER.md)。

这些是带探针的Windows debug软件数据。它们能确认冗余调用、树结构和代码热点，不能给出Android profile的FrameTiming.build/raster、GPU完成时间或手机实际帧率。+49软件墙钟没有全面改善，本报告保留全部数字；真机目标待新内部页面采集，绝不填0或推定达标。

## 逐项排查与修改

| 项目 / 代码位置 | +48定位 | +49处理及证据 |
| --- | --- | --- |
| 布局：`lib/ui/training_transition.dart`；`training_poster_flight.dart` | Rect逐帧改变Positioned尺寸，海报/图片反复layout。热进入Image layout合计0.282–0.418ms，不能解释为几十毫秒总根因 | 固定舞台布局，AnimatedBuilder传稳定像素child，仅Transform平移/缩放及clip变化；反向补偿contain，人物不拉伸。热进入布局27→1、0.014–0.028ms；热退出16→1、0.011–0.021ms（每次合计、带探针） |
| 重绘：`training_poster_image.dart`、`training_transition_freeze.dart`、`chat_home_page.dart`、`main.dart` | SDK chrome入场paint密集；pop/finished时对话树出现数百次build突发 | 海报和宿主问题按钮独立RepaintBoundary，底页保留真实静态层，模型通知继续收集，转场后合并呈现；不改数据保存时点。进入build482→387、paint1776→1704；退出build1201–1305→812–864，paint2137–2169→1798–1830 |
| 圆角/透明度：`training_poster_flight.dart` | 圆角/影像跟随移动图尺寸重建，旧大图Opacity产生组合层风险 | ClipRRect明确antiAlias，圆角按x/y反缩放后保持物理20→0/0→20；背景只改颜色alpha。常规运动不对整舞台做Opacity，规定的淡入/交叉尾段用FadeTransition及稳定图层；FadeTransition本身不保证所有组合都无离屏层 |
| 毛玻璃/阴影：固定SDK c97 `trainer_surface.dart` / theme | 当前训练主题是实色，没有BackdropFilter；仅固定blur4接触阴影，没有大半径移动毛玻璃 | 保留原材质与阴影，不引入临时替代底色或视觉切换。SDK三个内部chrome边界仍需SDK侧支持，见下节 |
| 解码：`training_poster_image.dart`、`training_card_media.dart`、`coach_ui_adapter.dart`、`cached_exercise_media.dart` | 预热raw AssetImage，显示却是带cacheWidth的ResizeImage，键不同；原软件第0帧有缺图 | 卡片可见即预热，宽=屏宽×DPR，点击前等同键解码完成；卡片/舞台相同素材共享已解码像素。RawImage稳定复用，进入Image paint19→3、退出15→1；测试验证共享image clone与布局/像素widget身份 |
| 重任务：`player_page.dart`、`gated_posehub_media_preparer.dart`、`training_transition_activity.dart`、`posehub_media_repository_io.dart`、`app_store.dart` | SDK门禁前会申请媒体预取；宿主缓存SHA/LRU与完整状态JSON可撞上运动；PlayerPage重建会重新PlanCodec转换/遍历动作库 | 公共preparer适配等待startGate及短转场空闲；计划预取在门禁完成后的frame尾启动。缓存校验chunk/原子LRU提交等待转场空闲，保留安全检查/300MB/并发限制。计划、rhythm与voice按输入身份缓存。大JSON在compute编码，保存仍与退场并行并在持久化成功后提交记录。小于16KiB严格上界的快照保留轻量路径；toJson/不可变快照建立仍在UI队首一次，不宣称全部保存工作已离开UI |
| 控件：SDK c97 `trainer_chrome.dart`；宿主`player_page.dart`的IssueMotion | SDK已使用一个共享chrome animation及Interval，各小块走paint变换 | 保持原5层时序/曲线；宿主问题按钮同区间、FadeTransition+Transform+独立边界。没有拷贝SDK控件或改私有State |
| 着色器/后端：原有`InternalRendererProbe.kt`、`performance_report.dart`；新`training_transition_timings.dart` | manifest不强制后端；软件首轮有debug JIT，不是手机shader证据 | 复用本进程实际引擎启动日志探针，记录Impeller/Skia及Vulkan/OpenGLES、verified；未知保持unverified。首次/热2–5按进程、方向分别标记，不强制切后端，不投放猜测的shader包 |

SDK核查证据与基线具体行号见[启动、媒体、语音与保存审计](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/SDK-STARTUP-AUDIT.md)。560ms前没有SDK计时、语音begin、hold或宿主视频控制器；此调用链未发现摄像头、姿态模型或TTS初始化。共享音频输出在App启动创建，预门禁音量赋值不等于新建原生播放器或开始播放。

## 软件耗时前后对比

下表为单次 `WidgetTester.pump` 的 **Stopwatch wall最大值/P90，ms**；含debug hooks、Timeline、JIT/调度及不同树结构的探针开销。它不是手机build/raster指标，不能与8ms/12ms目标直接比较。真实I/O/worker等待在第0测量帧之前单列，不混入绘制耗时；旧/新fixture都按同一560ms和33,333μs步长推进。

| 轮次 | +48进入 max/P90 | +49进入 max/P90 | +48退出 max/P90 | +49退出 max/P90 |
| --- | --- | --- | --- | --- |
| 1（首轮） | 30.320 / 8.650 | 65.380 / 18.915 | 45.257 / 10.332 | 78.984 / 17.893 |
| 2 | 15.548 / 5.604 | 28.351 / 8.360 | 30.850 / 5.591 | 43.842 / 4.240 |
| 3 | 13.273 / 4.684 | 18.729 / 5.807 | 37.175 / 6.704 | 50.605 / 6.883 |
| 4 | 11.787 / 4.148 | 24.500 / 6.588 | 29.628 / 3.638 | 45.319 / 5.872 |
| 5 | 15.359 / 5.134 | 15.015 / 4.874 | 38.736 / 4.697 | 42.127 / 5.031 |

热运行进入Image布局合计从0.282–0.418ms降至0.014–0.028ms；热退出从0.225–0.351ms降至0.011–0.021ms。整体软件墙钟没有全面下降，不能只用调用数下降宣称实际运动已达标。实际SDK chrome/GPU、原生纹理退场、首轮管线/字形缓存成本还需设备FrameTiming/Timeline辨别。仅首次慢也可能来自解码、管线或原生懒初始化；须用实际后端及shader事件判断。[Flutter性能最佳实践](https://docs.flutter.dev/perf/best-practices)、[Impeller](https://docs.flutter.dev/perf/impeller)、[DevTools性能视图](https://docs.flutter.dev/tools/devtools/performance)为核查依据。

## 同帧视觉与功能

560ms进入、420ms Rect、280ms背景、SDK原错开区间、250ms退场、380ms缩回、120ms尾段及150ms减少动效都保留。几何测试逐阶段断言实际绘制clip与圆角；固定图片布局、contain比例、560ms门禁、保存一次/finished一次、失败完整完成页、保存与退场并行、列表锚点、后台/返回/重复点击清理、图文预览恢复均已回归。

86组浅深同帧PNG、24张三列对照保留，左+48/中+49/右未遮罩4倍差值。示例：[浅色进入500ms](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/same-frame-comparison/light-entry-015.png)、[深色进入500ms](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/same-frame-comparison/dark-entry-015.png)、[浅色退出400ms](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/same-frame-comparison/light-exit-012.png)、[深色退出400ms](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/same-frame-comparison/dark-exit-012.png)。

原第0帧缺图被预解码修复，人物/阴影有细微重采样差，采集问候/时钟也不同；原图与差值完整展示，不声称逐像素零差。控件时序、位置、人物比例和颜色编排的受控几何与目视比较保持原设计。原始差异及哈希见[同帧清单](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/same-frame-comparison.json)。

软件采样源码 `962d6b2dc85d72c098fd549fa843bb25b83d11a2` 与最终打包源码 `c1d1c3994061cb451bed2b92501a665dc0bd61e4` 之间只有测试文件变化，运行输入2715项/内容身份 `cf7d5cc713d4e63de0fdd0aa156db4e346eea4c34f7568e5747d7c5f69624c2c` 完全相同。测试夹具显式适配native worker与fake clock、ResizeImage、预解码及flushPersistence；不更改生产编码路径、不减少断言、不跳过用例。专门6项序列化回归仍使用真实默认compute；软件探针不传fixture-only编码开关。

完整测试由 `run_checks.py` 执行 `flutter test --no-pub --concurrency=1 --flavor internal --reporter expanded --dart-define=SMARTFIT_POSEHUB_PACK=true --dart-define=SMARTFIT_ALPHA_CARDS=true --dart-define=UGK_INTERNAL_MEDIA_PREVIEW=true --dart-define=SMARTFIT_WIDGET_FAKE_STATE_ENCODER=true`。最后一个开关只在 `test/app_flow_test.dart` 的内存widget夹具中读取，用于避免fake clock跨zone等待native worker；生产 `lib/` 不读取它，两个APK均不传此开关。实际默认compute的独立6项序列化测试仍照常执行，日志、命令与开关边界见测试源绑定回执。

## APK与检查

全量 **827通过、0跳过、0失败**，analyze **0问题**；严格离线锁解析通过，整份pubspec.lock与3934da7一致。两个APK皆从 `c1d1c3994061cb451bed2b92501a665dc0bd61e4` 新构建，签名证书与+48相同：`3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`；ZIP/ELF 16KB、存储JNI、无MP4、原Noto及1737项静态/音频保留检查通过。profile的第5个VM service库有本次官方Flutter69c8 JAR→merged→stripped→APK来源链。

| 模式 | arm64内测包 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| release | [SmartFit-trainer-transition-0.1.0+49-c1d1c39-internal-arm64-v8a-release.apk](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/SmartFit-trainer-transition-0.1.0+49-c1d1c39-internal-arm64-v8a-release.apk) | 42,657,842B / 42.66MB | `134d3886f4220e71590b24b9914402de67d2b74d71ea4949d9f8c940ac3c6bd0` |
| profile | [SmartFit-trainer-transition-0.1.0+49-c1d1c39-internal-arm64-v8a-profile.apk](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/SmartFit-trainer-transition-0.1.0+49-c1d1c39-internal-arm64-v8a-profile.apk) | 53,609,054B / 53.61MB | `c7c1becb0c77231821981c3dbda16735e017e24fecd2ce5cb6e64bd702ca39a3` |

release较+48的42,628,010B变化 `+29,832B`，不超过45,000,000B。验包：[release](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/validation-release.json)、[profile](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/validation-profile.json)；[测试/源码绑定](E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-performance/tests-source-binding.json)。后续README/docs-only提交和最终Git范围由交付目录 `final-closeout.json` 单独记录，不改变打包源码或冒充重新测试构建。中间失败/取消的检查、探针和fixture定位日志均保留，最终验收只引用本节成功源绑定回执。

## 内部页面与开哥采集步骤

入口：**设置 → 内测工具·正式版不显示 → 训练进出帧耗时**。internal release/profile均可查看；正式flavor入口及采样均关闭。每次进入/退出记录帧数、build最大/P90、raster最大/P90、各自及合并>16ms帧数、原始engine帧号/vsync时间、版本/源码/SDK、真实后端与首次/热运行标记。P90最近秩法，16ms严格“>”，同一帧只合计一次。空样本/中断/减少动效/截断不伪造达标。

1. 安装 **profile** 包。系统应用设置中强行停止后重新打开一次，保留原数据，不在每轮之间重启App。
2. 用同一张可见计划卡，单击开始、等进入完成，再点×并确认结束；等缩回、完成记录和列表滚动结束。连续做 **5轮**，得到进入/退出各5条。避免动画中重复点击；首次单列，第2–5次为热运行。自然完成的“完成”路径也可另行采样。
3. 打开上述内部页，确认最近10条包括本次启动进入/退出1–5，点 **复制最近10次 JSON** 后粘贴回会话。引擎批次可能延迟约1秒；页面显示待回传数量，复制会等正常尾段并刷新迟到修正，不需要电脑或ADB。后台慢保存与失败重试有独立outcome/标记，别与正常5轮混算。

JSON异步保存到Application Support下 `diagnostics/training-transitions/recent.json`，重启保留最近10次。每帧不编码、不写文件、不通知UI；统计与JSON编码用compute，保留延迟FrameTiming的首尾engine帧。当前本机无设备：**手机build/raster最大/P90、>16ms帧数、实际后端、首次shader情况均未测**。目标为profile热第2–5次每个方向build P90≤8ms、raster P90≤12ms、>16ms≤1帧；当前不宣称通过。

## SDK配合事项（单列，未修改）

当前公开接口足以完成宿主优化。SDK c97的顶部信息/HUD/提示卡尚无独立内部RepaintBoundary，宿主不能通过公开接口单独包这三个私有child。若要求这三层也各自隔离，建议SDK在 `packages/ugk_trainer/lib/src/ui/trainer_chrome.dart:30-35` 的 `_chromeLayer` stable child加边界，或提供可选 `chromeLayerBuilder(layerId, child)`；不改布局、时长和曲线。实际Android成本占比仍待profile。

SDK `ugk_play_pause_button.dart:156-166` 的装饰呼吸在paused状态仍会运行。若设备Timeline证实为热点，可提供独立 `decorativeAnimationGate/chromeEffectsEnabled`，不停止共享chrome时钟。门禁前媒体优先请求在 `trainer_player.dart:591`，本轮已用公开preparer适配及宿主工作窗口解决；可选SDK `mediaPreparationGate` 可使其更直接。上述均是独立SDK建议，本候选三包仍严格c97，没有绕过私有State、反射或拷贝控件。
