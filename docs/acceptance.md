# 本机验收记录

验收日期：2026-10-19（Asia/Shanghai）。接手基线：`main@6c2c1d3`。

本轮完成本机自动化验证与跟练缺陷修复，检查点标签为 `m3-local-tests`。**Android 设备走查及 release APK 尚未通过，M3 完整验收未完成。** `m3-local-verified` 留待下述设备与构建项目全部通过后再打。

## 环境与验证结果

| 项目 | 本轮结果 |
| --- | --- |
| 本机 | Windows 11 x64 |
| Flutter / Dart | 3.44.7 stable / 3.12.2 |
| Android SDK / Java | SDK 36.0.0 / Android Studio JBR 17.0.11 |
| 依赖解析 | `flutter pub get` 成功；提交的 lock 由本机 SDK 重新生成，使用 pub.dev |
| 初次静态分析与测试 | `flutter analyze` 无问题；原有 18 项测试全部通过 |
| 修复后静态分析与测试 | `flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=1` 全部 31 项通过（本机原始输出在被忽略的 `.buildlog/`） |
| Android 真机 | `adb devices -l` 无设备；未执行真机验收 |
| Android 模拟器 | 使用 API 35 AVD 的只读临时实例，禁用快照写回；启动失败，可用提交内存约 903 MB，实例需要 4096 MB |
| Release APK | `flutter build apk --release` 失败；Gradle JVM 原生内存分配失败。将单次构建堆限制降至 1024 MB、768 MB 并限制工作线程后仍失败，最后报 `Could not reserve enough space for object heap` |
| Android licenses | `flutter doctor -v` 提示部分 license 未接受；本轮失败发生在 Gradle JVM 启动阶段，尚未完成后续工具链验证 |
| Release 签名 | 仍为 debug 签名，沿用已知 P1 待办 |

构建失败没有产出可交付 APK。没有修改系统分页文件、终止其他应用或接受额外 SDK 协议。原始崩溃日志位于被忽略的 `android/hs_err_pid*.log` 与本机 Gradle daemon 日志目录，不纳入公开仓库。

## 本轮修复与自动化覆盖

- 提前结束：在准备、训练中或动作间休息结束时，保留已经走完的动作数；不再显示全部完成或播放整套完成语音。重复结束不重复写历史。
- 视频暂停：手动暂停及音频中断同步冻结示范；恢复时保留播放器和当前画面。音频中断解除后等待用户手动恢复。
- 暂停时的「不舒服 → 跳过」保留暂停状态，跳过最后一项仍会写入一次历史；提前结束后固定结果页时长。
- 语音：使用真实 manifest 与文件检查 13 套默认模板的台词素材；覆盖阶段切换、长时间后台后的过期提示丢弃、跳过/返回、队列抢占与取消、仅保留提示音及提前结束。

Widget 测试使用替代音频输出，不能证明 Android 解码、扬声器实听、WebView 首帧和系统音频焦点已通过。

## Android 设备验收清单（全部待执行）

在 Android 真机开启 USB 调试并授权本机，确认 `flutter devices` 列出该设备。先释放足够的系统可用提交内存，再构建和安装；模拟器需要另外预留其 RAM。不要把模拟器结果填写为真机结果。

| 步骤 | 操作与通过标准 | 状态 |
| --- | --- | --- |
| 安全确认 | 全部选「否」并同意后可生成；任一选「是」时仍可浏览但不能生成 | 待验 |
| 场景生成 | 输入「办公室 10 分钟放松肩颈」，生成工位放松计划，无地面动作；检查剂量与预计时间 | 待验 |
| 器械计划 | 选择哑铃全身力量，核对器械、分组、组数及次数 | 待验 |
| 视频 | 计划预览、跟练及动作库中，办公室、徒手和哑铃动作均从封面切入实际动态画面，无持续黑屏或解码错误 | 待验 |
| 训练时序 | 从准备进入训练；至少完整走过一次计次、多组休息、左右换侧及动作切换；视频镜像和右/左提示一致 | 待验 |
| 语音 | 实听准备、开始、次数、倒计时、休息、换侧、完成；与屏幕阶段对应，跳过/返回后无旧台词串播 | 待验 |
| 暂停与中断 | 手动暂停时计时与视频冻结；恢复继续。模拟来电/拔耳机，中断结束保持暂停，手动恢复才继续 | 待验 |
| 疼痛与提前结束 | 暂停后打开「不舒服」，跳过仍暂停；提前结束显示「今天先到这里」，历史数量小于总数，无整套完成播报 | 待验 |
| 后台与长间隔 | 切后台再返回，无积压旧语音；阶段符合会话有效时间规则；来电中断时间不计入训练 | 待验 |
| 完成与存储 | 自然完成只写一条历史；停留结果页时长不增长；重启保留安全确认、最近计划和历史 | 待验 |
| 离线与署名 | 飞行模式下冷启动、生成、视频和语音可用；「关于」页保留 Snow CC BY 4.0 署名 | 待验 |
| Release 安装 | release APK 构建成功，安装后重复主流程，记录机型、Android/WebView 版本、APK SHA-256 和签名类型 | 待验 |

## 复验命令

```powershell
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter devices
flutter run -d <device-id>
flutter build apk --release
Get-FileHash build/app/outputs/flutter-apk/app-release.apk -Algorithm SHA256
```

将设备结果和构建结果更新到本文件，相关问题修复并复验后，再提交完整里程碑并标记 `m3-local-verified`。APK、keystore、密钥及 `local.properties` 保持在版本管理之外。
