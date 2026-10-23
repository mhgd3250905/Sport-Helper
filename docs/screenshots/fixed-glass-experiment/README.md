# 固定玻璃拆分实验候选观感

这组图片由真实 Flutter `ChatHomePage`、`PlanCard`、`SuggestionStrip` 和 `ChatInputBar` 在组件测试中渲染，供浅色／深色观感审阅。它们不是手机截图，也不提供真机 Raster 数据；最终默认方案须等开哥在同一真机流程下采样后确定。

| 候选 | 浅色 | 深色 |
|---|---|---|
| 保留现状（baseline） | [查看](plan-light-baseline.png) | [查看](plan-dark-baseline.png) |
| 只去饱和度过滤 | [查看](plan-light-no-saturation.png) | [查看](plan-dark-no-saturation.png) |
| 模糊减半 | [查看](plan-light-half-blur.png) | [查看](plan-dark-half-blur.png) |
| 固定输入框及建议条全静态 | [查看](plan-light-all-static.png) | [查看](plan-dark-all-static.png) |

渲染尺寸 1170 × 2532 像素，逻辑尺寸 390 × 844，DPR 3。使用 App 内置 Noto Sans SC、相同离线计划、同一滚动位置及静止的既有星尘背景。玻璃锁定为 `minimal`，与前两轮手机对照使用的档位一致。滚动计划卡在全部候选中都保持静态；没有背景捕获源。输入框、建议条及计划卡矩形在切换候选时完全不变。像素差异都局限于底部固定控件区域。

深色 baseline 与去饱和度图片像素相同，是当前控件后方背景接近中性的结果。测试另外确认实际材质 `saturation` 为 1，并且每个 minimal 玻璃控件的 `BackdropFilter` 数量由 2 减为 1；不能据截图相同认定该开关无效。

浅色原模糊 1.5，减半后 0.75；深色原模糊 1.2，减半后 0.6。去饱和度保留原模糊。静态候选没有模糊／饱和度过滤。每个固定控件均有独立 `RepaintBoundary` 及只覆盖自身形状的 `ClipPath`。

本次手机测试场景实际承载于聊天页：固定玻璃只有输入框及建议条的各个胶囊，没有独立顶栏或底栏玻璃。`PlanPage` 详情的顶栏和底部开始按钮原本也不使用玻璃，因此顶栏／底栏拆分应显示“不适用”，不能把无变化的空开关作为归因证据。

复现命令（PowerShell，串行运行，不启动模拟器）：

```powershell
$env:PUB_CACHE = 'E:/DevCaches/pub'
$env:PUB_HOSTED_URL = 'https://pub.dev'
$env:FLUTTER_ROOT = 'E:/flutter'
$env:SF_FIXED_GLASS_SCREENSHOTS = '1'
& 'E:/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --flavor internal test/fixed_glass_rendering_test.dart --update-goldens
```

运行前应确认没有其他 Flutter 测试或构建正在使用该工作区。生成信息及 SHA-256 见 [visual-review.json](visual-review.json)。
