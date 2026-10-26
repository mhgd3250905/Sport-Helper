# SmartFit：按动作下载缓存层与 v2 自测

> 历史准备节点 `beb3a20`：正式 v3 patch 已接通，当前以 [v3 候选记录](posehub-on-demand-v3-2026-10-26.md) 为准。下文的 v2 复用、待发布状态与旧目录合同不再适用于当前 v3。

2026-10-26，基于 `323c57479ec91e1bdbd3ea109f8c7b071c9e27c4`，继续使用 `feat/posehub219-v2-20261026`。这是 +34 的准备阶段；本轮没有生成新的 release APK，也不合入 main 或操作 `release/1.0`。+33 整包 APK 的记录保留为历史。

## 已完成

APK 资产声明已移除 592,748,021 bytes 的整包 ZIP 和 descriptor；删除 Android 首次解压器、MethodChannel、Dart 整包安装服务及对应测试。宿主中已下载的原始 ZIP 保留，不进入 Git，也不再属于 APK 资产。

SDK 内置 catalog 继续作为唯一目录来源。v2 的 438 张封面／缩略图逐项核验后合计 **17,143,808 bytes（16.35 MiB）**，低于 20 MB，因此图片随 internal 包提供，视频不随包。图片按 catalog SHA 分目录，只在 pubspec 声明当前版本，避免把 v2/v3 两套图片一起打包。媒体载荷仍不进入普通 Git，`images-index.json` 记录原路径、大小、SHA 和内容寻址资产名。

`PoseHubMediaRepository` 按选中动作的 catalog 文件清单工作：

- `ensureFile(file)` 准备单个文件；`ensureAction(id)` 准备该动作文件并返回本地 `mediaBaseUri`。
- App 私有目录为 `ApplicationSupport/posehub-media/<catalog SHA>/`，保留 SDK 原相对路径。文件字节数、流式 SHA-256 均通过后，临时文件才原子改名。
- 同一文件、相同 SHA 内容和同一动作的并发任务复用，最多 3 个任务；进度通知节流至 100ms。失败立即可重试，健康的在途文件继续复用。
- HTTP 超时、重定向次数、响应体大小有界；正式配置只接受 HTTPS。测试 HTTP 仅显式允许 loopback，不更改 TLS 校验。错误状态不包含签名 URL 或请求头。
- 本地命中仍核验 bytes/SHA。旧 +33 私有目录只检查当前请求文件，符合新 catalog 时复制到新缓存，不移动、删除或修改旧目录及用户数据。
- 图片预览只准备图片，播放才准备当前动作文件；动作库首帧不等待整库或视频。App 训练媒体已有局部进度、失败重试和切动作时隔离旧 Future 的回归。

下载配置通过 `SMARTFIT_POSEHUB_MEDIA_BASE_URL` 覆盖 host；`media-delivery.json` 将 catalog 原路径映射到实际 Release asset 名，并核对 bytes/SHA。显式映射缺项直接失败，不猜测 URL。

## 方案依据

检查了维护活跃且许可证明确的实现，再选择最小依赖方案；没有复制外部源码。

