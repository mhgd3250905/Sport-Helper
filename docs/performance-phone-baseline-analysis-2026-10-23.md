# +16 手机性能基线分析（2026-10-23）

这两份真机 release 数据显示：聊天相关场景的主要持续压力在 Raster 绘制/合成阶段，UI build 大部分帧较轻。它们是同一版本的两个不同场景，不能当作优化前后对比；目前还不能把具体玻璃效果、图片、星尘或 SDK 判为根因。本次只分析报告和源码，没有改运行代码、SDK、启动模拟器或打包。

## 输入与采样条件

| 项目 | 第一份 | 第二份 |
| --- | --- | --- |
| 原文件 | `F:/test-logs/SmartFit-performance-20261023T072429339031Z.json` | `F:/test-logs/SmartFit-performance-20261023T072556285057Z.json` |
| 时间（北京时间） | 15:23:48.586–15:24:29.336 | 15:24:43.057–15:25:56.280 |
| 整份记录窗口 | 40.751 秒 | 73.223 秒 |
| 手动场景标签 | `longChatScroll` | `planExpand` |
| 整份记录 / 场景帧数 | 1,863 / 1,323 | 4,353 / 3,963 |
| 导出时消息条数 | 12 | 17 |
| 无法归属 / 无效帧 | 0 / 0 | 0 / 0 |
| 后台期间排除帧 | 2 | 0 |

共同条件：小米 `2602BRT18C`，Android 16 / API 36，非模拟器；`0.1.0+16` internal release / Android versionCode 2016；源码 `4319e1e345317b9e9cc47b435ab210a181a0ef12`；SDK `f684e02f38e652633c23fa8946a53d02b6aa3ea2`；浅色、星尘开、93 个动作。两份 `measurementKind` 都是 `baseline`。

display 报告约 120 Hz，因此记录器采用约 8.333 ms 的超预算阈值。这个值是显示设备刷新率，不是已测得的 App 实际呈现 FPS；这些数据没有屏幕 present 事件，也没有每帧原始时间序列，不能由它们计算实际屏幕丢帧率或确认系统是否把 App 渲染节奏限制在其他频率。

`renderer=unverified`，手机实际 Impeller/Skia 后端未确认。`glassQuality=adaptive_initial` 也不是实际玻璃档位，详见下文。两份均有 `conditionChangesDuringCapture=0`，但它只覆盖记录器实际收到的条件，不能补全未记录的质量切换。

## 采用场景组，排除设置页的稀释

单位 ms；“超预算”按上述约 8.333 ms 阈值。P90/P99 来自有界直方图上界，误差不超过 6.25% 或 1µs；均值、最差和计数精确。

| 场景 | 线程 | 平均 | P90 | P99 | 最差 | 超预算帧 / 占比 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 聊天滑动，1,323 帧 | UI build | 0.807 | 1.151 | 4.095 | 33.480 | 10 / 0.76% |
| 聊天滑动，1,323 帧 | Raster | 10.670 | 16.383 | 18.431 | 80.040 | 780 / 58.96% |
| 计划卡场景，3,963 帧 | UI build | 0.981 | 1.471 | 9.727 | 29.808 | 47 / 1.19% |
| 计划卡场景，3,963 帧 | Raster | 10.852 | 17.407 | 19.455 | 80.417 | 2,622 / 66.16% |

联合超预算分别为 786 / 59.41% 和 2,645 / 66.74%，同一帧两线程超时只计一次。第一份有 780 个联合超预算帧同时 Raster 超时，只有 6 帧仅 UI 超时；第二份相应为 2,622 和 23 帧。这是优先查绘制/合成路径的依据，但不等同于认定 GPU 算力、特定 shader 或某个组件有缺陷。

UI 存在约 30 ms 的偶发峰值，第二份 UI P99 也略超预算，仍需保留后续检查。当前却没有证据支持把“整个聊天页持续重建”或“大 JSON 解析”作为这两份的主要原因。仅先重构 builder / isolate，未必能改善主要 Raster 压力。

整份 `total` 的 Raster 超预算比例是 43.69% / 60.99%，低于聊天场景的 58.96% / 66.16%，因为混入了设置/性能报告等较轻页面。分析用户反馈时应优先看 `scenarios` / `pages.chat`。两份场景组恰好等于对应 `pages.chat`，说明标签窗口覆盖了该段聊天页，无法分离静止、每次滚动和每次展开动画的瞬间。记录器也没有给出各场景的独立墙钟持续时间。

## 源码复核与优先级

