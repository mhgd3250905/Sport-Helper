# +49 训练页关闭流畅度修复（2026-10-30，已验收）

开哥真机反馈：+49 的标准滑动方案整体效果不错，但点左上角关闭、返回来源页仍不流畅。本轮保留已确认的视觉方案，只修复真机证实的 App 诊断日志热路径；不把旧包测试通过或已有截图当作本次修复完成。

分支继续为 `codex/trainer-transition`，版本保持 `0.1.0+49`，internal arm64 Android versionCode 为 `2049`。SDK 三包及 coach override 保持 `66dd98a549c1ff5fedecb626a7c88583090a1440`。不改 SDK、路由、主动画或业务保存，不合并、不推送 main、不打 tag，`release/1.0` 不动。

## 基线与设备绑定

| 项目 | 实际基线 |
|---|---|
| App 打包源码 | `ca246228922dd3a2371180657609cb733537e69a` |
| 已有文档收束提交 | `32d87c4d627cfae3c06fc7cf677f0d6871ca4067`，不替代打包源码 |
| 真机安装的 profile APK SHA-256 | `dbc13879db082cf67176c894be6934e0442a41f837f7deb721bd8c5e35ae44c6` |
| 实际 Android 身份 | `com.ugk.smartfit.internal / versionName 0.1.0 / versionCode 2049` |
| 设备系统与型号 | Android 16，`2602BRT18C` |
| 渲染后端 | Impeller / Vulkan，已有真机记录确认 |
| 系统动画 | window、transition、animator 三项均为 1× |
| 原始屏幕分辨率 | 1280×2772；采集未降低分辨率或修改动画设置 |
| 数据边界 | 基线采集未清除 App 数据；本仓库不保存手机原始健康数据、设备序列号或私有 VM 连接地址 |

此前固定源码的 **843/843、analyze 0、同签名/16KB/JNI** 等结果仍属于[原 +49 标准滑动交付](trainer-transition-plus49-slide-2026-10-30.md)及其[台账](reports/trainer-transition-plus49-slide.json)，不代表本轮新日志实现已通过最终验证。

## 有效证据与时间窗口

原始文件仅保留在本机仓库外目录：

`E:/AII-3D/3D-Sport-AI/deliveries/trainer-transition-plus49-close-device-20261030/`

本仓库只记录必要摘要与该路径，不入库全量 trace、CPU 栈原件、原始手机截图、会话内容或私有 VM 地址。外部可复核文件包括 `entry-audit-native-report.md/json`、`entry-audit-cpu-report.md/json` 及对应重算脚本。

| 采集 | 有效范围与限制 |
|---|---|
| r2 | Native trace 有效。用 `clock_snapshot` 的 BOOTTIME−MONOTONIC 约 `44732234095008ns` 映射，退出相对 trace 起点为 1719.704779–2007.260779ms，跨度287.556ms。VM 使用 Ring 导致前段事件丢失，不能凭“没有早期 Dart span”排除同步工作。 |
| r3 | 目标误落在图文预览，未复现训练退出；recent 仍为旧 r2 行且在该轮采集窗口之外，CPU profiler 也未启用。本轮不用于训练退出结论或前后对比。 |
| r4 | 有效训练退出，Endless timeline 保留了前段，真实 UI 消息和最终销毁 scope 可用；CPU sampling unavailable，不能据此给函数级 CPU 比例。 |
| r5 | 有效训练退出，Endless timeline 与 CPU sampling 均可用。`sourceEntry=guide` 表示训练从图文页进入，不是 r3 的“只播放图文预览”。 |

r2 的实际调度：退出窗口内 Android main/platform Running 197.477ms，最长连续执行32.945ms，Runnable 等待仅1.302ms；raster Running64.091ms，最长连续执行12.804ms。前198.779ms，main 累计 Running179.292ms，raster 多数时间睡眠。主线程回调出现66.823/61.077ms间隔，raster 提交出现67.930/52.899ms间隔，支持“上游 UI 事件循环被同步工作占用”，不支持把首要问题仅归为退出末帧解冻。调度 Running 不等于 Flutter 一帧的 build，回调/提交间隔也不等于完整的硬件 vsync 列表。

## CPU 归因：整份日志反复导出

r5 以 `72562763581 <= sample.timestamp <= 72563048885` 严格过滤，退出285.304ms内有 **158 个有效、互异时间戳 CPU 样本**。边界前最近样本为 start−212us，后最近样本为 end+367us；不能为凑159条而扩展退出窗口。函数索引映射来自采样函数表的 owner、resolvedUrl 与 location，窗口计数重新计算，不使用整份 profile 的 inclusiveTicks。