| 来源 | 许可证 | 本轮取舍 |
| --- | --- | --- |
| [dart-lang/sdk](https://github.com/dart-lang/sdk) 的 `HttpClient` / 文件 API | BSD-3-Clause | 使用已有运行时，手动处理有界公开重定向、流式写入和原子发布 |
| [dart-lang/http](https://github.com/dart-lang/http) | BSD-3-Clause | 参考请求及流式响应设计；无需再增加一套客户端依赖 |
| [Baseflow/flutter_cache_manager](https://github.com/Baseflow/flutter_cache_manager) | MIT | 其 URL／时效缓存与不可变 catalog SHA 合同不同，不引入额外 SQLite、Rx 和失效策略 |

SDK 旧下载 repository 的清单、目录合同及重定向行为不匹配本轮逐文件 Release，未修改 SDK 缓存源码。`crypto`、`path_provider` 原已在 lock 中，仅改为直接依赖，无新增或漂移版本。

## v2 验证结果

当前仍固定 `ugk_coach-v0.6.1`、`ugk_trainer-v0.4.1`（`eaff581a19204fe1eaea49463a98adff54f043bc`），coach_ui 仍为 `ugk_coach_ui-v0.2.1`。默认 SDK bundle 验证 219 浏览／211 AI／8 待补；产品没有新增写死数量或待补名单。

| 检查 | 结果 |
| --- | --- |
| 缓存层真实 loopback HTTP 回归 | 26 项通过：任务复用、缓存重开、旧 v2 复用、重定向、超时、断流、bytes/SHA 拒绝、临时文件、重试、并发及映射缺项 |
| App 定向整合回归 | 42 项通过：浅深库浏览、搜索与自主单练、预览／播放下载、旧异步结果隔离、媒体交接及主要会话流程 |
| 图片加载／Release 映射 | 各 5 项通过 |
| 真实 v2 素材 smoke | 1 项通过，见下表 |
| 图片准备 Python 测试 | 6 项通过；438 个实际图片逐项 bytes/SHA 核验通过 |
| 全项目静态分析／改动文件格式 | 0 issue／0 格式变动 |
| 离线严格锁文件检查 | `pub get --offline --enforce-lockfile` 通过，lock 哈希不变 |
| Android arm64 internal Dart／资产编译 | `debug_android_application` 通过；产物 ZIP 为 0，438 张图片共 17,143,808 bytes 逐项 SHA 核验通过；未构建 APK 或编译原生 Android 层 |

真实 smoke 使用 SDK 默认 bundle，按视频 bytes 排序动态选择中位动作，loopback HTTP 直接流式提供原始 v2 MP4；没有读取 ZIP、修改素材源或使用合成视频。

| 项目 | 实测 |
| --- | --- |
| 选中动作 | `o-supported-mini-squat` |
| 首次 HTTP / 视频正文 | **1 次 / 2,841,722 bytes** |
| 该动作封面＋缩略图 | 从本地载荷准备，76,436＋18,162 bytes |
| 缓存校验 | 三个文件 bytes/SHA 全部通过 |
| 重复进入 | **新增 HTTP 0 次** |
| 关闭服务器后重建 repository | 离线命中，**新增 HTTP 0 次、网络正文 0 bytes** |

报告：`E:\AII-3D\3D-Sport-AI\deliveries\posehub-on-demand-20261026\v2-download-smoke.json`。同目录保留 HTTP、App 回归、分析、图片核验及严格锁文件日志。

可复现真实 smoke：设置 `SMARTFIT_POSEHUB_V2_SOURCE` 为已核验的解压 v2 根目录（包含 `catalog.json`、`media/`），运行 `flutter test --no-pub test/posehub_media_v2_smoke_test.dart`。未设置时明确跳过，不能当作真实素材测试通过。

## 等待正式 v3 patch 的部分

用户已自行向 SDK 转达接口要求：提供 `prepareFile` / `prepareAction`、进度与重试、准备完成后再启动单练计时，并正式更新 catalog 校验。

当前 SDK 0.4.1 的浏览／详情／单练还没有资源准备插槽；App 没有复制 SDK 页面或修改 pub 缓存。`PoseHubLibraryPage` 已移除整库安装门禁，但 SDK 页面的图片／视频准备与单练计时门控，必须等 patch 后接入。当前 App 媒体适配不代表这部分已经完成。

v2 Release 没有逐文件公开资产，`media-delivery.json` 因而明确为 `ready:false`，不生成虚构下载地址。本提交是开发准备节点，不能用该占位配置交付 +34 release 包。

v3 正式发布后，固定 SDK patch/tag、替换 catalog、重新生成当前 SHA 图片目录和索引、从正式 Release 资产清单生成下载映射，再接入 SDK 回调并进行 GitHub 实际下载、断网重试与 APK 内容／体积验证。先不发布或合并分支。

本轮没有真机安装、原生视频播放或 Raster P99 数字；也没有新的 APK 实测体积。+33 大包和旧截图不算按需版交付。等正式 v3 和接口接通后出 release 内测包，再按原要求进行保留数据安装和浅深真机验收。
