# 滚动计划卡观感对照

这四张是实际 Flutter App / PlanCard 组件的 widget 渲染图，**不是手机或模拟器截图，也不用于帧性能结论**。画布为 1170 × 2532 像素，逻辑尺寸 390 × 844，DPR 3。未启动模拟器。

| 主题 | 修前：列表卡片真玻璃 | 修后：静态仿玻璃 |
| --- | --- | --- |
| 浅色 | [plan-light-before.png](plan-light-before.png) | [plan-light-after.png](plan-light-after.png) |
| 深色 | [plan-dark-before.png](plan-dark-before.png) | [plan-dark-after.png](plan-dark-after.png) |

每对图片来自同一挂载的 `SmartFitApp`，只切换内测 `scrollingGlassEnabled`。内存会话、滚动位置、封面图片、字体、背景色场和静态星尘保持一致。计划卡和单动作卡均使用真实 `PlanCard`。没有读取或改写真实会话，也没有请求 AI。

修前强制 `GlassQuality.minimal`，对应开哥 +17 真机八格测试的实际档位；该路径仍有模糊和饱和度背景过滤。当前 legacy `SfGlassSurface` 整个 class 与 +17 源提交 `7718e619a11250097aa27e629063935922beed0c` 的实现逐字一致（LF 规范化 SHA-256：`dcdaf2714d21d9da3af7dd547fd187951d2e3c40cfa3866a703097d5f47af50d`）。测试验证修前有过滤器和 `GlassBackgroundSource`，修后滚动卡片中二者均不存在。固定输入栏和建议 chips 继续走原玻璃路径。

截图测试同时断言两种材质下两张卡片的位置和尺寸完全相同。首次运行抓到了细描边隐式增加 1.6px 高度的问题；修正后，浅色和深色两项检查均通过。截图里浅色卡面更接近白霜，深色卡面略微提亮；布局、媒体和控件保持一致。

重现命令（项目目录，串行运行；需要已有依赖）：

```powershell
$env:PUB_CACHE='E:/DevCaches/pub'
$env:PUB_HOSTED_URL='https://pub.dev'
$env:TMP='E:/DevCaches/tmp'
$env:TEMP='E:/DevCaches/tmp'
$env:SF_SCROLL_CARD_SCREENSHOTS='1'
& 'E:/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --flavor internal test/scroll_card_visual_review_test.dart --update-goldens
```

平常测试不设置 `SF_SCROLL_CARD_SCREENSHOTS` 时跳过此图片生成入口。字体使用 App 打包的 Noto Sans SC，图标使用 Flutter 的 MaterialIcons。真机观感及 Raster P99 / 稳态超预算目标由新内测包按原流程复测确认。