| 函数/路径 | 去重后的样本数 | 占严格窗口样本 |
|---|---:|---:|
| `RuntimeLog.exportJson`（index8351） | 122 | 77.22% |
| `DeveloperLogSanitizer.sanitize`（index7530） | 107 | 67.72% |
| SharedPreferences 三层 `setString` 并集 | 9 | 5.70% |
| `AppStore._encodeState` | 3 | 1.90% |

107个 sanitizer 样本全部属于122个 exportJson 样本。三层 `setString` 各命中同一组9个样本，原始函数命中数之和27不能视为27个独立样本；与 exportJson 的并集是131/158（82.91%）。**inclusive 计数不相加，采样占比不是函数独占耗时，也不能把122个样本写成精确122ms。**

导出工作出现三个采样簇：退出+0.874–49.558ms 的44条、+66.991–110.612ms 的39条、+130.585–174.280ms 的39条。后两簇跨度约44ms；这不是三次调用的精确计数，也不是每次函数开始/结束的秒表。

第一簇的真实调用链为：

```text
_confirmClose → _endEarly → VoiceQueue.cancelAll
→ JustAudioVoiceOutput.stopSpeech → _record
→ RuntimeLog.record → flush → exportJson
→ _snapshot → DeveloperLogSanitizer.sanitize / _clean / _redact
→ String.replaceAll / RegExp
```

后两簇由 `_RawReceivePort`、stream/Future 完成路径恢复到 `flush` 异步闭包，再次导出整份日志。基线 `while (_savedRevision != _revision)` 在等待写入期间积累新 revision 后继续循环；`await storage.write(..., exportJson())` 的 `exportJson()` 实参仍在 UI isolate 同步执行。异步写盘并未让前置全量脱敏与编码异步化。

因此首要根因位于 App RuntimeLog，不是 SDK 转场时长或卡片编排。AppStore 仅3个样本，当前没有证据支持扩大修改业务保存。

## scope 实测与退出后的销毁

| 采集 | scope | 退出后开始 | 实测 elapsed duration |
|---|---|---:|---:|
| r4 | `DartIsolate::HandleMessage` | +71.542ms | 44.737ms |
| r4 | `DartIsolate::HandleMessage` | +134.762ms | 46.145ms |
| r4 | `Animator::BeginFrame` | +284.724ms | 66.096ms |
| r4 | 上述帧内 `FINALIZE TREE` | +301.566ms | 49.058ms |
| r5 | `DartIsolate::HandleMessage` | +66.673ms | 44.569ms |
| r5 | `DartIsolate::HandleMessage` | +129.495ms | 45.024ms |
| r5 | `Animator::BeginFrame` | +285.174ms | 68.596ms |
| r5 | 上述帧内 `FINALIZE TREE` | +302.198ms | 51.418ms |

这是 VM scope 的真实持续时间，**不是 exportJson 函数独占毫秒**；嵌套的 FINALIZE 与外层 BeginFrame 也不能相加。r4、r5 是不同轮次，不拼成一条虚构时间线。

r5 退出后100ms内另有65条样本，其中42条包含exportJson。+303.106ms 的原始栈出现 `_InactiveElements._unmount → StatefulElement.unmount → _ExerciseVideoState.dispose → _record → RuntimeLog.record → flush → exportJson → sanitize`，表明组件销毁也会被整份日志处理拖住。

视频释放必须另行归位：r2 packed_alpha 的53.649ms原生调用在退出结束约77.4ms后才开始；r4的69.685ms调用在退出结束约75.3ms后开始。两者可影响返回后的响应，但**均不属于退出280ms中段，不作为滑出卡顿的根因**。

仅看 build/raster 阈值会漏诊：r5前三帧 build 分别约3.651/1.796/0.351ms，pipeline totalSpan却为63.143/51.441/64.192ms。验收须同时看事件循环消息、callback/提交间隔、totalSpan和录屏，不能只用“build/raster均未超16ms”宣称退出流畅。

## 本轮实现边界

修复候选只改 App 诊断日志及初始化接线：

