# SmartFit 滚动卡片静态仿玻璃修复（+18）

针对已确认的计划卡玻璃路径开销，滚动计划卡改为静态仿玻璃：半透明底色、细高光描边和轻阴影，分别适配浅色/深色。卡片不再执行背景模糊、饱和度过滤或设置背景捕获源。计划卡内容、尺寸、展开动画和按钮布局保持原样；固定建议条、输入框与其他固定玻璃控件继续使用原材质。星尘未改，SDK 与锁文件未改。

本轮源码验证和手机帧性能验收分开记录。+17 手机对照已确认主要开销，见 [原手机分析](performance-phone-raster-analysis-2026-10-23.md)；+18 的真机 P99 与超预算比例必须等待安装复测，不能由 widget 截图或测试代填。没有启动模拟器，没有合入 main 或推送。

## 修改范围

| 位置 | 修改 / 审核结果 |
| --- | --- |
| `lib/ui/theme/glass.dart` | 新增 `SfScrollCardSurface` 静态材质；生产无真玻璃卡片分支或聊天背景捕获源。内测可恢复整条旧卡片玻璃路径，未增加逐层滤镜实验 |
| `lib/ui/chat/plan_card.dart` | 多动作计划、单动作卡共用新表面；整张重卡片增加独立 `RepaintBoundary`，用于重绘隔离，不作为纹理捕获源 |
| `lib/ui/chat/validated_plan_card.dart` | SDK 校验后仍适配到 App `PlanCard`，自动使用新表面；SDK 不变 |
| `lib/ui/chat/action_card.dart` / `lib/ui/theme/widgets.dart` | 动作推荐卡原本就是静态 `SfPanel`，无背景过滤；保持原样。其他滚动列表未发现 App 直接玻璃调用 |
| `lib/ui/chat/chat_home_page.dart` | 默认聊天内容不再成为 `GlassBackgroundSource`；仅内测旧卡片对照恢复该源。消息既有重绘隔离保持 |
| `lib/main.dart` / `lib/ui/theme/adaptive_glass.dart` | 生产和内测统一 App 自适应控制器，预算为精确 `1000 / display.refreshRate`；关闭第三方固定整数预算控制器。保留原阈值比例，换刷新率清统计窗口与旧冷却期 |
| `lib/diagnostics/*` / `lib/ui/performance_settings.dart` | 内测新增「列表卡片真玻璃」，默认关、不持久化；生产无入口。每帧与元数据记录实际 `scrollCardGlassEnabled`，schema 2 / `raster_controls_v3` |
| `tools/performance/raster_matrix.py` | 保留旧 +17 / v2 读取；显示每格真实卡片模式，拒绝将不同卡片模式混作原有单开关差值 |

普通 `RepaintBoundary` 缓存重卡片的绘制，与带 scope key、供纹理读取的 `GlassBackgroundSource` 用途不同。生产保留前者、移除后者。

## 观感对照

以下是实际 App / PlanCard 的 Flutter widget 渲染图，不是手机或模拟器截图，不作为帧性能样本。每对使用同一挂载 App、固定内容/图片/字体/滚动位置/静态星尘，玻璃强制 minimal，与 +17 采样档位一致。旧 `SfGlassSurface` 与 +17 源码逐字相同。

| 主题 | 修前 | 修后 |
| --- | --- | --- |
| 浅色 | [修前截图](screenshots/performance-scroll-cards/plan-light-before.png) | [修后截图](screenshots/performance-scroll-cards/plan-light-after.png) |
| 深色 | [修前截图](screenshots/performance-scroll-cards/plan-dark-before.png) | [修后截图](screenshots/performance-scroll-cards/plan-dark-after.png) |

截图断言计划卡和单动作卡前后矩形完全一致。描边最初造成的 1.6px 隐式内边距已修复，使用 `DecoratedBox` 与显式内边距，未改变卡片尺寸。浅色卡面更接近白霜，深色略微提亮。四张均已查看，无裁切或溢出。重现步骤和图片 SHA-256 见 [截图说明](screenshots/performance-scroll-cards/README.md) 与同目录 `visual-review.json`。

## 手机复测

