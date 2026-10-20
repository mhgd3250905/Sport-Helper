# 本机验收记录

最新合并检查点（2026-10-20）：PR #3 美学 v2 已合入 `main@a5997ef`，里程碑 `m7-aesthetic-v2`。已复验审核源 `7ef80d7`：静态分析 0 issue，全量 144 项测试及 5 项独立复现/无障碍检查通过，动作包校验 0 errors，Web release 与 Android debug 构建成功。原四项必修与一项动效问题已关闭，93 个动作包版本为 1.1.0，浅色媒体已纳入文件清单及索引。合并提交的文件树与审核源完全一致，记录见 [PR #3 本机审核](pr3-local-review.md)。这次只完成合并、主线同步及文档记录，没有安装 APK 或进行真机验收；下文 `m6-input-focus` 的手机输入验收仅适用于当时已安装版本。

验收日期：2026-10-19（Asia/Shanghai）。接手基线：`main@6c2c1d3`。

最新输入检查点 `m6-input-focus`：小米 Android 16 真机已安装并启动，用户确认输入测试通过。输入框上下留白原先不参与点击，已改为输入控件内部留白；新增 4 项点击、隐藏后重新打开键盘及四行草稿回归，修复前 3 项失败，修复后全量 102 项通过。静态分析 0 issue，Web release 和 Android debug 构建成功，修复版已覆盖安装。USB 调试保持连接；微信输入法当时报告已显示但键盘区域为空，切换到已启用的搜狗输入法后能显示软键盘。没有把“USB 调试导致不弹键盘”或“微信跨设备模式”判定为已验证根因。

本次修复版 debug APK SHA-256：`15b7ded8e1e4aee0afc33d50ef2c816e87ca62538aa53ec4822cf4e2f7d1f0de`。安装使用 `adb install -r`，没有清除 App 数据。设备截图、输入法诊断和构建日志仅保留在本机忽略目录 `.buildlog/`；下文“全部待执行”表格为早期基线，当前仅安装启动及输入获得真机验收，尚不能据此标记完整 `m3-local-verified`。

最新动作包检查点：PR #1 已合入 `main@adafcf9`，标签 `m4-drill-packs`。本机静态分析无问题，44 项 Flutter 测试、语音工具环境回归通过；93 个动作包与公共包校验通过，695 条语音审计 0 失败。Web release 与 Android **debug** APK 构建成功，APK 中检查到 94 个包 manifest、93 个视频、93 个封面和 695 条语音。下文最初的内存不足记录属于 M3 历史，不能据此认定当前 debug 构建仍失败；也不能把 debug 构建记为 release 或真机验收通过。

对话首页 PR #2 本机复验：静态分析 0 issue、98 项测试及独立截图检查通过，Web release、Android debug APK 构建成功。已修复安全入口绕过、保护条件丢失、详情训练与改版保存、键盘/辅助功能和小屏布局问题，完成 360×640 浏览器主流程走查。[完整审核记录](pr2-local-review.md) 含固定 SHA、证据和 APK 摘要。Web 仍只有视频海报且存在字体回退联网；真机、release 签名与完整设备验收保持待办。

本轮完成本机自动化验证与跟练缺陷修复，检查点标签为 `m3-local-tests`。**Android 设备走查及 release APK 尚未通过，M3 完整验收未完成。** `m3-local-verified` 留待下述设备与构建项目全部通过后再打。

同日补做本机 Web 走查，检查点 `m3-web-qa`：Web release 构建成功，最新静态分析无问题，38 项测试通过；具体结果见下节。Android 待验项目保持未验状态。

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

## 本机 Web 走查（2026-10-19）

入口已加入 `web/`。本机 release 预览地址：<http://127.0.0.1:8766>。验证使用隔离 Chrome 会话，尺寸包括 390×844、844×390 和 1440×900。

| 项目 | 结果与证据 |
| --- | --- |
| 构建与自动化 | `flutter build web --release --no-pub --no-web-resources-cdn` 成功；`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=1` 全部 38 项通过 |
| 安全确认 | 任一回答「是」时生成操作被阻止；刷新后仍保持只浏览状态；从设置重做安全确认后恢复生成 |
| 生成与跟练 | 办公室描述生成工位计划；无器械核心描述生成核心计划；走过准备、训练、暂停、不舒服、提前结束和返回 |
| 暂停与记录 | 暂停后间隔 1.5 秒读取计数，数值与进度保持不变；提前结束显示 0/10，浏览器存储只有一条相应历史；安全状态、最近计划与历史均已写入 localStorage |
| 手动换动作 | 原先无器械计划可把俄罗斯转体换成弹力带抗旋转推；现显示「暂不能替换：弹力带抗旋转推 需要弹力带」，原动作保留；自动化另覆盖有器械可换和保护部位校验 |
| 动作详情 | 原先横屏底部溢出约 353 像素；改成可滚动弹层后，844×390 可滚到要领与注意事项，无溢出报错 |
| 语音 | 对浏览器媒体播放做运行时观察：26 次 play 请求成功，22 次观察到播放时间推进，未记录播放拒绝。音频素材请求成功；未做扬声器实听质量验收 |
| 控制台 | 最终 release 走查没有 console error；debug 模式在鼠标悬停提示期间切换窗口尺寸曾出现 Flutter `overlay.dart` 的 `size == theater.size` 断言，保留为 SDK/调试模式观察项，release 未复现 |

本轮另外修复首页自带的「膝盖不太好」「腰不太好」「腰有点酸」不触发保护条件，以及点击示例后改描述仍沿用旧推断目标的问题。Web 音频的平台判断增加 `kIsWeb` 短路；跟练图标按钮补上可访问名称。

**Web 限制：** 当前视频明确使用 `media_view_stub.dart`，只有海报，没有 Web 视频播放器，不能用 Web 判断 Android 视频解码与同步是否通过。虽然构建时把 CanvasKit 放到本地，运行中仍观察到 `fonts.gstatic.com` 的中文字体请求，因此没有宣称 Web 预览完全离线。Android 的媒体、来电、锁屏和 release APK 验收仍待执行。

浏览器实拍：[暂停画面](screenshots/web-player-paused.png)、[无器械替换拦截](screenshots/web-swap-guard.png)、[横屏详情滚动到底部](screenshots/web-landscape-detail.png)。临时浏览器日志与检查脚本留在本机 `output/playwright/`，不提交仓库。

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
