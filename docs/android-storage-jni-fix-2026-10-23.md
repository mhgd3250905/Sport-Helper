# Android 发布包存储 / AI 路由修复（+15）

## 手机日志确认的事实

用户提供的 `SmartFit-runtime-20261023T004906692417Z.json` 来自 Android internal `0.1.0+14`，47 条连续事件覆盖北京时间 08:48:41–08:49:06。文件 SHA-256 为 `d305e5806a047f16aa01602b2446df999f52fc1fb78d73ea2118ae10cd15ce41`，原件未修改；摘要见 [手机日志分析](reports/phone-storage-failure-2026-10-23.json)。

- 启动出现 `app.identity_unavailable / PlatformException`，导出头部 `persistenceFailed=true`。
- `hasKey=true`、`hasDeviceIdentity=false`、动作目录 93 条可用；引擎因 `identity_unavailable` 选择整个本地规则引擎。
- 两轮消息均为 `route=local / offline_engine`，453ms / 465ms 返回；第二轮生成 7 动作的 template 计划。该完整窗口内 **0 次 AI 请求**，不能把它说成 AI 思考很快。
- 5 个非内置视频处于 `waitingForWifi / wifi_required`，是 Wi-Fi 下载政策，与 AI 未发请求无关。日志没有训练开始事件。

手机旧日志没有记录原生错误码或异常正文，因此不能单靠它断言具体 Java 异常名称。以下是对交付 APK 独立检查确认的二进制缺陷。

## APK 中的确定缺陷

固定的 `shared_preferences_android 2.5.0` 使用 Pigeon JNI。其生成代码按固定签名查找 `getAll(String,List,Continuation)`。+14 实际 DEX 把 `kotlin.coroutines.Continuation` 改名成 `md`，方法定义中的参数变成 `Lmd;`，与 JNI 查找的 `Lkotlin/coroutines/Continuation;` 不匹配；Unit、Result 和协程辅助类也被改名或移除。

官方 2.5.2 通过保留这些 Kotlin 类型的 consumer R8 规则修复 Android release 启动 `NoSuchMethodError`：[更新记录](https://pub.dev/packages/shared_preferences_android/changelog)、[固定版本的官方规则](https://github.com/flutter/packages/blob/shared_preferences_android-v2.5.2/packages/shared_preferences/shared_preferences_android/android/consumer-rules.pro)。

直接检查已有 +13 production 与 +14 internal arm64 APK，均失败 36 项。由此确认该打包缺陷早于运行日志功能；以前网页 AI 成功不能证明 Android 发布包可正常读取设备标识。

## 修复与防回归

`android/app/proguard-rules.pro` 原样补入官方六条 Kotlin keep 规则。当前 Flutter release 构建自动读取该文件，不关闭 R8，也不升级 DataStore、切换存储后端、迁移键名或清空用户数据。SDK 和运行依赖版本均未变；只把锁定的测试平台接口 2.4.2 声明为测试直接依赖。

另修正 legacy SharedPreferences 的缓存问题：原插件在平台写入完成前更新缓存；写入失败后，旧代码可能从缓存读到未落盘的 UUID。App 存储读取现在先 `reload()`，平台读失败继续抛出，设备标识仍必须成功持久化才启用 AI。新增真实插件缓存边界测试覆盖异常/false 写入、重试、重启、旧 UUID/其他数据保留，不改成内存标识绕过。

日志增加经过筛选的原生错误码和固定 JNI 失败分类，不记录原始错误消息或路径；同一次存储持续故障只加一条写失败标记。AppStore 恢复失败有独立事件，`app.state_initialized` 不再误称底层存储成功。

发布脚本新增 `verify_android_storage_jni.py` 门禁：读取最终 APK 的 DEX 定义，检查 8 个类、33 个方法签名、3 个字段；仅有字符串或引用不能通过。三个 ABI 全部通过才宣布构建完成；缺失或改名则失败退出。构建时可指定 `-PythonCommand C:/Python314/python.exe`。

## 验证与限制

- Flutter 全量 **298 项通过**，分析 0 issue；严格离线锁文件通过，Python DEX 检查器 3 项测试通过。
- 三个 internal release ABI 的 JNI 检查均通过。已保存 [+13 production 失败报告](reports/storage-jni-plus13-production-negative-2026-10-23.json)、[+14 失败报告](reports/storage-jni-plus14-negative-2026-10-23.json)、[+15 arm64 通过报告](reports/storage-jni-plus15-arm64-2026-10-23.json)。
- 全部 695 段 AAC-LC、5 段提示音、413 份训练媒体的库存和哈希再次通过；[同口径包内占用](reports/apk-storage-fix-internal-size-2026-10-23.json)。
- 创建了工作区内全新的独立 API29/API35 x86_64 AVD，所有 ADB 操作均指定这两个自建模拟器，未连接或操作用户手机、未改已有 AVD。模拟器能启动并安装 APK，但启动完整 App 后宿主模拟器进程退出（两种 release 包均出现，包含禁用 Vulkan 的尝试）；**没有完成模拟器运行验收**，不能据此声称 +15 真机 AI 请求或日志保存已通过。
- 真机覆盖升级后，需用同一问题复测并导出日志，确认 `chat.engine.route=sdk / hasDeviceIdentity=true`、出现 `ai.request.* / ai.turn.end`、`persistenceFailed=false`，并重启后保留记录。20 分钟训练仍待有设备时验收。以上待验不使用此前网页结果替代。

## 交付候选

内测 arm64：`.buildlog/install/SmartFit-0.1.0+15-storage-fix-internal-arm64-v8a-release.apk`。

`com.ugk.smartfit.internal` / `0.1.0` / versionCode **2015**，arm64-only，非 debuggable，v2 签名验证通过，证书与 +14 相同，可覆盖升级。**49,384,327B = 49.38MB**，SHA-256 `6ecdc72d0fb48c8b179e288009cfe8279a50be4bef1391ee7dfdedebf48249fb`。原 +13/+14 文件保留但不再建议安装。没有新建 +15 生产交付包。

候选代码在 `feat/voice-aac-comparison`；仍待开哥验收同意后合并并推送，main 未改变。
