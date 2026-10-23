# SmartFit 流畅度基线包（2026-10-23）

本轮先交付 `0.1.0+16` 内测记录器基线，分支 `feat/performance-baseline`，基于开哥已验收的 `+15` 保存节点 `c35068003fe484f793ce051134444ae3b0172c4d`。业务、素材、视觉效果及 SDK 实现保持原样。尚未实施性能修复；手机基线、修复后同场景对比和开哥同意是后续合入 main、推送的前置条件。

两项 SDK 仍固定 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`。本轮只读审核其引用版本，不修改 SDK、pub 缓存或升级依赖。[App 候选和 SDK 待调查清单](performance-static-audit-2026-10-23.md)明确区分静态怀疑与实测结论。

## 开哥手机怎么采集

安装 arm64 internal release 基线包，沿用 `com.ugk.smartfit.internal`，覆盖已有内测版即可保留原设置和聊天。首次打开先正常使用约 10 秒，让自适应玻璃质量稳定。

下载源沿用 +15 的本机测试主/备地址 `192.168.71.116:8778/8779`，未上传云端。内置动作可离线使用；采集下载场景时手机需能访问本机素材服务。本次启动的只读服务使用正常速度，未人为降速到手机包里。

1. 打开「左下角我的计划 → 设置 → 导出性能报告」，点「开始新一轮」。只在一轮开始时清空，不要每换场景都清空。
2. 选择一个场景，点「开始此场景并返回」，到目标页面操作约 20–30 秒。回设置选下一个场景。设置与性能报告页不计入场景，导航到目标页的转场可能计入，复测时保持相同步骤。
3. 依次覆盖动作库快速滑动、筛选切换、动作详情进出、长聊天滑动、计划卡展开/收起、训练页切换动作、下载和校验进行中的滑动。下载场景必须实际开始下载；仅选标签不会制造下载。若没有可下载素材，在反馈中标注未跑。
4. 全部操作后点「导出性能报告」，稍候会打开 Android 系统分享。选择飞书或其他保存方式，再把 JSON 交回。界面只确认分享面板已打开，不声称已经发送成功；取消或失败后内存统计仍保留，可以重试。

本轮记录只在内存，重启 App 会清空；需在退出前导出。没有自动上传。报告不含聊天内容、动作名、密钥、用户文件路径或设备唯一标识。已有「运行日志」是另一条排障通道，它仍按 +15 行为保存，不用于逐帧记录。

对比时保持同一手机、系统刷新率、主题、星尘开关、玻璃质量、聊天长度、计划规模与缓存状态；冷缓存和热缓存分开。报告中的 `conditionChangesDuringCapture` 非零，表示本轮条件发生变化，应重新稳定设置后清空开始。系统省电、温度和后台负载也应尽量一致。

## 指标和实现

`SchedulerBinding.addTimingsCallback` 同时统计 UI build 和 Raster：平均、P90、P99、最差以及超过当前刷新周期的帧数。两线程同时超预算的同一帧只在联合数里计一次。`estimatedMissedVsyncs` 是根据最慢线程估算的吞吐错过周期数，不能称为实测屏幕丢帧。两线程是流水线，耗时不能直接相加当帧时长。Flutter 帧也不覆盖 WebView 独立 compositor/视频解码的全部帧。

设备元数据来自 Android：型号、厂商、系统、API、实际安装包 versionName/versionCode、是否模拟器。刷新率来自实际 display，更新时写入标签；无法取得元数据会明确标不可用。实际渲染后端默认 `unverified`，不能把默认配置当成手机已确认开启 Impeller。

按固定页面标识自动分组，手动场景采用固定枚举。标签在下一个 scheduler frame 生效，通过引擎 `frameNumber` 与延迟到达的 `FrameTiming.frameNumber` 精确匹配，缺 key 或历史已淘汰的帧单独计数，不猜归属。最多 32 页、8 场景、128 条标签边界，每线程固定 1024 桶直方图。均值/最差精确，P90/P99 是直方图上界，误差不超过 6.25% 或 1µs，定义也保存在 JSON。回调不写文件、不编码 JSON、不发 UI 通知。

导出时才拍快照，JSON 编码交给 `compute`，Android 文件写入在工作线程。release 引擎约每秒批量交付帧，因此导出前等待 1.2 秒排空尾批次；设置页帧不会混入场景。后台暂停收集，返回恢复，后台期间未交付的尾批次可能缺失，报告明确这一限制。

生产版以 flavor 常量排除初始化、observer、设置入口和 VM 扩展；Android 性能 Activity/Provider 仅存在 internal 源集。内测 release 没有 profile VM 扩展；仅 internal profile 提供本机 VM 采集接口。尚未对 iOS 分享通道作实现或真机验收，本轮交付 Android。

## 模拟器与工具

官方文档通常建议真机 profile。本机 Flutter 3.44.7 的 Android x64 `supportsRuntimeMode` 实际允许 profile，已通过 `flutter run --profile --no-pub --flavor internal` 构建、安装并连接 DevTools 2.57.0。测试使用独立 AVD 数据目录，不清理已有模拟器或其他项目数据。所有模拟器数值只作环境内相对比较，不能代表开哥手机的绝对性能。

首次环境会话中断前已保存动作库/筛选/详情的帧数据和筛选 Timeline，保留为原始记录，不把中断后未导出的内存统计补写出来。新会话不能拼成一个连续采样。DevTools Performance 与 Timeline Events 已实际连接查看；引擎日志及 DevTools 确认该模拟器使用 Impeller OpenGLES。随后开哥提醒本机模拟器可能占满内存、卡死，已关闭本轮独立 `emulator-5582`，保留其数据目录且不再启动。Rebuild、关闭 Impeller 的 A/B 和其余场景暂停模拟器采集，改等手机报告或可选无线真机。没有声称所有七场景已测。

可选无线实测：手机与本机同 Wi-Fi，在 Android 开发者选项开启「无线调试」，使用手机显示的配对地址执行 `adb pair <地址:配对端口>` 并在本机输入临时码，再用连接地址执行 `adb connect <地址:调试端口>`。确认 `adb devices` 后运行 internal profile 并连接 DevTools Performance；不要把配对码写进报告或源码。此步骤不是安装基线包的前提。

对两份手机 JSON 使用标准库工具：

```powershell
python tools/performance/compare_reports.py before.json after.json -o comparison.md
```

工具逐场景给出双线程指标、样本数、超预算占比与相对变化；缺场景不补零，设备/条件不一致、后端未确认或采集中条件变化会标记不能直接归因。工具不会自动代替开哥验收。

## 交付证据

[已保存原始帧报告](reports/performance-emulator-baseline-incomplete-2026-10-23.json)：internal profile / Android 15 API 35 x64 模拟器 / 约 60 Hz / 浅色 / 星尘开启 / 玻璃 standard。共 1,124 帧，未归属 0，本轮条件变更 0；以下三个场景合计 1,119 帧。不是手机绝对性能。采样时源码为 `c350680` 加记录器工作区变更，未包含后续设置页枚举保护修复；该保护只影响隐藏场景进入设置，不影响已采场景实现。

| 场景 | 帧数 | UI 平均 / P90 / P99 / 最差 ms | UI 超预算帧 | Raster 平均 / P90 / P99 / 最差 ms | Raster 超预算帧 | 联合超预算帧 | 修复后 |
| --- | ---: | --- | ---: | --- | ---: | ---: | --- |
| 动作库快速滑动 | 556 | 0.924 / 1.663 / 3.199 / 39.577 | 1 | 14.273 / 17.407 / 22.527 / 26.225 | 112 | 113 | 待手机基线后决定修复 |
| 筛选切换 | 323 | 1.254 / 1.727 / 6.399 / 9.728 | 0 | 5.030 / 11.263 / 19.455 / 44.891 | 12 | 12 | 待测 |
| 动作详情进出 | 240 | 0.887 / 1.215 / 3.583 / 4.474 | 0 | 4.438 / 8.191 / 17.608 / 17.608 | 6 | 6 | 待测 |
| 长聊天滑动 | 未采集 | — | — | — | — | — | 待测 |
| 计划卡展开 | 内存样本未导出，不能复用 | — | — | — | — | — | 待测 |
| 训练切动作 | 未采集 | — | — | — | — | — | 待测 |
| 下载/校验中滑动 | 未采集 | — | — | — | — | — | 待测 |

动作库路径为 28 次上下交替 fling（240ms 的输入手势），筛选为 18 次“全部/力量/核心”切换，详情为 5 次首个动作进出（每次停留约 1.6 秒）。帧标签窗口包含手势之间的停顿及首尾命令耗时；详情来源为首个内置动作，非下载/解码压力测试。筛选 VM Timeline 保存在 `.buildlog/performance-filter-timeline.json`，32,575 个事件，约 7.66MB，含 UI/Raster 线程；不将完整 trace 或模拟器临时文件提交到 Git。不能用该组单次采样推断图像、阴影或 SDK 就是根因。

| 项目 | 本轮最终核验 |
| --- | --- |
| 运行源码 | `4319e1e345317b9e9cc47b435ab210a181a0ef12`；后续文档提交不冒充重新打包 |
| APK | `.buildlog/install/SmartFit-0.1.0+16-performance-baseline-internal-arm64-v8a-release.apk` |
| 身份 | `com.ugk.smartfit.internal` / versionName `0.1.0` / versionCode `2016` / arm64-v8a / release / 非 debuggable |
| 字节数 / SHA-256 | 49,515,967B（49.52MB）；`942eed98ca4e6860f69326107568ea6fc71f099eba56fc45e12022e5e42502ac` |
| 签名 | 既有开发签名配置，APK v2 校验通过 |
| Dart 验证 | 全量 334 项通过；随后仅补导出时读取实际聊天条数，导出模块 18 项补检通过；最终 analyze 0 issue |
| Python | 对比工具 17 项、存储 JNI 工具 3 项通过；测试输入不当作实测数据 |
| 发布门禁 | internal release 三 ABI 最终 DEX 存储 JNI 检查通过；最终 arm64 包包含记录器 schema/通道/文件名前缀和 internal Provider，且不包含 profile VM 扩展 |
| 生产版隔离 | 另构建 arm64 production release，仅用于核验：上述三个 Dart marker、native 性能通道和 Provider 均不存在，profile VM 扩展不存在；不交付此无 AI 构建凭据的核验包 |
| 依赖与 SDK | `pubspec.lock` 与 +15 保存节点字节一致，SDK 引用目录 Git 状态干净，无 SDK 修改 |
| 真机与系统分享 | 尚无真机帧数据；UI/channel 合同与 native 编译已验，实际 Android 分享面板、接收方取 JSON 和手机性能待开哥验证 |
| 合并状态 | 本地分支保存，未合 main、未推送；卡顿修复与修复后对比尚未开始 |

机器可读包身份和核验项见[交付记录](reports/performance-baseline-delivery-2026-10-23.json)。没有修复后包之前，不填写“优化后”数字或性能提升百分比。DevTools 自动生成的 `devtools_options.yaml` 保留为未跟踪文件，未纳入本轮提交；本轮没有清理模拟器目录或已有改动。

参考：[FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)、[addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)、[Flutter 构建模式](https://docs.flutter.dev/testing/build-modes)。
