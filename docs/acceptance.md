# 本机验收记录

## 1.0.0+25 发布验证与封闭测试（2026-10-24）

打包源码 **`9d7bcff629be8c33bed6e12b0285314ad514f9d6`**，发布分支 `release/1.0`；包身份和哈希以[台账](version-management.md)及[版本存档](reports/version-save-1.0.0+25-2026-10-24.json)为准。原验收界面保留，不注入在线 AI Key。此节不把用户此前对旧包的认可扩展为当前包全项设备通过。

| 证据 / 命令 | 结果与时间来源 | 对应 source state / 边界 |
|---|---|---|
| `flutter analyze --no-pub` | 同一会话2026-10-24打包前执行，0问题 | 上述完整打包SHA；本次未重跑全量分析 |
| `flutter test --no-pub` | 同一会话最终重跑435通过、13跳过；旧字节断言首次失败及修复过程保留 | 上述SHA；跳过项不计为通过，本次不新增全量结果 |
| `python tools/release/test_release_contract.py` | 本次15:44只读重跑8项通过 | 干净HEAD等于打包SHA；身份、固定SDK、上传签名配置、生产素材范围和iOS配置合同；不等于iOS编译通过 |
| `python tools/release/validate_release_source.py` | 本次15:44重跑：93项App动作放行，其他96项待发布 | 同一干净HEAD；只允许已授权的运行源码/素材修正 |
| `python tools/packs/validate_packs.py --on-demand-media --decode` | 同一会话打包前93项及公共包/695条语音校验0错误 | 上述打包SHA；本次未重新解码语音 |
| `tools/release/build_play_bundle.ps1`，外部签名配置、固定公开媒体URL、`-Offline` | 同一会话已构建1.0.0+25 AAB；pub.dev过程环境与已锁依赖一致，签名/包检查通过 | 已观察的既有构建，完整启动路径含外部私有签名配置，未在本次读取或重执行。不是文档保存提交的新构建 |
| 真机同载荷简测 | 无损更新到+25，93项库和非内置素材可用；前2个动作完成、到第3/8后提前结束，结果2/8；后台约8秒服务仍为mediaPlayback foreground，结束后释放 | AAB导出的本地更新副本改用手机旧安装证书，1618个非签名ZIP条目逐项SHA相同；不声称上传证书APK直接覆盖成功 |
| 政策与物料 | 真机从设置打开隐私和条款正文；4张真实截图，约75秒实际流程视频已上传YouTube、不公开列出且匿名可播 | 同一+25载荷的局部观察；不是完整12分钟训练或长时/跨设备验收 |
| Play提交1详情（MCP Playwright只读页面） | 14:49提交16项更改；本次15:45刷新显示“已发布”，后台给出15:02发布时间 | Alpha `1.0.0 (25) - Closed test` 的外部观察；不证明Production资格、公开分发或源码全项测试 |

本次closeout开始时HEAD与打包SHA相同，`git diff --name-status 9d7bcff629be8c33bed6e12b0285314ad514f9d6..HEAD`为空；完整tracked/untracked状态为空。后续只更新Markdown和版本记录JSON，不改lib/assets/pubspec/lock/平台配置/测试/构建脚本，因此旧源码验证仍适用于未改运行代码；本次新增验证仅限文档一致性、链接和Git保存。

初次上传签名APK覆盖旧调试签名包失败的历史保留；没有为录屏卸载或清数据，也没有安装/使用模拟器或修改手机显示设置。稳定视频展示用户开始、后台语音、返回暂停和明确提前结束，不声称完整训练通过。iOS、连续>20分钟和更广设备矩阵仍未验；正式版还需真实12人连续14天封测及后续资格审核。

## 以下为历史验收，不能替代 +25

## +15 用户确认与版本保存（2026-10-23）

开哥在本会话反馈：“我测试通过了 你先做一个版本保存 文档对齐台账更新”。关联最近交付的 `0.1.0+15` internal arm64 修复包，本轮状态更新为 **用户确认测试通过，保存本地版本**。

| 项目 | 已核对结果 / 证据 |
| --- | --- |
| 运行源码 | `15079e6fc57be7c1e0d5b6c5f876784f183ce63e`，分支 `feat/voice-aac-comparison` |
| 版本保存标签 | 本地注释标签 `smartfit-v0.1.0+15-internal-verified`；指向本次文档对齐节点，运行代码保持上述提交 |
| 交付 APK | `SmartFit-0.1.0+15-storage-fix-internal-arm64-v8a-release.apk`，本机 `.buildlog/install/` 保留 |
| 包身份 | `com.ugk.smartfit.internal` / versionName `0.1.0` / versionCode `2015`，arm64-v8a，release / 非 debuggable，minSdk 24 / targetSdk 36 |
| 大小 / SHA-256 | 49,384,327B（49.38MB）；`6ecdc72d0fb48c8b179e288009cfe8279a50be4bef1391ee7dfdedebf48249fb`；本次重新读取文件核对一致 |
| 固定依赖 | App 两项 SDK ref 均为 `f684e02f38e652633c23fa8946a53d02b6aa3ea2`，coach 0.3.3 / trainer 0.1.6；这是 App 固定依赖，不代表 SDK 当前主线 HEAD |
| 已有自动化证据 | 运行源码的 Flutter 298 项、Python 3 项、分析 0 issue、严格锁文件、三 ABI release JNI 门禁和资源哈希通过，沿用[修复记录](android-storage-jni-fix-2026-10-23.md) |
| 用户验收证据 | 当前会话的通过确认；本次没有新增逐项设备日志、耗时或 token 数字 |
| 本次保存范围 | 文档、验收记录、台账和本地注释标签；未重建已测 APK，未合并或推送 |

