# SmartFit Coach Agent v2：+39 接入完成

分支 `codex/coach-v2`，基线 +38 `db1e550a6f863ab170a607f5dac800498c89f040`，上一个独立接入检查点 `1a20badb0c902f04a7ea65c954c94318e75a5930`。本轮三包统一固定到 SDK main `32d2839a4edb6d47e5ffe362215ec1a94b208824`，通过官方 GitHub git 源锁定；trainer 的 coach 传递依赖由受版本控制的同提交 override 统一，不依赖本机 ignored override。

## 会话与卡片

App 原子保存 `jsonEncode(controller.exportSession().toJson())`、SDK 显示消息和 App 显示消息，三个字段分别为 `coachSessionJson`、`coachDisplay`、`chat`，由同一笔本地存储写入。保留 SDK 显示副本，覆盖 SDK 已交付、App 尚在展示延迟时被终止的窗口。完成、节点更新、后台和取消/销毁前保存；开始新对话覆盖为新的空会话快照。

打开有快照的会话调用 SDK `restoreSession(CoachSessionSnapshot.fromJson(...), savedDisplayMessages)`；没有快照的旧存档调用 `restoreHistory`。SDK 恢复的推荐、待答询问和回答状态再同步到显示层。损坏/未知 schema 交 SDK 回落，`snapshotRestoreFallback` 只写诊断日志，不弹窗。App 不读、不写 per-card planState，也不补造账本、来源、候选或计划版本；历史 planState 随旧消息兼容忽略，由 SDK 推断旧存档。

已删除 App 自绘 ActionCard，推荐使用 SDK `CoachRecommendCard`。首帧取动作库同一 trainer standing 资源；名称、难度、器械取可信目录。说明仅在卡片顶部显示一次；颜色和中文字符串映射保留 SDK 默认表面与控件。打开动作进入现有单动作训练；排计划发送原文“请把刚才推荐的动作排成计划。”。

等待气泡沿用 SDK 真实 node 事件的纵向打卡，output 完成后折叠为一行。App 的 Slots、意图/条件继承、模板失败回落和计划 ID 重写已在上个检查点删除。底部面板仍为自适应行数、四格菜单、页面同色背景和减少动效兼容，不改训练页和既有套路卡。

## 配置边界

App 和 SDK 默认值保持当前分支原值；Agent 的重试、超时和上下文阈值不覆盖，客户端 `maxRetries=0`、timeout 120 秒。此次自测和 +39 明确通过四项 `--dart-define` 注入：`SMARTFIT_AI_BASE_URL=https://ai.uuugk.win/v1`、`SMARTFIT_AI_MODEL=deepseek-flash`、`SMARTFIT_AI_AUTH=bearer` 和 `SMARTFIT_AI_TOKEN`。Key 只在运行/构建时从本机外部配置读取，不入仓库或回报。+39 为开哥本人手机专用 internal 内测包，不发布到远端。

## 验证

固定 Flutter 3.44.7，App internal 全量 539 项通过、0 跳过，`flutter analyze --no-pub` 无问题。包括真实官方 catalog 与匿名 HTTPS 下载校验/复用/离线缓存。新完整快照宿主回归 13 项通过，覆盖计划/推荐/问答、choice/form 待答、interrupted、坏快照回落、显示缓存篡改、交付与展示之间的保存窗口及原子写入。SDK 推荐卡宿主回归、默认主题/首帧/回调均通过。

每段真实模型只跑一次，均为 deepseek-flash，无报错、无补充追问：

| 对话 | 耗时 | 调用 | 结果 |
| --- | ---: | ---: | --- |
| 在家徒手20分钟练核心 | 15.400 秒 | 6 | SDK 准入 20 分钟计划卡 |
| 换一套，缩短到10分钟 | 19.085 秒 | 5 | 同一 plan_id 的新版本，目标 10 分钟，主体新动作比例 100% |
| 推荐几个拉大腿内侧的动作 | 6.964 秒 | 3 | SDK 准入 4 个推荐动作 |
| 终止进程重开后：把这几个排成15分钟 | 10.614 秒 | 4 | SDK 快照恢复推荐，计划包含原推荐全部 4 个动作，目标 15 分钟 |

第三段完成并 flush 后，测试编排仅终止自己启动的 Flutter 进程树；第四段从全新进程、全新 ChatController/Agent/AppStore 读取磁盘文件，核验保存字节 SHA 不变、进程 ID 不同，随后再发送第四段。恢复首包 roles 为 system/user/user/user，没有历史 assistant/tool/reasoning。没有操作 Android 手机，不将此结果称为真机验证。

证据根目录：`E:/AII-3D/3D-Sport-AI/deliveries/coach-v2-plus39-sdk32/`。`all-tests.log`、`analysis-final.log`、`live/summary.json`、`live/process-restart.json`、`live/restart-restored.json` 和逐请求元数据保留；不记录密钥。构建后的源码 SHA、APK 名称/字节/SHA、签名、16KB/JNI 与 SDK 锁定以 `release-apk.json` 为准。

`main` 和 `release/1.0` 未操作，不推送、不合并；等开哥真机确认后再安排 main。旧 adbc908 的换套拒绝后旧卡重交负向探针另有历史报告，本轮未在 App 绕行；本轮四项实际路径均通过。