| 项目 | 可核实证据 | 本轮结论与下一步 |
| --- | --- | --- |
| 自适应玻璃目标预算 | App `lib/main.dart:140–146` 未传 `targetFrameMs`；固定依赖 liquid_glass_widgets 1.14.0 的 `lib/widgets/shared/glass_adaptive_scope.dart:279` 默认 16 ms，`lib/utils/glass_quality_adapter.dart:616` 降档检测为 P95 > 1.5 × 目标，即约 24 ms。 | 已确认配置未对齐记录器的 120 Hz 预算；10–19 ms 的 Raster 成本可能持续超出 8.33 ms，却不触发该降档规则。需要确认实际呈现节奏，再用内测对照验证按刷新率适配目标的作用；这不是具体玻璃根因的证明。 |
| 实际玻璃质量没有被可靠记录 | `lib/main.dart:231` 读取 `store.glassQuality ?? 'adaptive_initial'`；`lib/data/app_store.dart:289–294` 静默保存质量，不通知 MaterialApp 重建；`lib/ui/performance_settings.dart` 导出只刷新消息和动作条数。 | 确认是记录器条件信息缺口。下次采样应直接记录实际 effective quality、phase、frost、适配预算及变化，而不能把当前占位值当真实档位或把变更计数 0 当质量稳定证明。 |
| 聊天页常驻玻璃与背景捕获 | `lib/ui/chat/chat_home_page.dart:242–257` 把颜色层及滚动消息放入 GlassBackgroundSource；`lib/ui/theme/glass.dart:133–147` 使用独立 GlassContainer layer；`lib/ui/chat/chat_widgets.dart:565–567` 输入栏请求 premium，建议条及计划卡请求 standard。 | 两份 Raster 均值接近，优先验证聊天共用渲染层。做可恢复的内测 A/B 开关、同屏截图后再选外观，不能直接删除磨砂或改变默认设计。 |
| 计划卡展开的合成、裁切、图片预热 | `lib/ui/chat/plan_card.dart:654–690`、`:755–775`、`:948–975` 的动画 Opacity/clip；`:368–385` 的原尺寸预缓存。 | 仍是候选；没有动画事件边界或 Timeline，80 ms 尖峰不能归因给某次展开、saveLayer 或图片解码。下一步需将首次与热缓存展开、静止窗口分别采集。 |
| 星尘 | `lib/ui/chat/cosmos.dart:71–75` 约 30 Hz 更新独立 painter，`:93` 有 RepaintBoundary；本次浅色模式，`:181–183` 的模糊 halo 仅在深色执行。 | 不能说星尘导致整页 build，也不能把深色 halo 当本次原因。已有设置开关，适合先做同场景开/关对照，无需模拟器或新包。 |
| 旧动画 WebP 分支 | `lib/app/services.dart:274–282` 使用 Pose-Hub override；`lib/domain/exercise.dart:113` 和 `lib/ui/theme/media_theme.dart:36–39` 排除 cutout，+16 APK 无 cutout 文件。 | 不作为本版优先候选，不能仅因仓库保留旧分支代码就认定有持续动画 WebP。 |
| SDK | 当前页面组为聊天/设置，没有训练、动作详情视频或下载/校验窗口。 | 暂无能确认的 ugk_coach / ugk_trainer 性能缺陷。SDK 保持不改；共享训练播放器、下载/校验问题仍等待对应场景证据。 |

以上 App 行号对应当前 +16 运行源码；第三方包位置对应锁定的 1.14.0 本地源码，只读检查，没有修改 pub 缓存。

## 下一次最小对照

先使用现有 +16 包，在同一会话、同一计划、同一浅色与缓存状态下，采同一场景各约 30 秒：星尘开和星尘关各重复 3 次。每轮开始清空一次，保持实际操作相同，分别导出。这个对照只改变已有设置，既不需要模拟器，也不先去掉玻璃。

新内测包首先补足实际玻璃质量/预算记录，再逐个加入玻璃质量或背景捕获的诊断开关；外观会变化的开关应提供开/关同屏截图给开哥选择。若无线调试可用，用真机 profile Timeline/Rebuild 捕捉静止、滚动、首次展开和热缓存展开，检查实际光栅化、离屏层、图像解码及等待。不要同时修改星尘、玻璃和图片，避免失去归因。

这两份各只有 12 / 17 条消息，不是数百条聊天的规模压力测试；只有聊天和计划卡两个场景，动作库、筛选、动作详情、训练切动作、下载/校验中滑动这五项仍无本轮手机数据。当前没有修复后版本或前后性能提升结论，不合 main、不推送。

数据含义参考：[FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)、[显示刷新率](https://api.flutter.dev/flutter/dart-ui/Display/refreshRate.html)、[引擎批量帧回调与流水线](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)。