该确认不扩展为此前暂缓的连续 >20 分钟训练或 iOS 验收通过；这些仍按[连续训练清单](physical-release-acceptance.md)单独记录。+13/+14 的存储缺陷及旧失败证据保留，当前推荐包为 +15。机器可读存档见[版本保存记录](reports/version-save-0.1.0+15-2026-10-23.json)。

## AAC-LC 与运行日志阶段（+13 → +15，2026-10-22–23）

695 条语音已按开哥选择转换为单声道 AAC-LC 32kbps / 22.05kHz，原件不覆盖；动作素材按内置与下载组合保持 413 文件 / 14,883,430B。+14 增加运行日志，手机日志揭示存储 JNI 混淆使设备标识读取失败、整段走本地引擎。+15 补官方 Kotlin keep 规则、修复失败写入后的缓存标识读取，并增加最终 APK JNI 检查。阶段证据分别见[语音转换](voice-lc32-release-2026-10-22.md)、[运行日志](internal-runtime-logs-2026-10-23.md)和[Android 存储修复](android-storage-jni-fix-2026-10-23.md)；本次用户通过确认以本页顶部为准。

## release 分包与语音统计（0.1.0+12，2026-10-22）

开哥批准后已先推送 SDK main `df90e7c`，再推送 App main `8f1f3c5`。随后按明确选择增加隔离的 internal release，SDK trainer 0.1.6 `f684e02` 已先发布；App APK 运行源码为 `4fdf8ac`。生产 / 内测 arm64 release 均约 55.71 MB（55,712,099 / 55,711,995 B），较上轮 debug 通用包减少 72.08%；三 ABI 分包均已构建，调试 Kernel、VM snapshots、Vulkan 验证库均未打包。生产门禁与 HTTPS 限制保留，内测独立应用 ID。App 265 项测试、分析 0 issue；trainer 145 项及 AOT 编译策略矩阵 18/18 通过。695 条语音未改，原本已是 AAC 单声道，逐条时长/码率及低码率预算已交付。开哥确认目前没有真机，连续 >20 分钟真机训练仍未执行，不能记为已通过。详见 [release 记录](release-size-2026-10-22.md) 与 [待执行清单](physical-release-acceptance.md)。

## 动作素材精简与按需下载（0.1.0+11，已批准合并，2026-10-22）

App `feat/on-demand-media` 运行源码 `ee73bb112b9cf3cdaae7803628d0d9703b73ff24`，共享 trainer 0.1.5 固定 SDK `df90e7cb3f53c919927542056dcdfd6c0a600a66`。开哥批准后已按 SDK → App 顺序合 main 并推送，App 文档节点为 `8f1f3c5`。素材 413 文件 / 14,883,430 B，APK 的旧视频/封面/cutout 均已排除，视频仅 32 段；同为通用三 ABI debug APK，208,066,987 B → 199,556,721 B。App 全量 265 项通过，最终 SDK trainer 144 项 / coach 377 项通过，静态分析与锁文件检查通过。断网封面降级、弱网先加载后启用、双地址 SHA 失败拒绝启用已有模拟器短流程和 HTTP/组件回归证据；计时语音继续运行由实际播放器组件测试验证。尚无真机长时播放结论；细节、哈希、配置和宿主模拟器限制见 [本轮完整记录](on-demand-media-acceptance.md)。

## 计划卡片展开与可访问性（PR #5 已审核合并，2026-10-22）

开哥授权本机修复、通过审核后合并。已测运行源码 / PR 最终 head `f92cbc936a123b77bc43d2a23987d928596eaefd`，目标 main `d4b3e76bf10474ae6c49d8b9f376fa842e16840b`。两项 P2（标题与收起按钮重叠、隐藏详情按钮仍能 Tab/Enter 激活）已关闭；保留原展开/收起节奏和共享元素过渡。全量 253 项测试通过，新增 16 项覆盖窄屏、随包字体、三档字号、深浅色、减少动效及键盘反向操作；分析 0 issue、严格锁文件、Web release 与 Android debug 编译通过。

