# 生成卡 v2：+45 候选记录

分支 `codex/task-bubble-v2`，基于已验收并推送的 +43 main `94e924fe287770f56d4e8ceeedd521e2871267da`，版本 `0.1.0+45`（internal arm64 2045）。交接中旧 31fd3f0 基线已由开哥明确更正；+44 属于独立 guide-lite，两个候选互不依赖。三包与 coach override 固定 `b490eec43b408a8a35ce81a7830833bc6a3ff278`，整份 pubspec.lock 不变。

## 实现与边界

生成卡按批准数值重做：44px 圆球、300° 渐变光环、10px 呼吸光点、现有 alphaThumbnail 剪影轮换、状态上移交错切换与扫光、四段进度和来源胶囊。卡片使用现有 SfPalette.surface，含指定 .5px 边框、浅色双阴影与半径160的氛围光。删除三点组件及 token，保留其它 generation key，新增 generation-core/check。

App 内不新增“减少动效”开关。正式交付使用完整动效，八张截图均为正常动效下的有限时间取样；保留系统 MediaQuery 无动画环境的静态回落测试，不将其作为交付截图场景。

`CoachDeliveryTransition` 只延后展示：回复结束即具备消息、当前计划和持久化结果；视觉完成240ms、停留350ms、收起300ms（高度 easeOutCubic，透明度200ms easeInCubic），共890ms后才挂载计划卡。取消占位保持44×44，完成时隐藏文字。新请求、会话切换、页面离开或后台立即结束视觉交接。失败/普通文字回复保留基线300ms交叉淡化与高度过渡；取消仍直接移除生成条目，均不进入成功打勾流程。没有业务 Timer 或延迟数据保存。

SDK 的 output.done 事件不提前代表成功回复已完成。等待期间保留原SDK阶段与“马上就好”文案，完成勾由成功交接的 UI 标记触发；独立的非等待组件仍能按原SDK完成事实显示勾。阶段函数与数据内容不变。

SDK 的 CoachAppear 入场祖先会在入场结束时切换树形结构。App 用每个 delivery ID 对应的稳定 UI key 保留同一个交接状态，避免快速回复时被祖先重建提前跳过890ms；key随当前消息/会话清理。SDK 源码与公开接口不改，阶段判断、状态文案数据源、参数映射、取消逻辑和最终计划卡内容不变。

生产改动限于 `coach_task_bubble.dart`、`ui_polish_tokens.dart`、获授权的 `coach_delivery_transition.dart` 与 `chat_home_page.dart` 必需的 UI 标记/身份；另更新版本、回归测试及本记录。未修改 ChatController、AppStore、模型提示、SDK 仓库或 release/1.0。

## 本机验证与产物索引

固定 Flutter3.44.7；最终全量 **690/690 通过、0 跳过**，`flutter analyze --no-pub` **0 问题**。原始结果由交付目录 `flutter-test-full.log`、`flutter-analyze.log` 和 `validation.json` 记录。覆盖 A 光点、B 剪影轮换、C 进度、完成勾及44px占位、320px宽1×/1.5×中文标题、系统减少动效中途切换零运行Ticker，以及即时数据、精确890ms、离页/会话切换/新轮无残留动画；完成阶段保留400ms填充，失败/普通回复保留原300ms过渡。

| 事实源 | 路径（相对项目公共目录） |
| --- | --- |
| 本轮独立证据目录 | `deliveries/task-bubble-v2-plus45/` |
| 最终源码与 APK 绑定 | `release-apk.json`、`package-metadata.json`、`delivery-status.json` |
| 自动化与范围核对 | `validation.json`、`final-checks-exit.json`、`git-scope-observation.json` |
| 浅/深四状态原图 | `screenshots/task-bubble-{a,b,c,d}-{light,dark}.png` |
| 实际组件截图来源与数值 | `screenshot-source.json`、`screenshots-validation.json`、`capture-matrix.csv` |
| 原型对照 | `reference/prototype-{a,b,c,done}-settled.png`、`prototype-comparison.json` |

原型为双列网页，候选为390×844逻辑尺寸、DPR3、App真实字体和资源的单主题实际组件渲染。原型 B/C 图片虽加载但透明度为0；候选按文字要求显示真实、校验过的 alphaThumbnail。原型完成动画中提前出现计划卡的行为以开哥最新890ms交接要求为准。原型 CSS 的勾缩放260ms以最新240ms完成视觉要求执行。上述是明确的文字/补充优先规则，没有自行调小字号、间距或动效。

构建要求：internal arm64 release、同 +43 签名、实际2045、ZIP/ELF16KB、存储JNI、219官方动作/438图片和源码指纹门禁均由实际 APK 回执核对。源码提交与截图/打包提交一致；外部回执生成不改动源码工作树。候选保留本地未合并、未推送、未打 tag，交开哥真机验收。本轮不操作设备，不据软件图推断安装、性能或真机视觉通过。
