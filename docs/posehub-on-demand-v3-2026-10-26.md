# SmartFit v3：按动作下载内测候选

基于 `beb3a2027dafe3e8a2602947ba8cee897d08d9e5` 继续 `feat/posehub219-v2-20261026`，版本 `0.1.0+34`。本轮用户确认暂不能连接红米，先出包；没有安装、清数据或操作设备。main、release/1.0 及暂存的微拟物改动保持原状。

## 来源与包体

- `ugk_coach-v0.6.2`、`ugk_trainer-v0.4.2` 的 annotated tag 解引用及远端 main 均核到 `ac9b31f1d3f32edaa5c461b95d2eadc71b54e88a`。`ugk_coach_ui-v0.2.1` 不变；lock 只升级前两项。
- 依照 SDK `docs/posehub-app-test-pack-r1-v3.md`，素材版本 `posehub-app-test-pack-r1-v3`，catalog 为 2,896,158 bytes，SHA-256 `75881cf91621c967f80732f0219f23e85b35e8bde5d1a51ee75dec5f7c5edd36`。
- 219 浏览／211 AI／8 待补仍从 SDK 接口取得。v2/v3 的动作 ID、顺序与所有非媒体字段逐项一致；不编造待补剂量。
- APK 不含整包 ZIP 或这 219 个动作的视频。438 张图片合计 **6,513,102 bytes（6.21 MiB）**，由当前 catalog SHA 目录随 internal flavor 提供；pubspec 只声明 v3 图片目录。源素材和旧 v2 本机资产保留，媒体载荷不进入普通 Git。
- release arm64 APK、源码指纹、签名、实际大小、SHA-256、相对 +32 的包体差值，以交付目录 `release-apk.json` 为准；构建 helper 禁止覆盖已有交付。

## 下载与 SDK 就绪门控

下载地址由有序 `mediaBaseUrls` 配置，逐项用原始、区分大小写的 `file.path` 解析。目前只配置 `https://media.uuugk.win/pack/r1-v3/`。以后可将国内地址置于列表首项，失败自动切下一地址；HTTP、网络、断流、超时、字节数和 SHA 校验失败都不能提前发布文件。

`assets/posehub/media-delivery.json` 固定 pack/version/catalog 身份和地址列表；构建覆盖项 `SMARTFIT_POSEHUB_MEDIA_BASE_URLS` 接受 JSON 字符串数组，例如 `["https://first.example/pack/r1-v3/","https://backup.example/pack/r1-v3/"]`。正式地址必须为无凭据、无 query/fragment 的 HTTPS 目录。

私有缓存为 `ApplicationSupport/posehub-media/r1-v3/<catalog SHA>/`。下载先写 `.part`，bytes/SHA 全部通过后原子改名；任务、内容和动作请求复用，进度局部更新。**v2 的旧安装目录、无版本缓存和 r1-v2 命名空间均不查找、不复用**；也不删除这些旧目录或用户训练数据。

`SmartFitPoseHubMediaPreparer.prepareAction(action)` 将 App 缓存进度映射到 SDK 的 Progress／Ready／Failed 流；只有 `ensureAction` 真正成功才 Ready，100% 进度不代表完成。退订只移除该消费者监听，不取消其他消费者共享的下载；错误只呈现安全中文与重试。

SDK 动作库使用同一稳定 preparer，进入单练时准备该动作，准备或失败期间禁用开始和计时；Ready 后仍由用户点击开始。App 视频也使用 SDK 准备控制器及主题面板，后台、覆盖路由和切动作晚回调保持隔离。

App 多动作 `TrainerPlayer` 暂无公开时钟暂停接口，因此本轮在挂载引擎前准备**本次计划实际引用的唯一动作**，并非整库下载；全部 Ready 且页面在前台后才创建引擎。这样下载等待不会消耗训练时间，也不复制 SDK 训练引擎。准备失败可重试。

SDK 静态图片组件没有下载 hook，故首页后台仅将小图从 APK 核验复制到私有目录；首次挂载动作库先等待这项本机操作，避免 `FileImage` 首次失败后无法自动刷新。这里不下载视频。图片准备失败不会永久锁住动作库。

## 自动化与公开网络证据

核心 HTTP 回归 34 项通过，覆盖有序主备、bytes/SHA 拒绝、截断与超时、失败清理、并发复用、版本隔离、旧 v2 同 SHA 仍不得复用。SDK 默认 bundle 合同 4 项、地址配置 5 项、UI／计时门控 42 项通过；App 受影响流程整合回归通过。另以实际 v3 目录运行两个适配文件 17 项全部通过、0 跳过，保留全部 93 个历史训练 ID；这两条外部目录测试已从旧 fixture 读取器迁移到与产品一致的 SDK 入口。各组包含重复用例，不相加宣称全量测试。全项目分析 0 issue、严格 lock 检查无漂移，最终日志在同一交付目录。

真实 R2 smoke 使用正式 SDK 默认 catalog，按视频 bytes 排序动态取中位动作；匿名 HTTPS 使用默认 TLS 校验，没有读取 ZIP 或绕过证书。

| 桌面自测项目 | 结果 |
| --- | --- |
| 动作 | `serratus-C` |
| 视频 | 749,713 bytes |
| 封面／缩略图 | 25,054／5,162 bytes |
| 首次网络准备 | 3 个 GET，779,929 bytes，6,456 ms，失败 0 |
| 完整性／响应 | 三文件 SHA 一致；HTTP 200、MIME、immutable 缓存头正确 |
| 重复准备 | 11 ms，新增 HTTP 0 |
| dispose 后重开，显式阻断网络 | 18 ms，新增 HTTP 0 |

该网络用例刻意不提供 bundled loader，验证全部三文件下载。实际 APK 随包提供小图，正常首次只需要下载该动作视频。这些时间来自桌面网络环境，**不是真机下载等待、播放或性能数据**。只有一个正式源时，备用切换由受控 HTTP 回归验证，未声称有第二个正式 CDN。

## 构建与真机边界

交付目录：`E:\AII-3D\3D-Sport-AI\deliveries\posehub-on-demand-v3-20261026`。`build_release.py` 从干净提交构建同包名、同 +32 签名的 internal arm64 release，验证无整包 ZIP、无 PoseHub 视频、仅当前图片目录、根 catalog SHA、JNI 和 16KB 对齐；不操作设备。

开哥连接红米后再以 `install -r --no-incremental` 覆盖安装，保留聊天、计划、训练历史及标记。待测：首次单练等待、断网失败重试、已缓存离线播放，以及浅／深动作库滚动 Raster P99 与超预算帧数。120Hz 目标仍为 P99 <8.33ms、超预算帧接近 0。

本轮真机 P99 为**未采集**，不能用桌面网络、Widget 测试或旧 +32 的流畅反馈代替。当前 R2 冷准备自测约 6.46 秒，国内网络等待仍需真机确认；可按已接通的列表配置增加前置国内源。

SDK 库／单练仍没有宿主问题标记扩展槽；App 原训练标记保留，SDK pack 无真实位置快照时不虚构时间戳。此候选先不合 main、不推 release/1.0，等开哥实测反馈。
