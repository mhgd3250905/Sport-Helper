# 动作素材按需下载验收（2026-10-22，已批准合并）

App 分支 `feat/on-demand-media`，运行源码提交 `ee73bb112b9cf3cdaae7803628d0d9703b73ff24`。
共享 SDK 分支 `feat/trainer-media-cache`，固定提交 `df90e7cb3f53c919927542056dcdfd6c0a600a66`（coach 0.3.3 / trainer 0.1.5）。此验收完成后，开哥已批准先发布 SDK，再发布 App；两边均已合入并推送 main，App 节点 `8f1f3c56f12f3157ea6e1b63e9b89ea867290ba6`。后续独立内测 release、trainer 0.1.6 与语音统计另见 [release 记录](release-size-2026-10-22.md)，不改变此处 +11 历史包的哈希与测试范围。

## APK 与素材体积

同一 Flutter 工具链、debug、通用三 ABI（arm64-v8a / armeabi-v7a / x86_64），单位为十进制 MB。基线为 PR #5 最终运行源码 f92cbc9，main 292a24e 仅增加旧验收文档，运行代码一致。新包额外开启待审核素材预览和局域网双地址，并沿用本机既有 Worker app key 注入方式；没有请求新的 AI 验收调用。

| 项目 | 改造前 | 改造后 |
| --- | ---: | ---: |
| APK | 208,066,987 B（208.07 MB） | 199,556,721 B（199.56 MB） |
| 动作素材，含清单、封面/缩略图、旧 cutout | 23,734,409 B（23.73 MB） | 14,883,430 B（14.88 MB） |
| 动作视频 | 186 段 / 20,157,732 B | 32 段 / 13,035,872 B |
| 素材在 ZIP 内实际占用 | 23,734,409 B | 14,772,925 B |
| 原生库（包括三套 Flutter debug runtime） | 123,885,504 B | 123,885,504 B |

APK 减少 8,510,266 B（4.09%），素材减少 8,850,979 B（37.29%）。**约 15 MB 目标是安装包内的动作素材，APK 总体积仍包含 Flutter 调试运行库。** 当前仓库基线实际随包动作素材为 23.73 MB，并非上百 MB。

候选 APK：`.buildlog/install/SmartFit-media-0.1.0+11-debug.apk`；SHA-256 `147b1dece85a81c1e303d98904db4d6c42c12ded820098b12b0d7e6e8e744b22`。
基线 APK SHA-256 `c44c43c7c54438212806c3b952a559757de1484c0cfad5af4e773fe6488c2c00`。
新包为 `com.ugk.smartfit`、versionName `0.1.0`、versionCode `11`、minSdk 24、targetSdk 36、debug 签名。
逐文件核对 APK 与工作树的 413 项素材 SHA，一致；APK 中无旧 pack 视频/封面及 cutout，只有 32 个 mp4。机器可读结果见 [apk-size-report.json](../tools/media/apk-size-report.json)。

## 包与共用组件

Pose-Hub 来源 `E:/AII-3D/3D-Pose-Hub/release/v0.3.0-app` 只读。主清单版本 0.3.0，来源 mainCommit `41b1922459e36cd4ff2947828135b755465d0613`；清单 SHA-256 `5997a445f33cffac00dd4d9b213c7887d67e776fbb2ee9940e4f7c44c88c0e8d`。

内置仅主清单、builtin / realistic-dark 两份子清单（合计 132,592 B）、189 张有损封面与 189 张缩略图（1,714,966 B）、32 段 builtin 视频（13,035,872 B）。其余 20 份子清单不随包。完整默认补充包 realistic-dark 为 157 段、58,794,127 B（界面显示 58.8 MB），与已有 builtin 合起来覆盖索引中全部 189 个动作。源发布数据、原动作元数据与语音均未修改，资产构建前后已重算保护文件摘要：[builtin-assets-report.json](../tools/media/builtin-assets-report.json)。

