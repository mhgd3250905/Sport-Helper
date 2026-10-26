> 本报告为 2026-10-23 的历史 B 交付；开哥 2026-10-24 已要求改为全身稍放大 A2。当前方案与待确认状态见 [A2 报告](icon-fullbody-zoom-2026-10-24.md)，旧 B 选择不再作为合入依据。

# SmartFit 图标 A/B 与品牌色

流畅度改动已按开哥明确同意合入并推送 main `d362084976387b2b2fc331a0da8974dc112c02bf`，远端已复核。独立品牌分支 `feat/icon-brand-variants` 已 rebase 到该 main；本轮候选包源码为 `9773b61c45e3ffd286b789c32a6637eb04cfc09a`。开哥看到 A 的真机图标后明确选择 B 半身版；Android 和 iOS 默认图标已在品牌分支固定为 B。品牌分支尚未合入或推送。

## 候选与生产保护

指定源图来自开哥的 [Drive 文件夹](https://drive.google.com/drive/folders/1VVi2cGjoaW3luCksQFunMG6OKRZ0Z45U)：A 为 `smartfit-icon-v3.png` 全身版，B 为 `smartfit-icon-v4-crop.png` 半身版，均为 1024×1024、不透明、满版无圆角。B 原图已经裁掉下方腿部，生成过程没有追加裁切或重绘。

Android 使用独立薄荷到青绿渐变背景，整图前景缩为 46dp，其 65.05dp 对角线落在 66dp 安全圆内。五种 Android 密度和全部现有 iOS appicon 槽位已生成。圆形/圆角预览见 [遮罩对照](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。79 份候选资源及选定 B 后的 38 份受保护默认资源均通过校验。Android 默认使用 B 的 legacy/round/adaptive 图标，iOS 默认 AppIcon 的全部既有槽位使用 B；生成器仍只生成候选，不隐式覆写生产资源。

`--dart-define=SMARTFIT_ICON_VARIANT=A|B` 只给 internal sourceSet 注入所选资源；省略参数采用已选定的 B 默认图标。Gradle property 也可显式选择，冲突参数直接失败。Windows 未执行 iOS 编译/签名，两个候选 xcconfig 不改既有 scheme、bundle ID 或签名。

## 颜色与范围

本次只改主色、强调色、气泡颜色 token 及颜色用途映射，没有改变主题布局、星尘、列表、动画或 SDK；固定 SDK `f684e02f38e652633c23fa8946a53d02b6aa3ea2`。此为历史配色对照，原呈现细节见[历史证据归档清单](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)，不作为当前扁平候选验收。

| 用途 | 浅色 | 深色 |
| --- | --- | --- |
| 主色 | `#0F7976` | `#7AD4D5` |
| 主色小文字 | `#0A6C69` | `#7AD4D5` |
| 强调/开始训练/完成 | `#E8705F` | `#F38F7F` |
| 强调按钮前景 | `#30120E` | `#30120E` |
| 强调小文字 | `#A83B2E` | `#F38F7F` |
| 装饰源色 | `#BDF7CF` / `#7AD4D5` | 同色相 |

主色进一步加深以满足现有浅色背景的 4.5:1：最弱主色对底色为 4.558:1，珊瑚按钮按下态最弱 4.671:1；气泡正文最弱 12.889:1，次文字最弱 4.527:1。六项品牌对比度测试与独立复算通过。安全 caution/danger 和媒体舞台颜色保持原样。

## 两个覆盖安装包

两包均为 arm64 **release 内测版**，包名 `com.ugk.smartfit.internal`、versionName `0.1.0`、versionCode `2021`，与当前 +21 同签名。可 A → B → A 覆盖安装，无需卸载，保留原 App 数据。沿用 +21 避免回装本轮基线时发生版本降级，源码身份由导出报告中的实际 SHA 区分。

位置：`.buildlog/brand21/install/`。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `SmartFit-0.1.0+21-internal-iconA.apk` | 49,941,255 | `2504c9ba034ef5bcf1f300a18ed77cd68be09721fd3b727bb12c1d6b1548d077` |
| `SmartFit-0.1.0+21-internal-iconB.apk` | 50,003,871 | `593aad38b5d3b97a0038e6fb2eb8403dd2ed8a440c1104a62f174399c2eb70e1` |

两包 v2 签名、非 debuggable、仅 arm64、源码 SHA、SDK lock、最终 DEX/JNI 和逐像素图标校验均通过，另一候选 legacy 图标不存在。ZIP 条目仅 15 个图标 PNG 内容不同，`libapp.so` 与其它条目内容完全一致；两包含最新 main 的 +21 记录器及性能修复。默认 B 固定后另构建无 Worker key 的 production 校验包，验证默认图标、内测代码剔除、JNI 和签名；该包仅用于本机校验，不分发、不安装到手机。

开哥已选择 B。真机按 A → B 覆盖安装及启动均通过，安装 APK hash 与对应交付包一致，当前手机为 B。MIUI 最初缓存 A；回到桌面并重开应用信息页后已显示 B 半身构图，没有清除 App 或桌面数据。A 包保留作参考。默认 B 资源已在分支准备好，品牌分支合入等待单独同意。

## 验证与截图

rebase 后强制 lockfile 的 pub get 通过。全量 Flutter **420 通过 / 13 跳过**；内测材质/默认配置与品牌专项 **23 通过 / 4 跳过**；静态分析零问题；Python 图标完整性及默认 B 保护等 **13 通过**；四张截图测试通过。必要检查完成后未重复无关测试，也未启动模拟器。

截图使用当时源码的正式 Flutter 组件、固定内存会话，390×844 @3x；WidgetTester、星尘静止，用于历史颜色和布局审阅，不是真机截图或性能证据。原始环境参数及原图见[历史证据归档清单](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。独立视觉复核当时未见文字重叠、异常截断、卡片溢出或按钮错位。

| 页面 | 浅色 | 深色 |
| --- | --- | --- |
| 首页 | [查看](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [查看](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |
| 聊天 | [查看](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) | [查看](../../deliveries/flat-release-20261026/retired-evidence/manifest.json) |

卡片与建议条相对旧 +17 预览的表面变化来自已合入 main 的性能修复，品牌分支相对 main 没有改变这些路径。图标/品牌包未重新做性能采样，不把颜色预览作为性能改善证据。

机器可读记录含两包 hash、选中资源、测试和手机安装核验（如已执行）：[交付 JSON](../../deliveries/flat-release-20261026/retired-evidence/manifest.json)。旧 +17/profile 交付已被本轮替代，原包留存，不能用于覆盖当前 +21。

## 回归与源码范围

两份内测 APK 及四张颜色预览来自上述 `9773b61` 源码。此后为开哥选定 B 追加的改动仅涉及默认图标资源、Manifest 的 roundIcon、生产选择记录及资源校验；没有改 lib、SDK 或 lock。Dart 全量与材质回归不重复运行，追加默认 B 资源测试与实际 production 校验包检查。生产校验的确切 source/hash 和剔除证据见交付 JSON。

默认 B 的 production arm64 release 校验已通过：包名 `com.ugk.smartfit`，默认 B 图标逐像素匹配，15 个 Dart / 3 个原生内测标记全部不存在，VM 诊断扩展不存在，静态滚动卡仍保留；JNI、v2 签名、非 debuggable 和源码回执均通过。源码 `216c7b3`，APK SHA-256 `123ca114a6d5c1bb7e8c154ec38b498b47985d58db69f13b30eb2402c531b81e`，49,686,435 字节。无 Worker key，仅本机校验，不分发、不安装到手机。

Windows 新增默认 adaptive XML 已加 LF 属性，并通过独立 checkout-index 副本的哈希校验，避免未来合入检出时换行改变保护哈希。该属性、Gradle 说明注释及交付文档均不改变已构建包的运行行为。SDK lock 的 Git blob 与 main 完全相同，构建前后实际工作树 lock hash 也一致。
