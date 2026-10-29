# +41 补充接入：SDK 488ce82

本次并入既有 `codex/ui-polish-1`，保持 `0.1.0+41`，internal arm64 原生构建号仍为2041。SDK远端main已核实为 `488ce82b9dc7031925ba12c18f252b4e596e7776`；三包声明、解析锁文件及coach传递override均固定该完整提交，版本仍为coach0.8.0、coach_ui0.4.0、trainer0.6.0。除三个SDK来源外，其他锁定依赖未变。

依据固定提交的 `packages/ugk_trainer/docs/training-ux.md` 接入，不修改SDK仓库、缓存源码或其组件实现。旧 +41 / c6369c4 交付与40张截图完整保留，新的交付目录为 `E:/AII-3D/3D-Sport-AI/deliveries/ui-polish-1-plus41-sdk488/`；本说明替代首包中关于推荐卡、训练页和动作库仍待样式统一的状态。

## 入口和训练记录

| 入口 | 本次实际接入 |
| --- | --- |
| 正式动作库卡片 | 继续使用SDK `PoseHubActionBrowser`，SDK内部明确传 `TrainerStartMode.preview`；App绑定公开 `onCompleted` |
| 对话推荐单动作 | `showExerciseDetails` 给 `PoseHubSinglePracticePage` 明确传 `startMode: TrainerStartMode.preview`，训练路由按 `SessionResult` 接收返回值并绑定 `onCompleted` |
| 整套计划的▶ / 开始 | `PlayerPage` 明确传 `TrainerStartMode.training`，保留原准备倒计时与训练导航，不插入预览 |
| 完成页反馈 | `AppServices.recordTrainingCompletion` 接收SDK完整 `SessionResult`，将可空 `feeling` 写入同 `sessionId` 的摘要与完整训练记录，记录结构化 `training.completion.feedback` 日志 |

预览不启动训练计时、不保存记录；单动作点开始后按SDK进入10秒准备，并保留媒体实例。整套计划继续使用 `onFinished` 自动保存，再由 `onCompleted` 更新同一条记录。串行保存保证重试和重复完成回调不会产生第二条训练；迟到的无感受自动保存不会抹掉已经选定的感受。

`HistoryEntry.feeling` 使用SDK枚举 `easy / justRight / tired / uncomfortable`，未选为null，旧记录没有此字段也能读取。日志仅接受这四个固定枚举及 `unselected`，保存失败记录固定错误类型并重新抛给SDK，保留其原完成页重试机制。反馈没有接入教练、推荐、记忆、聊天状态或后续模型输入。

SDK单动作旧兼容回调 `PoseHubPracticeResult` 只有actionId、activeDuration、trainingDefinitionComplete，没有sessionId或完整SessionResult。因此单动作以 `onCompleted` 最终回执持久化；不从时间或动作猜ID，也不将旧回调另造记录。该兼容入口的自动保存局限不等同于整套计划的自动保存路径。

## 样式归属

推荐卡使用SDK `CoachUiStyle.fromTheme` 的默认颜色、字体与空builders，仅提供固定中文文案和可信动作模型/素材。不再注入SF的surface、媒体、pressable等样式hook。正式动作库直接使用SDK浏览器的新卡片；旧目录fallback也改为公开 `CoachRecommendCard`，不在App复制SDK私有卡片。

训练主题基于SDK浅/深默认主题，只映射既有品牌主色和字体，保留SDK `cardSurface`、`cardBorder`、`primaryForeground`、背景及其他默认样式。`PlayerPage` 移除App静态天空和自绘完成庆祝hook，训练、要领、完成列表、感受选择均由SDK渲染。既有媒体加载和动作问题记录属于功能适配，仍沿用SDK传入的主题与播放状态；没有新改视频、裁剪、机位或旋转。

SDK488已补齐正式动作库与推荐卡的连续底色、圆角20、间距12、两行标题和底部标签规范。原第一批的第二项按钮固定位置/实际卡面overhang裁剪、第五项受控原地展开/复用私有展开列表，SDK公共接口仍未提供完整支持，继续保留为SDK待办。

## 验证和交付

固定Flutter3.44.7 / Dart3.12.2，官方源和现有缓存。全量测试开启488缓存目录下官方catalog和匿名HTTPS smoke；最终全量、分析、严格锁文件结果见新交付目录回执。定向测试覆盖两个单动作入口的preview与媒体State保留、整套training、四种感受及未选、同ID持久化/重载、失败重试、旧数据、SDK样式默认值及反馈不进入AI。

最终 App internal 全量 **598/598通过、0跳过**，`flutter analyze --no-pub` **0 issue**，离线严格锁文件通过。原0–6最新截图2/2、新训练UX截图2/2通过；旧+40 before20张逐字节保留、最新after20张、新增训练18张，共58张PNG及两个当前harness哈希已逐项核对。训练UX实际完成回调保存并重载 `justRight` 后，history/session各仅一条同ID记录。

SDK升级后的完成页通用文案不再作为是否完整完成的判据。旧断言改为检查真实 `SessionResult.full / endedEarly / ItemStatus`、完成数量、不适事件及同ID只保存一次；没有恢复被移除的SF天空或完成页样式来迁就测试。

APK及源码指纹、实际aapt身份、同签名、16KB/ELF/JNI门禁见 `release-apk.json`；最终源码以其中 `source` 为准。新截图使用实际App/SDK组件和可信图片，原0–6浅深前后图与新增预览/训练/完成/感受软件静帧在新目录 `screenshots/`，不冒充原生视频或真机验收。

| 最终交付回执 | 已核实结果 |
| --- | --- |
| 打包源码 | `c8c64e3868849cf24e6a917a963d50cc63a0195c`；随后仅补文档的提交不替换此源码绑定 |
| APK | `SmartFit-ui-polish-1-sdk488-0.1.0+41-c8c64e3-internal-arm64-v8a-release.apk`，位于本说明开头的新交付目录 |
| 大小 | 143,533,650 B / 136.88 MiB；比SDK1532的同+41 c636首包增加65,632 B |
| SHA-256 | `9fcb1da1b43fd289904bc7113f64d10956c779ae979e177f51cb64a59b3b641b`；已按交付文件实际字节和哈希二次核对 |
| 实际包身份 | aapt `com.ugk.smartfit.internal / 0.1.0 / 2041`，internal arm64 release |
| 门禁 | 与旧+41同签名，ZIP/ELF16KB、存储JNI、严格锁文件、SDK及素材指纹全部通过 |
| 软件验证 | App全量598/598、0跳过；分析零问题；58原图和两截图入口哈希核对通过 |

[截图对照页](../../deliveries/ui-polish-1-plus41-sdk488/screenshots/index.html)及[原图索引](../../deliveries/ui-polish-1-plus41-sdk488/screenshots/README.md)保留全部真实软件渲染证据；训练页面图均附“软件静帧 / SDK站立首帧（非视频）”说明。两主题反馈JSON证明完成后 `justRight` 已持久化并重载，history/session各1条。

本轮不合入或推送App main，不操作release/1.0、不打tag、不安装手机、不新增真实模型调用。App main仍是已推送的+40 `adc79abef2b7195872e589f6225486e944b66644`；+41等待开哥真机确认。