App 继续使用已有 93 个动作的训练剂量、保护约束和语音，不为另外 96 个动作虚构训练元数据。新主清单索引全部 189 项，SDK 可以下载完整包；App 与 AI 目录只使用已有训练元数据且获准显示的交集。

下载、SHA 验证、缓存、网络策略、镜像顺序、后台队列（最多 3 个）和媒体展示位于三个 App 共用的 `ugk_trainer`。SmartFit 的 ExerciseVideo 为薄适配。读取顺序为内置、校验过的本地缓存、下载；视频与下载的子清单均先按长度和 SHA-256 校验，再原子启用。缓存位于 App cache 的 `training-media/0.3.0/<sha256>`，临时文件不能播放；统计/清理覆盖受管根目录的所有版本，保留其他缓存、内置文件、计划、历史及偏好。

聊天生成、非聊天自定义生成、换动作和开始跟练都接后台预取，不等待素材才展示计划或启动训练。断网时模板优先使用已经存在的示范，仍遵守器械、场景、难度、保护部位限制。设置提供默认包大小、仅 Wi-Fi 下载（默认开且持久化）、缓存占用与清理；Wi-Fi 恢复会自动续发因网络策略阻塞的请求，HTTP/校验失败保留失败状态供用户重试。不同皮肤/背景通过 SDK 的 `skin` / `theme` 参数保留接口，没有增加素材皮肤选择界面；App 的既有深浅色界面主题继续保留。

生产仅显示 `releaseEligible == true`；当前 189 项全部待审核，默认目录为空且有提示。预览 APK 显式打开 debug 编译开关；release 即使传该开关仍不显示待审核动作。资格会同时过滤 App、AI 目录、SDK 读取与下载入口，旧存档中不可用动作会被拦截并保留存档。

## 异常网络结果

| 场景 | 注入与实际表现 | 证据范围 |
| --- | --- | --- |
| 断网 | Android 关闭 Wi-Fi 与移动数据；未缓存的 h-9090-liftoff 停留在本地封面，显示“示范暂时加载不了，计时和语音仍可继续”，没有新增 HTTP 请求。内置 h-adductor-rock 仍能进入本地视频展示。离线生成优先已有素材且不突破训练约束。 | 模拟器页面/XML + SDK 与 App 选片回归 |
| 弱网 | 局域网服务以 8,192 B / 100 ms（约 80 KiB/s）发送 glute-max-A：先出现“正在加载动作视频”，289,452 B 完成后展示视频，写入 `0.3.0/f388f0fb06182fb8bc767f0562cdd53c5e033b10b2accb98a5a5365c66f78a29`。持续无数据则按 15 秒连接/响应/空闲超时转到备用地址；两者都失败则保留封面和说明。 | 真实 LAN HTTP + Android XML/缓存/视频截图；停滞与镜像回退由 SDK 真实 HTTP 测试覆盖 |
| SHA 校验失败 | 服务返回 HTTP 200、正确长度但翻转视频首字节；8778 和 8779 均被尝试，均被拒绝，页面保留封面与失败说明，Android 缓存目录为 `total 0`，无最终文件或 `.part`。 | 真实 LAN 双地址 + Android 页面/XML/磁盘检查；子清单损坏另有 SDK 回归 |

训练计时与语音不依赖上述下载 Future。实际 App PlayerPage 测试先保持下载 pending，再令其 offline，分别验证封面、加载/失败提示、倒计时继续变化与语音输出调用继续发生。此处语音结论是组件输出调用与原语音文件校验，不声称做过真机听音测试。

Android API35 模拟器已安装最终候选 APK，完成上述短流程。宿主 Windows WHPX 在多次视频运行/网络切换后不稳定，一次日志包含 `WHvEmulatorTryMmioEmulation`，另一次设备失去响应；切换 GPU/禁用 Impeller 用于排查，未写入 App 配置。没有把此环境上的短流程当成长时间播放或真机性能结论。已关闭本任务创建的模拟器，未操作其他设备。

