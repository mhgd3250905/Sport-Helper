# SmartFit 图标 A/B 与品牌色

本分支 `feat/icon-brand-variants` 从当前 `main` 的 `94d78cee9550dfbf470c7140e3729260d9b79f2d` 建立，位于独立工作区 `E:/AII-3D/3D-Sport-AI/Sport-Helper-icon-brand`。没有切换或修改流畅度分支，也没有合入它的业务、记录器或发布修复。合入顺序仍为流畅度先合；本分支等开哥确认后，再基于届时 main rebase、复验和合入，不提前推送。

## 源图和选择

源图来自开哥指定的 [Drive 文件夹](https://drive.google.com/drive/folders/1VVi2cGjoaW3luCksQFunMG6OKRZ0Z45U)。仅取两个指定文件，没有使用文件夹里另一个 `smartfit-icon-v4.png`。

| 候选 | 原始文件 | 源图 SHA-256 |
| --- | --- | --- |
| A 全身 | `assets/brand/source/smartfit-icon-v3.png` | `5489859ef71dd279453f46e15d0d1632eabf7f5cbdc7e677d591c34f14f8637c` |
| B 半身 | `assets/brand/source/smartfit-icon-v4-crop.png` | `a89d37b544942fe852b96e38b0faaaf66ac0d926d70037c227d0a102236d65f8` |

两图均为 1024×1024、不透明 RGB、满版无圆角。B 的腿已被用户提供的原图边界裁切，生成过程不增加裁切、不抠图或重绘。Android 自适应图标使用独立薄荷到青绿渐变背景，整图前景 46dp，含四角的对角线 65.05dp 完整落在 66dp 安全圆内；预览同时核对圆形和圆角遮罩。为了保留整张图，人物周围有安全留白。iOS 每个 iPhone/iPad/1024 marketing 槽位均已生成两套候选。

只给 Android internal sourceSet 加入显式选择的候选资源。构建参数为 `--dart-define=SMARTFIT_ICON_VARIANT=A|B`，也支持 Gradle property `smartfitIconVariant`；两参数冲突直接失败。不传参数则沿用原图标。21 个原生产图标文件与默认 iOS AppIcon 配置保持原样。iOS 当前没有独立 internal scheme，A/B xcconfig 只提供显式图标选择，不改 bundle ID、签名或既有 scheme；Windows 上没有执行 iOS 构建或签名验收。

生成和复验命令见 [图标构建说明](../tools/branding/README.md)，尺寸和每个生成文件的 hash 见 [资源清单](../tools/branding/icon-assets.json)。

## 颜色范围与对比度

只修改主题颜色 token 和其颜色消费映射。未修改玻璃/星尘/模糊/阴影、动画、布局、列表或视频渲染逻辑。SDK、pubspec、lock 和 main.dart 都不改。页面没有散落的旧 jade 主色，旧主色集中在 token；原玻璃背景池等独立效果按边界保留。

| 用途 | 浅色 | 深色 |
| --- | --- | --- |
| 主色：按钮、选中、进度 | `#0F7976` | `#7AD4D5` |
| 主色小文字 | `#0A6C69` | `#7AD4D5` |
| 强调：开始训练、完成 | `#E8705F` | `#F38F7F` |
| 强调按钮文字/图标 | `#30120E` | `#30120E` |
| 强调小文字 | `#A83B2E` | `#F38F7F` |
| 装饰源色 | 薄荷 `#BDF7CF`、青绿 `#7AD4D5` | 同色相 |

`#138A86` 在现有浅色页面仅约 3.84:1，因此进一步加深。最终主色在浅页 `#F4F5F3` 上 4.78:1、浅层 `#EEF0EE` 上 4.56:1；白色按钮文字 5.23:1。浅珊瑚按钮用深色前景，常态 5.67:1、按下变深后 4.68:1。深色主色对 surfaceHigh 9.26:1。AI 气泡只换青绿填色，用户气泡只换薄荷填色；正文至少 7:1、元数据至少 4.5:1。安全 caution/danger 与媒体舞台保持原值。

## 手机对比与流畅度隔离

先完成当前 +17 流畅度采样并导出 JSON，再覆盖安装 A/B。图标包基于 main，未包含流畅度分支的记录器，不能替代八格采样包，也不用于性能前后对比。它们用相同包名 `com.ugk.smartfit.internal`、相同签名和 versionCode `2017`，便于 A → B → A 比较，也允许回装原 +17；不抬高版本号造成回装必须卸载。

这两包使用 arm64 **profile** 构建。main 的 release 路径缺少流畅度分支已有的 SharedPreferences JNI keep 修复；此分支不混入该修复或改依赖，通过 profile 内测构建保持图标范围。打包脚本不输出 Worker 凭据。合入流畅度后 rebase 时，发布构建与 JNI 门禁再按新的 main 复验。

桌面启动器可能缓存旧图标，覆盖安装后需确认应用信息页和桌面均刷新，再比较人物/机器人是否被遮罩切掉。生产图标等开哥选定 A/B 后另行固定；这轮没有预选生产默认。

## 截图和验证

四张图使用正式 Flutter 组件、固定的内存会话，390×844 @3x，不读写用户聊天。截图是 WidgetTester 渲染：星尘静止，测试环境使用 shader-free `SfGlass.minimal`。它们用于检查颜色、布局和文字，不能声称是真机截图或真机玻璃表现；未启动 Android 模拟器。

| 页面 | 浅色 | 深色 |
| --- | --- | --- |
| 首页 | [查看](screenshots/icon-brand/home-light.png) | [查看](screenshots/icon-brand/home-dark.png) |
| 聊天 | [查看](screenshots/icon-brand/chat-light.png) | [查看](screenshots/icon-brand/chat-dark.png) |

图标遮罩预览：[A/B 圆形及圆角对照](screenshots/icon-brand/icon-mask-preview.png)。全量 Flutter 测试 271 项通过，包含六项颜色对比度合同检查；截图测试 4 项通过；静态分析零问题。图标生成完整性、所有尺寸、safe circle、生产图标保护及额外资源拒绝等 Python 检查共 11 项通过。真机桌面 A/B、实际玻璃上的颜色和 iOS 编译尚待相应环境验收。