1. RuntimeLog 将已冻结的事件列表快照及脱敏规则交给 `compute`，在 worker isolate 完成整份脱敏和JSON编码；传参不捕获 storage。`protectSecret` 在编码期间改变 epoch 时，旧 worker 结果丢弃重算。
2. 自动 record 合并到异步 flush，等待训练转场 Activity idle；显式 flush 仍可等待实际写入。保留串行写、revision、错误可重试与禁用状态无I/O，不用自动失败重试形成自循环。
3. internal 原生日志改用 Application Support 下独立的异步文件和原子替换。旧 SharedPreferences 只作读取回落，经过 RuntimeLog 脱敏后才写入新文件；不直接搬运旧原文，也不删除旧 preferences。非IO平台保留固定key回落。
4. `main.dart` 仅接入新 storage factory，性能比较基线元数据对齐 `ca24622`。不改 AppStore、SDK源码、训练路由、计时、语音业务、记录保存或 finished 插入流程；进入300ms/退出280ms、曲线、完整控件和防闪烁门禁保持原设计。

旧完整交付、APK及历史测试回执不覆盖。新修复继续保持三包66dd、+49/2049和候选未合并状态。

## 最终验证与验收

修复/打包源码：`88379139dafe0a07f03635da8a95cc93f0704068`。后续仅README/docs台账收束，最终HEAD由交付目录`final-closeout.json`记录。SDK三包及coach override仍为`66dd98a549c1ff5fedecb626a7c88583090a1440`；整份pubspec.lock与旧+49源码ca24622一致。

全量 **861/861通过，0失败/跳过**；Flutter 3.44.7，`flutter analyze --no-pub` 0问题，严格离线锁通过。新增18项日志异步/文件回归；首次fixture中的Flutter expect异步Zone误报改用expectSync，断言保留，最终已随全量通过。包装辅助36/36单列，不混入Flutter数量。

| arm64 internal包 | 大小 | SHA-256 |
|---|---|---|
| release | 42,655,242B / 42.655MB | `92948f44021b7aa019ac5ca76de55e6d993cd60cd7d808570d4767a2019c9e94` |
| profile（已覆盖安装） | 53,609,054B / 53.609MB | `2702f0949144fe8d3dc868af3c880e54983b8858b22b55c386ad0003efb17caa` |

APK路径分别为`E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-close-fix\SmartFit-trainer-close-fix-0.1.0+49-8837913-internal-arm64-v8a-release.apk`与`E:\AII-3D\3D-Sport-AI\deliveries\trainer-transition-plus49-close-fix\SmartFit-trainer-close-fix-0.1.0+49-8837913-internal-arm64-v8a-profile.apk`。两包同原签名，ZIP/ELF16KB、JNI、无MP4门禁通过；release小于45MB，原Noto与必要静态/语音资源保留。包门禁是软件检查；手机安装和实测另见`device-validation.json`。

覆盖安装未卸载或清数据：安装前后保存计划、46条会话记录、聊天及Coach会话的计数/摘要哈希一致。随后五次有意提前结束产生正常测试记录；不会把这些新记录误判成安装前后的数据变化。新日志文件已观察到391,664B，旧preferences保留。

### 同一手机实测

新包默认profile运行，未开启录屏、VM Timeline或CPU采样，浅色图文入口进出五次；五份原始JSON均绑定本轮源码，完整记录在交付目录`device-validation.json`及仓库外设备证据目录`fixed-guide-pure/`。

| 指标 | 原包观察 | 修复后五次 |
|---|---|---|
| 每次退出帧数 | 15–16 | **34、34、34、34、34** |
| 大于25ms的帧回调间隔 | 每次约3段 | **0** |
| 最大退出回调间隔 | 原正常chat/saved-plan约66.4ms；Guide trace最高74.744ms | **16.600ms** |
| 退出build P90 | 以各轮原JSON为准 | 0.554–0.749ms |
| 退出raster P90 | 以各轮原JSON为准 | 4.853–6.142ms |

首次退出单列：34帧，build最大17.826ms、raster最大8.252ms。第2–5次退出也均34帧；五轮中UI最大21.073ms、raster最大14.254ms，每次仍有1帧的build超过16ms，不能声称所有帧均低于16ms。原明显的60ms级回调空洞已不再出现。

旧Guide定位轮开启过trace/采样，旧无观察器记录来自chat/saved-plan；上述是定位及同机修复证据，不冒称全部入口/主题的严格统计基准或硬件present-FPS。五轮after只覆盖浅色guide，其余入口语义与浅深布局由全量用例回归。

用户随后要求交还手机，自动点击已停止，未再操作手机或补录after录屏。开哥亲自操作后明确回复 **“验收通过”**，已登记为本次+49关闭修复真机验收通过；具体手动步骤未另行枚举，不虚构覆盖清单。

候选保留`codex/trainer-transition`，本轮“不合并、不推送main、不打tag”的约束继续遵守；main、release/1.0、SDK仓库不动。验收结论不扩展为额外的合并/推送指令。
