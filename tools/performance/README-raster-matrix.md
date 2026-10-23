# Raster 同场景对照工具

读取新版内测包导出的 schema 2 JSON，逐格输出 4 档 × 聊天/计划卡 8 行稳态 Raster 表，并分别列出 case 前 2 秒、case 与首次进页窗口交集、全局首次进页前 2 秒和最差帧。

```powershell
python tools/performance/raster_matrix.py 'F:/test-logs/SmartFit-performance-NEW.json' -o 'F:/test-logs/SmartFit-raster-matrix.md'
python -m unittest discover -s tools/performance -p test_raster_matrix.py -v
```

多份输入只接受同一 `startedAt`、同一具体 `appSource`、同一设备/App/SDK/renderer/主题来源的互补格。重复格直接报错，不能用后一个文件静默覆盖。旧 schema 1 基线无法补成八格；缺格、未完成、跨度不足 30 秒、条件混合、未验证 renderer 或数据无效均显示 `—`。

每个差值只关闭一个开关，且保持场景、测试数据和消息数一致；同时核对每帧实际 renderer/backend、刷新率、主题、窗口尺寸、像素比和文字缩放。两边玻璃都开启的星尘对照，还要求实际玻璃 quality/phase/frost 一致。未记录实际尺寸的格需重新采样。全局首次进页窗口不绑定某个档位，不能用来做四档归因。

工具不合并百分位，不推断根因或着色器编译。P90/P99 是记录器导出的直方图估计；超预算比例不是屏幕实际掉帧率。输出文件和 stdout 均使用 LF。

## Android renderer 解析器验证

这 16 条检查只使用合成引擎行，直接编译应用实际的 `InternalRendererEvidenceParser`，不需要 Android 设备、模拟器、Gradle 构建或新增依赖。

以下命令在项目根目录运行，使用本机已有 Android Studio JBR 和 Gradle 自带的 Kotlin 编译器；输出只写入独立临时目录：

```powershell
$rendererCompilerLib = 'E:/DevCaches/gradle/wrapper/dists/gradle-9.3.1-all/9ot9r568e8zfvvd4mn8rbu1j0/gradle-9.3.1/lib'
$rendererCheckDirectory = 'E:/DevCaches/tmp/smartfit-performance-native'
New-Item -ItemType Directory -Force -Path $rendererCheckDirectory | Out-Null
& 'E:/Android/Android Studio/jbr/bin/java.exe' -Xmx256m -cp "$rendererCompilerLib/*" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath "$rendererCompilerLib/kotlin-stdlib-2.2.21.jar" -d "$rendererCheckDirectory/renderer-evidence-check.jar" android/app/src/internal/kotlin/com/ugk/smartfit/InternalRendererEvidence.kt tools/performance/test_renderer_evidence.kt
if ($LASTEXITCODE -ne 0) { throw 'Renderer test compilation failed' }
& 'E:/Android/Android Studio/jbr/bin/java.exe' -Xmx64m -cp "$rendererCheckDirectory/renderer-evidence-check.jar;$rendererCompilerLib/kotlin-stdlib-2.2.21.jar" com.ugk.smartfit.Test_renderer_evidenceKt
if ($LASTEXITCODE -ne 0) { throw 'Renderer parser checks failed' }
```

实际 renderer 证据限定为自身 PID、当前 Activity 创建之后、`flutter` 标签及固定引擎源路径的精确启动行，后台限量读取，不导出日志原文。Vulkan 探测后只有捕到最终 OpenGLES 行才确认回退结果。证据不足保持 `unverified`，不能拿默认配置或缺少 Impeller 日志推断 Skia。

识别文本已核对本机 Flutter 3.44.7 的 arm64 release 引擎及同版本官方源码：[Impeller OpenGLES](https://github.com/flutter/flutter/blob/69c8c61792f04cc809dfef0c910414fb9afc06cd/engine/src/flutter/shell/platform/android/android_context_gl_impeller.cc)、[Impeller Vulkan](https://github.com/flutter/flutter/blob/69c8c61792f04cc809dfef0c910414fb9afc06cd/engine/src/flutter/shell/platform/android/android_context_vk_impeller.cc)、[动态回退](https://github.com/flutter/flutter/blob/69c8c61792f04cc809dfef0c910414fb9afc06cd/engine/src/flutter/shell/platform/android/android_context_dynamic_impeller.cc)。该版 [Skia 初始化](https://github.com/flutter/flutter/blob/69c8c61792f04cc809dfef0c910414fb9afc06cd/engine/src/flutter/shell/platform/android/android_context_gl_skia.cc)没有同等成功启动声明，因此目前 Skia 路径会保留为未验证。