正式 Web 入口以独立本地 origin 和模板生成计划，已验证展开、保存、详情、切深色、进入共享 SDK 播放器、暂停/提前结束并返回；控制台 0 errors / 0 warnings。GitHub 已提交 [APPROVED review](https://github.com/mhgd3250905/Sport-Helper/pull/5#pullrequestreview-5602560196)，合并提交 `172366c6527d999b7817d97fe386e442f70f0e20` 的整个文件树与已测 head 一致，本地主线已快进同步。SDK 0.3.3 固定依赖、顶部栏移除和 AI 链路保留；没有新增 Worker 请求、真机体验或性能结论，也没有交付/安装新 APK。完整证据与截图见 [PR #5 审核记录](pr5-local-review.md)。

## SDK 0.3.3 提速接入（0.1.0+9，已合 main 并推送，2026-10-21）

`feat/coach-033-speed` / 运行源码 `158f4ac0d2cf7bfed0ac37d63ec6bd66eb0e5537`，coach / trainer 均固定 SDK main `fc5e456c44d76b872eb812597ffb5f67bc66bce3`。完整 237 项测试、分析 0 问题、严格锁文件检查通过。此前 56 项只验了隔离旧 UI 树，本次已补全量。六条真实 Worker 与最终 SDK 运行代码、当前 App 的 AI 链路一致，按要求复用，合计 180.430 秒、74,130 token、无回落；没有重复请求或改写成新跑结果。

经开哥批准，验收分支 `3388bd1edc86c43b5b5e8297cacd4b3ac19c644b` 已以 `f80db2804d6cb9791817463cd1cd5250b32a0e84` 合入并推送 App main，合并树与验收分支相同，包含此前移除顶部栏的修改。按本次要求已构建 `+9` debug 包，未降级安装到已装 `+10` 的真机。逐条耗时/token、复用依据与日志见 [0.3.3 验收记录](coach-033-smoke-2026-10-21.md)，包身份见 [版本台账](version-management.md)。此次合并后仅更新文档，不重复测试、构建或冒烟。

## 顶部栏移除（0.1.0+10，调整分支，2026-10-21）

`fix/chat-without-top-bar` / 运行源码 `89ffa8f` 去掉顶部动作栏，新对话移至左下角抽屉；237 项测试、分析 0 issue 与 Android debug 构建通过。真机已覆盖安装 `+10`，前台截图确认顶部栏消失、原聊天保留；未清空数据。当前 main 仍为 `+9`，包身份与证据见 [版本台账](version-management.md)。

## Liquid Glass（0.1.0+9，PR #4 已审核合并，2026-10-21）

审核原 head `d92f89a`、目标 main `530686e`；解决六处冲突并修复 320px / 大字体单动作卡溢出后，运行源码为 `829381ffa19b737a6c146c8c73b33394937665b1`。最终 PR head `67d1a731281ea5b865e6d5fd2fb2253e0a464795` 仅再加审核文档与截图。已获授权由 GitHub 以 `561ea8cc69efa38d07c03169c257e8fa4116bc72` 合并，整树一致。

237 项测试、静态分析 0 issue、严格锁文件、Web 与 Android debug 构建通过。真实浏览器正式着色器下检查深浅色计划生成、展开、保存、新对话、SDK 播放器暂停/提前结束返回，控制台 0 errors / warnings。新增队列交错写入和键盘下取消/新对话回归；包与截图见 [完整审核记录](pr4-local-review.md)。本轮没有新增真机帧率或真实 Worker 请求，不改写下方 `+8` 的独立证据。

## SDK 0.3.2 接入（0.1.0+8，核心已验，已合入并推送 main，2026-10-21）

2026-10-21 开哥批准后，`feat/smartfit-coach-032@f0ebafc6257347e62533d98fb5d57f0706ddf6e9` 以 `ebb0840f479acdf0bdc8a46e41f30eff055a0c1b` 合 main，版本 `0.1.0+8`，合并树与审核分支一致；已推送 origin/main 并核对远端一致。两项 SDK ref 仍为 `b26e4fda807b6ef3db15a61ba30c67fb51dce5e1`，运行源码、测试与 APK 继续绑定 `b39304488e964b22a65501363a15140b5d0ca235`。原六条合法交互、独立严格卡片补验及原脚本 exit 1 均保留，本次不重跑或改写数据。

| 检查 | 本轮状态 |
| --- | --- |
| 依赖解析 / 严格锁文件 | 通过；`.buildlog/coach-032-lock-verify.log` |
| App 全量测试 | 224 项通过；`.buildlog/coach-032-tests.log` |
| 静态分析 / debug 构建 | 分析 0 issue、debug 构建成功；`.buildlog/coach-032-analyze.log` / `coach-032-build.log` |
| APK 身份 | `.buildlog/install/SmartFit-coach-0.3.2-0.1.0+8-debug.apk`，203,937,142 bytes；SHA-256 `a8746c2a04348855dc43cd9b402a9733cc827edda1f72d7d35070bf818dee4d7`；`com.ugk.smartfit`、versionName `0.1.0`、versionCode `8`、minSdk `24`、targetSdk `36`，debug |
| APK 资产核对 | 与 `+7` 比对，1,167 条 pack entries 无缺失，程序 kernel 更新 |
| 六条真实 Worker | 全部固定 `b26e4fd` 全新完成，39 步、43 请求、384,013 token，均 ok、无回落；臀桥第 3 步 badResponse 重试 4 次后恢复，关闭记忆计划触发 slow。原严格脚本保留唯一 `actions: no ValidatedActions` / exit 1，不能记为脚本全通过 |
| 记忆三轮 | 实际保存 level / equipment 两条且 durable snapshot 相等；新对话排计划首请求含记忆摘要、难度 1、含哑铃卧推/划船；关闭后全轮无摘要/工具、无哑铃动作、原条目保留 |
| 动作卡独立补验 | 显式展示「脚踩椅面臀桥」：4 步 / 4 HTTP / 72.908 秒 / 20,109 token，ok、无重试/slow/回落；actions 与 App 卡片均为 `w-feet-on-chair-bridge`，使用同一准入对象，未交付计划。独立 verdict 空失败、exit 0，不覆盖原六条 verdict |
| 源码与证据边界 | 相对 `b393044`，lib/assets/pubspec/lock 无变化；补验只调整 harness，APK 和 224 项测试来源不变。完整记录见 [0.3.2 验证](coach-032-smoke-2026-10-21.md) |
| App 合并与交付 | 已获开哥授权以 `ebb0840` 合 main，审核源 `f0ebafc` 整树相同；已推送 origin/main 并核对远端一致。原 APK 不变，无本轮真机或完整训练通过结论 |

本轮核对 SDK 默认 100 逻辑步、单次请求 60 秒、整轮 360 秒、每步最多 4 次重试及 30 秒慢提示，客户端不另重试，App 外保护 390 秒。新增重试序号、整理上下文及「还在想…」进度；最终失败分类回落，内部异常不进入渲染。记忆逐条持久化确认、已确认事实取消后保留，清除失败抛错；typed 动作/计划门禁和取消不显示继续保持。

## 首次 Skill Agent（0.1.0+7，历史分支未单独合并，功能随 +8 入主线）

以下只记录 `+7` 当时的验证、包身份及待审批状态，不替代 `+8` 的独立终验。旧 `+7` 未单独合并，其功能已随获准的 `+8` 一并入 main；旧 SDK main `1d1aad8` 和待批表述仅描述历史时点。

历史分支 `feat/smartfit-skill-agent`，包版本 `0.1.0+7`，运行源码 `5743073691547d44aec891ab6d4a45b5b3fa381b`；`ugk_coach 0.3.0` / `ugk_trainer 0.1.4` 当时按 SDK 规则第 4 条临时固定修复 `43dfef637144a1e08b5eda5ed743db0671ba5a8d`。SDK 分支完成推理字段续传、空字段及记忆开启指令修复。当时 SDK main 为 `1d1aad86f516bd7121cc73c71d623043f1042dc3`，修复待批；现 SDK 0.3.2 已在 main，不能把此旧审批状态当作当前待办。App 不复制、内嵌或 patch SDK，不改 pub 缓存；`712cb7b` / `029af4a` 的旧包与源码继续单列。

| 检查 | 当前结果与边界 |
| --- | --- |
| 依赖解析 / 锁文件 | 当前 `43dfef6` 的 `flutter pub get --enforce-lockfile` 通过；日志 `.buildlog/skill-agent-43-lock-verify.log` |
| SDK 独立修复验证 | `43dfef637144a1e08b5eda5ed743db0671ba5a8d`：coach 304 项、trainer 126 项测试通过，两包分析均 0 issue；已推送修复分支，未合 SDK main |
| App 全量测试 / 分析 | 绑定 App `5743073` / SDK `43dfef6`，217 项通过、分析 0 issue；日志 `.buildlog/skill-agent-43-tests.log` / `skill-agent-43-analyze.log` |
| Android debug 构建 | 固定当前 ref 后构建成功，仅以 dart-define 注入密钥；日志 `.buildlog/skill-agent-43-build.log` |
| 当前 APK 身份 | `.buildlog/install/SmartFit-skill-agent-0.1.0+7-debug.apk`，229,903,158 bytes；SHA-256 `9d35b899e59b60f613f65d230431f1c4f0368da07b8c0f61a79daebed0946e19`；`com.ugk.smartfit`、versionName `0.1.0`、versionCode `7`、minSdk 24、targetSdk 36，debug |
| 真实 Worker 多步 | 前三轮关闭记忆案例按与 `712cb7b` 的等价性复用；当前记忆写入、后续参考及关闭后隔离三轮均通过，六类核心功能通过，最终采用的六条记录均无回落。逐轮证据见 [CoachAgent 首次真实 Worker 验证](coach-agent-smoke-2026-10-21.md) |
| 交付与合并 | 当前 debug 包已在本机保留，无本轮真机或完整训练通过结论；SDK 和 App main 合并推送均待相应验证通过并取得开哥同意 |

本轮实现将 `CoachSession` 换为 `CoachAgent`，`maxSteps` 保持默认 10，HTTP 单次 120 秒、不自动重试，App 整轮保护超时 1230 秒；订阅 `reading` / `checking` 分别显示「正在查动作库」/「正在核对计划」。重复发送禁用、取消及新对话作废结果不显示；纯文字仅用 SDK 接纳结果，动作与计划分别只以 `ValidatedActions` / `ValidatedPlan` 进入渲染、保存和 trainer，失败仍使用标明「预设方案」的本地模板。

记忆由 App 实现 `UserMemoryStore.load/save`，独立本机键 `smartfit.ai-memory.v1`；「AI 记忆」开关持久化并即时同步 Agent，「清除记忆」调用 SDK 后复读本机存储确认成功，失败有提示。关闭和清除保留当前聊天与计划，因此真实关闭记忆验证需先开「新对话」隔离旧消息及已解析条件。当前 `43dfef6` 已在真实 Worker 3 步、35.372 秒、11,487 token 后完成 `level=新手` / `equipment=家里有哑铃` 的实际本机保存和文字确认；后续计划实际使用哑铃、难度 1；关闭后无记忆摘要/工具且计划无哑铃，原记忆仍在本机，两轮均通过。

`+7` 固定 `43dfef6` 后的依赖检查、217 项测试、分析和 debug 构建通过。该提交只改记忆开启指令，关闭记忆 system/tools SHA 与 `712cb7b` 相同，故当时复用前三条并新跑记忆三条。这一分组复验规则不适用于改变了预算、重试及持久化的 SDK 0.3.2；当前 `+8` 六条必须重新执行。旧 `+6/+7` 的成功不代替顶部本轮终验。

### 推理字段第二版修复阶段（`712cb7b`，历史）

| 检查 | 第二版阶段结果 |
| --- | --- |
| 源码 / SDK | App `a7cfe04550c8c8cac867b105470d66c96744858d`；SDK `712cb7b3d636a5314c5aa08211c822928a0af4f4` |
| 自动化 / 构建 | App 217 项、分析 0 issue、严格锁文件与 debug 构建通过，日志 `.buildlog/skill-agent-712-tests.log` / `skill-agent-712-analyze.log` / `skill-agent-712-lock-verify.log` / `skill-agent-712-build.log`；SDK coach 299 项、trainer 126 项与两包分析 0 issue |
| 历史 APK 身份 | `.buildlog/install/SmartFit-skill-agent-712cb7b-0.1.0+7-debug.apk`，229,902,535 bytes；SHA-256 `2f513b380d9ba091c989fd5dff79bbded45f947b70ef36d185970c23d9b8cca8`；包 metadata 与当前 `+7` 相同，旧摘要不作当前包身份 |
| Worker 边界 | 前三轮关闭记忆案例通过；第四轮仅给出计划，未调用 `remember`、本机仍空，促使当前记忆指令修复。前三轮依关闭记忆系统/工具 SHA 等价复用，详细记录见 [真实 Worker 验证](coach-agent-smoke-2026-10-21.md) |

### 第一版 SDK 修复阶段（`029af4a`，历史）

此阶段绑定 App `0a8fada86b504964551bc58f8854837162210e6c` / SDK `029af4a1e735b5f1c3f1ee5cef6c82aad8a1c3f4`，不作为第二版 `712cb7b` 的终验。SDK 第一版 coach 291 项、trainer 126 项测试及两包分析 0 issue；App 结果如下。

| 检查 | 第一版阶段结果 |
| --- | --- |
| 依赖解析 / 锁文件 | `flutter pub get --enforce-lockfile` 通过，日志 `.buildlog/skill-agent-fixed-lock-verify.log` |
| App 全量 / 分析 | 217 项通过、0 issue，日志 `.buildlog/skill-agent-final-tests.log` / `skill-agent-final-analyze.log` |
| Android debug 构建 | `tools/coach/build_debug.ps1 -AppKeyFile '<本机文件>'` 成功，仅以 dart-define 注入密钥；日志 `.buildlog/skill-agent-debug-build.log` |
| 历史 APK 身份 | 已另名保存 `.buildlog/install/SmartFit-skill-agent-029af4a-0.1.0+7-debug.apk`，203,909,858 bytes；SHA-256 `35b07c8ae6b59a82d9bb6f2883999143841ed17fec0dd4da7294114ef2b7b326`；`com.ugk.smartfit`、versionName `0.1.0`、versionCode `7`、minSdk 24、targetSdk 36，debug。该摘要只属于第一版历史包 |
| Worker 边界 | 核心计划多步请求通过；臀桥第三步 HTTP 400 暴露缺失/null 推理内容也须显式回传空字段，未完成全部六轮 |

SDK main `1f8be6e` 阶段曾完成 215 项全量及后续 28 项定向回归，日志为 `.buildlog/skill-agent-tests.log`、`skill-agent-settings-progress-tests.log`。这些开发阶段结果与第一版 217 项全量存在重叠，不累加，也不代替当前修复的终验。

## 工具会话（0.1.0+6，历史核心功能已验，2026-10-21）

以下保留上一阶段源码、包与模拟器证据，其 HTTP 次数、耗时与通过结论只适用于 `+6`。

当前主线 `main`（原分支 `feat/smartfit-coach-tools`），运行源码 `9e94bb513751def6306f8e63313050efd632ccb9`，包版本 `0.1.0+6`。两个 git 依赖固定 SDK main `09a392bc0b736e6a23eef71d55d86108660e0e59`（`ugk_coach 0.2.0`、`ugk_trainer 0.1.4`），远端 main 已核对；SDK 工作区和 pub git 缓存均未修改。现有 smartfit profile 与该 SDK JSON 内容一致，AI 目录仍只含实际随包 93 动作。

| 检查 | 本轮结果 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | 通过，两项依赖的固定 ref 与 resolved-ref 一致；其余依赖版本保持 |
| `flutter test --no-pub` | 195 项通过。含 24 项工具引擎回归、9 项会话/卡片组件回归，以及既有 App/训练/存储回归；不与旧版本测试数叠加 |
| `flutter analyze --no-pub` | 无问题 |
| `tools/coach/build_debug.ps1 -AppKeyFile '<本机文件>'` | debug 构建成功，仅经 dart-define 注入密钥；本轮源码与上述 commit 一致 |
| APK | `.buildlog/install/SmartFit-coach-tools-0.1.0+6-debug.apk`；229,742,403 bytes；SHA-256 `7469c492cdc400ba2648dfb837394334ce6c6a507f12c3019d2cce26f787e59b`；已安装 API35 x86_64 模拟器 |

测试覆盖真实 loopback HTTP 工具协议、无 Authorization、持久 UUID、门禁全部错误反馈及最多两次重交、原始无效输出不显示、断网/超时/429 的「预设方案」、模板门禁、水平/时长/保护部位条件、busy、取消与 reset 的迟到结果、当前计划上下文、保存 ID 唯一性、卡片恢复重验和页面关闭保留会话。SDK 新 trainer 只统计实际完成工作，跳过动作计 0；两处旧测试已据此更新，仍核对记录保存和编辑计划快照独立保存。

配置为 BaseURL `https://api.uuugk.win/v1`、模型 `deepseek-v4-flash-0731`；单次请求 120 秒、HTTP 不自动重试，门禁最多重交 2 次，总保护超时 365 秒。模型给出的重复计划 ID 只在通过门禁后替换为独立 App ID，替换后再次经 SDK `admitTemplate` 取得 `ValidatedPlan`；不修改计划动作或剂量，不修改 SDK。

### 模拟器真实 Worker 首轮冷烟

环境为 API35 `sdk_gphone64_x86_64`。每种工具均从 SDK 空会话首轮发起；这是 App / SDK 会话冷启动记录，未证明远端 Worker 实例或上游模型缓存处于冷态。通过调试 VM 延时调用真实 `ChatController`，卡片/详情/保存/开练另用实际界面核对；测试安全确认采用模拟器的合成「无禁忌」状态，不代表真实用户健康状态。

| 请求与操作 | 观察 |
| --- | --- |
| 新手、办公室、徒手、保护膝，展示两个站姿肩颈动作 | 22.5 秒；`TurnStatus.ok` / `TurnOutcome.model`，submissions 1、HTTP 1；返回 `h-wall-angel` / `o-stand-sidebend`，仅 `ValidatedActions` 进入动作卡 |
| 点击「靠墙天使」动作卡 | 打开同名动作详情，展示本地示范素材、要领和注意事项 |
| 实际点击「新对话」 | SDK turnCount 清为 0，当前计划为空，旧卡清除，安全确认保留 |
| 新手、办公室、徒手、保护膝，3 分钟、3 动作计划 | 32.4 秒；`TurnStatus.ok` / `TurnOutcome.model`，submissions 1、HTTP 1；生成「办公室肩颈放松」，App ID `ai-1792550089320914-81abb71a`，3 个动作；仅 `ValidatedPlan` 进入计划卡 |
| 实际点击计划保存 | 已存数量 0→1 |
| 重启恢复 | 原 AI 计划与已保存状态保留；卡片重新通过 SDK 门禁，SDK 新进程会话 turnCount 为 0 |
| 从恢复的原 AI 计划卡点击开始 | 已进入 `ugk_trainer`；显示「靠墙天使」、10 次、准备倒计时和 1/3 进度，示范素材可见 |

用户随后明确本阶段只需确保本次 SDK 新功能跑通，真实问答体验由用户后续安装 APK 验证。按此范围，本轮核心功能验收通过；没有本轮真机结论，也未验证完整训练、声音实听、锁屏/通知或系统中断。模拟器首次进入 trainer 时 ADB shell 失去响应；保留数据重启并改用软件图形后恢复，重新点击原卡已进入播放器，无 App 或 SDK 修改。测试结束时该模拟器已停止。2026-10-21 开哥授权合并推送，已以 `f83642eb06260c22cb891931acc02ce908ad538d` 合入 `main`。合并树与已验分支 `193f67d` 完全一致（tree `df972079e5c301aa4244640d4f792855426aed07`），复用本节已绑定源码的 195 项测试与核心冷烟证据；后续状态更新仅改文档。

本机忽略证据：`.buildlog/coach-tools-final-all-tests.log`、`coach-tools-final-analyze.log`、`coach-tools-lock-verify.log`、`coach-tools-smoke-build.log`、`coach-tools-turn-*.json`，以及 `coach-tools-actions.png`、`coach-tools-action-details.png`、`coach-tools-plan.png`、`coach-tools-restored.png`、`coach-tools-player-core.png`。不提交原始设备日志、调试服务地址、密钥或 APK。

## AI 新接口（0.1.0+5，历史待验）

分支 `feat/smartfit-ai-replies`，待验版本 `0.1.0+5`，源码 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`。BaseURL 为 `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`。APK `.buildlog/install/SmartFit-ai-proxy-0.1.0+5-debug.apk`，203,741,474 bytes，SHA-256 `f3ac1f4276f82c629bb254065d5bc3108d4181a5531679fed7a7d2f90d2a14a4`；debug 签名与旧包相同，ZIP/profile 打包检查通过，已覆盖安装并保留旧数据。6 项 endpoint/UUID/header 配置测试及分析通过；旧源全量 180 项本轮未重跑。尚未完成本次验收，合 main 与推送等待新的用户授权。

App 沿用原 App Key 与原设备 UUID，鉴权仅为 `X-App-Key` 与 `X-Device-Id`，不发送 `Authorization`。`tools/coach/build_debug.ps1 -AppKeyFile` 仅用 dart-define 注入本机文件中的 App Key。随机 UUIDv4 首次持久化成功后才启用 AI，存储失败使用本地引擎。每设备 30 次 / 10 分钟限流由服务器执行，429 给出提示并回退本地。

生成计划限定随包 93 个动作并严格校验后才可保存和开练；SDK 对不合格输出最多重写一次，网络超时/最终校验失败回退本地。发送的历史仅为 AI 可见相关轮次与显式当前计划/训练条件，已存计划和训练历史保存在本机、不自动上传。下方记录旧 AI 计划在 `+5` 的局部 UI 保存/开练，不把它或此前 `+2` 完整训练迁移为新地址 AI 生成链路通过。通知可见性、其他系统中断、Play Console 与正式 release 验收待办保持不变。

### 验证来源与源码绑定

以下均为 2026-10-20 本会话实际执行并记录的结果；2026-10-21 文档收束只核对 Git delta，不读取原始日志、密钥或构建产物，也不重新操作手机。`e549e0f84aa9118ef20752b8926c7b8c602a7e0f` 到收束前 HEAD `4cbadb0c5be786d16694ff1e7fbd2f3cb453925c` 仅变更 README 和 4 份文档，因此下列配置测试与静态分析仍适用于相同运行源码。

| 命令 / 方法 | 结果与 source state | 适用性 |
| --- | --- | --- |
| `flutter test --no-pub test/device_identity_test.dart` | 6 项通过；对应 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f` 的提交前同一源码状态 | UUID 与代理配置回归；不把此前全量 180 项再加 6 写成 186 项 |
| `flutter analyze --no-pub` | 无问题；对应上述 `e549e0f…` 同一源码状态 | 后续仅文档变化，可复用；不是本次新执行 |
| `./tools/coach/build_debug.ps1 -AppKeyFile '<本机文件，路径不收录>' -FlutterCommand 'E:\flutter\bin\flutter.bat' -BuildLog '.buildlog/ai-proxy-v5-build.log'` | 成功；脚本执行 `flutter build apk --debug --no-pub` 并以 dart-define 注入 App Key；源码 `e549e0f…` | Windows/PowerShell；单次环境 `PUB_HOSTED_URL=https://pub.dev`、`JAVA_HOME=E:\Android\Android Studio\jbr`。只绑定上方已记录的 `+5` 包，不声称收束 HEAD 重新构建 |
| 调试 VM 延时调用真实 `ChatController`，界面确认；保存/开练/暂停/结束使用 UI 点击，重启后读取持久化状态 | 使用上述 `+5` 包；问答成功、计划请求三次上游失败；旧 AI 计划局部训练及保存结果见下表与下节 | 设备与接口的当时观察；不能代替新接口计划生成成功或完整训练验收 |

旧源 `cc16f530944cf4f6034365aa111528536978ecc3` 的全量 180 项和分析保留为历史记录。该源到 `e549e0f…` 修改了代理配置、关于页、包版本与配置测试；不将旧源全量结果直接写为当前新配置的全量复验。

### 新地址真机观察

| 请求 | 结果 |
| --- | --- |
| 「训练后为什么要慢慢恢复呼吸？」 | AI 正常回答，`outcome=model`，27,722 ms，HTTP 请求 1 次 |
| 第一次 3 分钟计划生成 | 43,447 ms 后回退本地，SDK 错误 `all upstreams failed (tencent:AbortError)` |
| 第二次 3 分钟计划生成 | 41,589 ms 后再次回退本地，同一上游错误；用户确认服务调整完成后重试仍发生 |
| 第三次极简 3 动作 / 3 分钟计划 | 41,952 ms、HTTP 请求 1 次，仍回退本地；同为 `all upstreams failed (tencent:AbortError)` |

三次计划请求均已提示使用本地模板，本地功能继续可用。常规问答通过，新接口计划生成未通过，不能判定本次验收完成。目前不申请合并；待服务器恢复生成计划后再做新地址真机验收，合 main / 推送等待开哥新批准。没有实际连续发送 31 次请求验证服务器配额；429 仅有自动化覆盖“不重试、显示提示并回退”，不写为实机配额已验。

### +5 局部保存与训练 UI

保存的是旧 `+4` 接口生成的原始 AI 计划 `ai-1792509025833151-84572f23`（「办公室肩颈放松」，10 动作），不是新地址生成结果。实际 UI 保存后已存计划 1→2，点击原卡开始 `ugk_trainer`，视频与倒计时正常，暂停后于 34 活动秒提前结束。记录 `sessionId=s-mvgu0k9q-15e74dbd32c5`，`planId` 为上述 AI 计划，`endedEarly=true`、完成 0/10，历史 3→4。

重启后已存计划仍为 2、历史仍为 4，原 AI 计划及该 SessionResult 均保留，原随机设备标识未变，前台服务已释放。2026-10-20 收尾时从抽屉返回原 AI 计划卡，已保存状态可见，没有活动前台服务。本次仅验证局部启动/提前结束和持久化，不记作完整训练、`+5` 声音实听或新地址 AI 计划链路通过，源码和 APK 身份仍为上述 `e549e0f` / `+5`。

问答和计划请求通过调试 VM 的延时 Future 调用真实 `ChatController` 发送，并在 UI 确认文字/卡片；保存、开练、暂停与结束均为实际 UI 点击。本机忽略日志为 `.buildlog/ai-v5-safe-usage.json`、`ai-new-endpoint-tests.log` / 分析日志及 `ai-phone-state.json`，不提交含设备状态的原始日志。

### 旧地址与 +4 历史

旧源 `cc16f530944cf4f6034365aa111528536978ecc3` / `0.1.0+4` 的全量 180 项测试及分析通过；旧地址实机曾约 21 秒成功生成 AI 计划，随后追问回落本地。服务调整中，这条观察不代表新地址或 `+5` 已通过。

旧包 `.buildlog/install/SmartFit-ai-worker-0.1.0+4-final-debug.apk`，229,561,107 bytes，SHA-256 `e2fcb4d54fd10fa7d0d7a10783d751aafb197fbd4285f653a64eaae3f4533446`，仅作历史身份；它使用 `https://ugk-ai-proxy.294851575.workers.dev/v1` 与 `deepseek-v4.1-flash-1017`，不再作为当前最终待验包。

## 后续目录节奏修复与键盘恢复（2026-10-20）

SDK 修复提交 `9407bf3` 将 JSON `source=repSeconds` 识别为派生节奏，其余来源仍为 catalog。新增目录解析、计次完整报数、计时剂量回退 `timedHold` 及其他来源回归；修前 3 失败、1 通过，修后包全量 100 项及分析通过。App 固定新 Git 提交，版本递增 `0.1.0+3`；两仓已经开哥授权依次合入并推送 main；SDK GitHub 全新克隆可获取该固定提交及包目录，App `flutter pub get --enforce-lockfile` 成功，依赖文件无变化。

微信输入法故障时报告已显示，实际 IME 窗口仅 1px；连接重建与输入类型实验未通过真机验证，已全部移除。只重启微信输入法服务后恢复为正常 1136px 窗口，用户以手指收起重开并输入，确认“现在正常”。未清数据、未切换输入法；本轮不是新的 App 输入代码修复。自动化输入可再次触发此状态，后续真机文本检查使用实际软键盘。最终包及检查结果见 [接入记录](ugk-trainer-integration.md#后续修复2026-10-20)。

## ugk_trainer 主线接入（2026-10-20）

`feat/ugk-trainer-integration` 已经用户同意合入并推送 `main`，接入检查点 `04112472a1ab8f07cebc1e7feb00604a56796b56`，App `0.1.0+2`。App 静态分析无问题、156 项测试通过，SDK 保存可靠性修复后 96 项测试通过。Android debug 与 Web release 构建成功；APK 签名/ZIP 完整性与合并 manifest 检查通过，包含一个媒体播放前台服务及 3 项所需权限。Web 有 CupertinoIcons 字体提示，构建未失败。

合并前 SDK `ea00ff7` 已推送至 SDK main，全新 GitHub 克隆可取到固定包目录。修正 `pubspec.lock` 中两个 SDK 包错误的 `0.0.0` 元数据为 `ugk_coach 0.1.2` / `ugk_trainer 0.1.0`，固定 Git SHA 与其他依赖不变；`flutter pub get --enforce-lockfile` 及 23 项接入/存储/语音定向回归通过。合入后的 `lib/`、`android/`、`assets/` 和 `pubspec.yaml` 与真机已测源 `bbf0f6e` 无差异，没有重复构建或更换已测 APK。

新包 `SmartFit-ugk-trainer-0.1.0+2-debug.apk` 本地保存（203,720,356 bytes），SHA-256 `7fd8c50b521090dd9bf60e2a332f266729c44bdab3e10936ff6de8e7bb4d24fd`，versionCode 2、minSdk 24、targetSdk 36。签名仍为同一本机 debug 证书，已按用户安排用 `adb install -r` 覆盖安装，未清数据、未上传。本次包身份、SDK 固定依赖与 Play Console 声明草稿见 [接入记录](ugk-trainer-integration.md)。

随后连接 Android 16 真机：20:51–21:03 自然完成「睡前放松」7/7 动作、每项 2/2 组，活动时间 696 秒，没有跳过或提前结束。用户确认真实出声及锁屏语音正常；后台返回、普通解锁、暂停/继续、单条完整结果保存、旧历史保留、停止并重启 App 后界面读取、服务及唤醒锁释放通过，详见 [本次真机记录](trainer-device-check-2026-10-20.md)。

当前设备通知权限为 ignore，通知可见性未验；来电/闹钟、耳机拔出、完整动作媒体及逐句听感、离线/性能仍未覆盖。Play Console 未提供应用条目/登录入口和演示录屏，声明未提交。用户已同意并完成 SDK 与 SmartFit main 的合并推送；上述待验仍独立保留，不据一轮训练创建 `m3-local-verified`。以下保留的是 M7 主线及更早验证记录。

## M7 主线状态与历史（2026-10-20）

版本、标签与交付包身份统一见 [版本管理与台账](version-management.md)。当前源码里程碑为 `m7-aesthetic-v2`，App 包版本仍为 `0.1.0+1`。

最新合并检查点（2026-10-20）：PR #3 美学 v2 已合入 `main@a5997ef`，里程碑 `m7-aesthetic-v2`。已复验审核源 `7ef80d7`：静态分析 0 issue，全量 144 项测试及 5 项独立复现/无障碍检查通过，动作包校验 0 errors，Web release 与 Android debug 构建成功。原四项必修与一项动效问题已关闭，93 个动作包版本为 1.1.0，浅色媒体已纳入文件清单及索引。合并提交的文件树与审核源完全一致，记录见 [PR #3 本机审核](pr3-local-review.md)。这次只完成合并、主线同步及文档记录，没有安装 APK 或进行真机验收；下文 `m6-input-focus` 的手机输入验收仅适用于当时已安装版本。

随后本地交付最新版 debug 测试包 `SmartFit-m7-d0b1c7e-debug.apk`（228,341,715 bytes），用户确认已取包，尚未反馈本包测试结果。该包来自已测源 `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`，与合并后的 `main@d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` 运行源码及配置一致；不记为从文档提交重新构建。SHA-256 为 `adde572a760e425a0c45779b6d4337eb4d8fdcf1ba59b8e12967913c4e8a10ec`，包版本 `0.1.0+1`，签名与旧版一致。交付只在本机完成，没有上传、发布或再次操作手机。同期 release 尝试受本机 JVM/提交内存限制，未取得可交付 release APK。

下文保留各阶段验收证据；测试项数属于对应版本，不是当前版本的多套重复结果。当前仍须执行下方完整设备清单，不能将取包、debug 构建成功或 M6 输入通过写成 M7 真机验收通过。

## M3–M6 历史检查点

验收日期：2026-10-19（Asia/Shanghai）。接手基线：`main@6c2c1d3`。

最新输入检查点 `m6-input-focus`：小米 Android 16 真机已安装并启动，用户确认输入测试通过。输入框上下留白原先不参与点击，已改为输入控件内部留白；新增 4 项点击、隐藏后重新打开键盘及四行草稿回归，修复前 3 项失败，修复后全量 102 项通过。静态分析 0 issue，Web release 和 Android debug 构建成功，修复版已覆盖安装。USB 调试保持连接；微信输入法当时报告已显示但键盘区域为空，切换到已启用的搜狗输入法后能显示软键盘。没有把“USB 调试导致不弹键盘”或“微信跨设备模式”判定为已验证根因。

本次修复版 debug APK SHA-256：`15b7ded8e1e4aee0afc33d50ef2c816e87ca62538aa53ec4822cf4e2f7d1f0de`。安装使用 `adb install -r`，没有清除 App 数据。设备截图、输入法诊断和构建日志仅保留在本机忽略目录 `.buildlog/`；下文“全部待执行”表格为早期基线，当前仅安装启动及输入获得真机验收，尚不能据此标记完整 `m3-local-verified`。

最新动作包检查点：PR #1 已合入 `main@adafcf9`，标签 `m4-drill-packs`。本机静态分析无问题，44 项 Flutter 测试、语音工具环境回归通过；93 个动作包与公共包校验通过，695 条语音审计 0 失败。Web release 与 Android **debug** APK 构建成功，APK 中检查到 94 个包 manifest、93 个视频、93 个封面和 695 条语音。下文最初的内存不足记录属于 M3 历史，不能据此认定当前 debug 构建仍失败；也不能把 debug 构建记为 release 或真机验收通过。

对话首页 PR #2 本机复验：静态分析 0 issue、98 项测试及独立截图检查通过，Web release、Android debug APK 构建成功。已修复安全入口绕过、保护条件丢失、详情训练与改版保存、键盘/辅助功能和小屏布局问题，完成 360×640 浏览器主流程走查。[完整审核记录](pr2-local-review.md) 含固定 SHA、证据和 APK 摘要。Web 仍只有视频海报且存在字体回退联网；真机、release 签名与完整设备验收保持待办。

本轮完成本机自动化验证与跟练缺陷修复，检查点标签为 `m3-local-tests`。**Android 设备走查及 release APK 尚未通过，M3 完整验收未完成。** `m3-local-verified` 留待下述设备与构建项目全部通过后再打。

同日补做本机 Web 走查，检查点 `m3-web-qa`：Web release 构建成功，最新静态分析无问题，38 项测试通过；具体结果见下节。Android 待验项目保持未验状态。

## M3 环境与验证结果（历史）

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

## M3 修复与自动化覆盖（历史）

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

## Android 完整设备验收清单（M7 仍待执行）

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