1. 覆盖安装 +18 arm64 internal release。包名保持 `com.ugk.smartfit.internal`，版本升为 2018。旧 +17 包、原 JSON 与截图均保留。
2. 保持与原报告相同的手机、竖屏、浅色、120Hz、字体和显示缩放。进入「设置 → 导出性能报告」，「列表卡片真玻璃」保持默认关闭；不改变原星尘偏好。
3. 开始新一轮，进入「生成 72 条测试会话 · 八格自动采样」，按上一轮相同的八格、相同步骤完成并导出 JSON。每格仍自动往返 32 秒，前两秒单列，稳态按原口径统计；没有改变测试内容、距离、步速或标签含义。
4. 报告应为 `raster_controls_v3`，实际 `scrollCardGlassEnabled=false`。玻璃开/关仍指全局开关（包含固定输入框），卡片模式另记。若需要整体旧效果对照，可在内测设置打开列表真玻璃另开一轮；切换期间不混合采样。

验收重点为 **全局玻璃开启时的计划卡滑动**，因为固定输入框应继续保留玻璃。120Hz 下稳态 Raster **P99 < 8.33ms**、超预算接近 0，并确认聊天没有退步。实际刷新率、renderer、主题、质量与卡片模式必须随数据检查；若新版质量与 +17 minimal 不同，不能把两份均值直接当作相同条件的精确收益。超预算比例是引擎耗时统计，不冒充屏幕实测 FPS。

首次进入计划卡页的原 Raster 最差 30.793ms 已单独记录，本轮没有针对该尖峰改启动/转场；新包仍保留全局首次进页前两秒窗口，复测后再判断是否处理。

## 验证与交付

全量 Flutter 测试 382 项通过，3 项跳过（1 项内测专用、2 项需显式开启的截图生成）；internal 专项 82 项通过，2 项生产门禁断言由默认全量验证。两项浅色/深色截图生成检查通过。静态分析零问题；Python 性能工具 44 项通过（八格工具 27、既有比较工具 17）。`git diff --check` 通过，依赖锁文件与修前 +17 分支提交 `67d16ab` 字节相同，SDK 固定引用保持原样。

手机包：[SmartFit-0.1.0+18-static-scroll-cards-internal-arm64-v8a-release.apk](../.buildlog/install/SmartFit-0.1.0+18-static-scroll-cards-internal-arm64-v8a-release.apk)。源码提交 `c6f09087a3dd1c3e291bc18e6722223ba52fd91f`；后续交付文档提交不冒充重新打包。

| 安装包检查 | 结果 |
| --- | --- |
| 身份 | `com.ugk.smartfit.internal` / versionCode `2018` / arm64-v8a / release / 非 debuggable |
| 大小 | 49,597,887 字节 |
| SHA-256 | `88b6f9bf9289e45b7a63d38fe0aa4a52173323a248ed050d8628b35b8fe483e0` |
| 签名 | v2 验证通过，与 +17 signer 相同，可覆盖安装 |
| JNI | 实际 arm64 release 的 Android 存储 JNI 门禁通过 |
| 内测标记 | AOT 含 v3、记录器、列表卡片开关、固定会话及实际打包源码标记；native 探测/分享标记存在；没有 profile VM-service 扩展 |
| 生产隔离 | 实际 arm64 production release 的 7 项 Dart 内测标记、3 项 native 内测标记及 profile VM-service 扩展全部不存在；静态卡片存在，JNI 与签名检查通过。不交付该无 AI 构建凭据检查包 |
| 手机性能 | +18 已收到 8/8 有效格；默认计划卡 P99 9.215ms、超预算 3.951%，明显改善但未达到 P99 <8.33ms，暂未通过验收 |

机器可读身份与检查见 [交付记录](reports/performance-static-scroll-cards-delivery-2026-10-23.json)。手机修前/修后、剩余玻璃路径、聊天与进入尖峰见 [真机复测分析](performance-static-scroll-cards-phone-review-2026-10-23.md)。本轮未将关星尘或全关玻璃的结果替代默认配置验收，没有继续修改运行代码。

Cockpit 本地服务不可达，旧进度请求仍未确认；保留原 clientRequestId 和参数，不用新请求号绕过。源码、截图、测试结果与包身份已在本地 Git 分支保存。

本轮留在 `feat/performance-baseline`，开哥复测和同意后才合入 main 并推送。图标配色分支保持独立，性能先合，之后再 rebase、复测并按确认顺序合入。`ask_user` 询问气泡仍待本轮合入后开始。
