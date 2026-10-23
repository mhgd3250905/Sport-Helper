# 计划会话默认材质观感

本组截图从正常 `SmartFitApp` 入口渲染真实 `ChatHomePage`、`PlanCard`、`SuggestionStrip` 和 `ChatInputBar`，没有在入口注入 `SfFixedGlassScope`，也没有设置实验策略。含计划卡的会话只将建议条改为静态仿玻璃，输入框保留原有真玻璃；滚动计划卡继续使用上一轮的静态材质。纯文字聊天的材质不变。

| 主题 | 修改前：固定控件均为真玻璃 | 修改后：仅建议条静态 |
|---|---|---|
| 浅色 | [baseline](../fixed-glass-experiment/plan-light-baseline.png) | [默认](plan-light-default.png) |
| 深色 | [baseline](../fixed-glass-experiment/plan-dark-baseline.png) | [默认](plan-dark-default.png) |

截图由 Flutter 组件测试生成，**不是手机截图，也不是性能样本**。尺寸为 1170 × 2532 像素，逻辑尺寸 390 × 844，DPR 3；使用内置 Noto Sans SC、相同离线计划与滚动位置、`minimal` 玻璃档位及关闭动画的既有星尘背景。截图没有调整星尘实现。

两个默认截图测试已通过，组件断言确认建议条内部 `BackdropFilter` 和 `GlassContainer` 均为 0、输入框仍为原有真玻璃、滚动计划卡没有背景过滤或捕获源。实际控件矩形见 [浅色布局](plan-light-layout.json)／[深色布局](plan-dark-layout.json)。

视觉检查通过：建议胶囊保持原有大小、位置、文字和高光细边，底色更实；未见文本裁切或拥挤。与此前同主题 baseline 的像素差异仅在建议胶囊区域：浅色 `[48, 2208, 1100, 2316)`，深色 `[48, 2196, 1100, 2316)`，坐标按左、上、右、下排列。计划卡、输入框及其余背景逐像素相同，因此没有布局移动。完整检查与 SHA-256 见 [visual-review.json](visual-review.json)。

采用该默认配置的真机依据是 +19 报告中同机、同场景、暗色条件的 `suggestions_static`：Raster P99 5.119 ms，超预算 0 / 3603 帧。此结论只覆盖该测量条件。浅色截图用于观感审阅，不能据此宣称浅色性能达标。将该方案设为普通会话默认后的新内测包仍需真机回归。

复现（由主代理确认无其他 Flutter 测试／构建占用工作区后串行执行，不启动模拟器）：

```powershell
$env:PUB_CACHE = 'E:/DevCaches/pub'
$env:PUB_HOSTED_URL = 'https://pub.dev'
$env:FLUTTER_ROOT = 'E:/flutter'
$env:SF_MEASURED_GLASS_SCREENSHOTS = '1'
& 'E:/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --flavor internal test/fixed_glass_rendering_test.dart --plain-name 'measured default' --update-goldens
```