本机未入仓证据目录 `.buildlog/media-cache/`：`ui-weak-loading.xml`、`weak-ready.png`、`ui-corrupt.xml` / `corrupt.png`、`ui-offline.xml` / `offline.png`、`ui-offline-builtin.xml`、`http-events.jsonl`、构建与测试日志。APK 哈希以本节给出的最终候选为准，早期构建日志不代替它。

## 验证

| 检查 | 结果 |
| --- | --- |
| App `flutter test --no-pub` | 全量 265 项通过；后续设置页从 repository 状态显示自动恢复进度的改动，再跑 11 项素材接缝测试通过 |
| App `flutter analyze --no-pub` | 最终 0 issue |
| App `flutter pub get --enforce-lockfile` | 通过，两项 SDK Git ref / resolved-ref 为完整 df90e7cb…，无 path override |
| trainer `flutter test --no-pub` | 最终 SDK 提交全量 144 项通过，其中 18 项媒体专项；静态分析 0 issue |
| coach | 377 项通过，静态分析 0 issue；本轮不改变 coach 运行代码 |
| 资产工具与迁移验证器 | 8 + 13 项 Python 回归通过 |
| `python tools/packs/validate_packs.py --on-demand-media --decode` | 93 动作包 + common，695 条语音，0 errors；默认完整旧包校验模式仍严格 |
| 源素材与 APK | 资产 verify-only、源输入前后摘要、APK 413 文件逐项 SHA、32 视频及旧素材排除均通过 |
| Android debug build | 成功；保留现有 AI key 注入方式，没有打印或入仓 key |

SDK 尚未推送，首次本机解依赖使用进程级 Git `insteadOf` 映射到本地 SDK 仓库获取固定提交；未手工改写 pub cache 实现，仓库保留正式 GitHub URL。合并批准后必须先把该 SDK 提交发布到 SDK main，再发布 App，其他机器才能正常解析这个 ref。初次 Pub 将未发布 Git 依赖记为 0.0.0，已对照提交中的 pubspec 将锁文件版本修正为 0.3.3 / 0.1.5，并由严格锁文件检查确认。

## 本机服务与复现

未上传任何云存储。当前测试主地址 `http://192.168.71.116:8778/v0.3.0-app/`、备用 `http://192.168.71.116:8779/v0.3.0-app/`；两个端口均只读同一 release 根，分别用于顺序回退测试，并非已部署的国内/海外服务。真实部署时可分别配置两个 HTTPS 地址。HTTP 仅 debug 允许；正式构建保留 HTTPS 限制与本机播放器 loopback 白名单。

```powershell
python tools/media/serve_release.py --root E:/AII-3D/3D-Pose-Hub/release --control .buildlog/media-cache/server-mode.json --log .buildlog/media-cache/http-events.jsonl
# control JSON: {"mode":"normal"} / {"mode":"slow"} / {"mode":"corrupt"} / {"mode":"offline"}
```

本轮服务已恢复 normal 并保持运行，供同一局域网的手机安装候选 APK 验收。若换 IP 或端口，重新构建时配置这两个地址。主清单相对路径会解析到相邻 `v0.3.0/` 视频目录，不应把服务根只设为 `v0.3.0-app/`。

```powershell
./tools/coach/build_debug.ps1 -AppKeyFile '<原有本机 app key 文件>' -BuildLog .buildlog/media-cache/android-build.log -DartDefines @(
  'SMARTFIT_INCLUDE_PENDING_MEDIA=true',
  'SMARTFIT_MEDIA_PRIMARY_URL=http://192.168.71.116:8778/v0.3.0-app/',
  'SMARTFIT_MEDIA_SECONDARY_URL=http://192.168.71.116:8779/v0.3.0-app/'
)
```

开哥已审阅并批准按 SDK → App 顺序合并推送，执行成功且远端 ref 已核对。本阶段不代替素材审核或云端发布。此验收期间 Cockpit 进度同步曾两次返回 SERVICE_UNAVAILABLE；后续服务恢复，使用原请求重放补登记并登记批准后的发布节点，没有重新 init、切换会话或猜测 revision。
