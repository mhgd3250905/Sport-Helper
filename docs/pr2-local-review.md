# PR #2 本机审核记录

日期：2026-10-19，Windows / Flutter 3.44.7 / Dart 3.12.2。

审核对象：[Sport-Helper PR #2](https://github.com/mhgd3250905/Sport-Helper/pull/2)，`feat/chat-home → main`。PR #1 已先合入，随后将本 PR 的 base 从 `feat/drill-packs` 改为 `main`。

- 云端原始 `headRefOid`：`38e2f1e30288d378eeb32f1817f73ea720bc6b0a`。
- 审核时目标分支实际 `targetHeadOid`：`adafcf9f1fac259ddc2d5f8b1f8898fa6078c897`。
- 改 base 后 PR 报告的 `baseRefOid`：`adafcf9f1fac259ddc2d5f8b1f8898fa6078c897`。
- 两侧共同祖先：`67a4ac4073a1172b6526eb2500ca583f9dcea5f1`，包含 PR #1 本机修复。目标 main 仅多出 PR #1 的合并节点，兼容性检查覆盖当前目标。

以下修复在本机隔离工作副本完成，进入 PR 源分支后重新核对源、目标 SHA。最终源 SHA 与验证结论同时记录在合并提交正文中。

## 查实并修复的问题

| 级别 | 复现与影响 | 修复与回归证据 |
| --- | --- | --- |
| P1 | 首次安全对话未完成，抽屉 → 自定义计划/模板仍可生成并开始；重新确认时旧卡片、详情和抽屉也可开始 | `AppStore.trainingAllowed` 统一要求确认完成且未阻止；复查立即撤销并持久化旧确认，取消此前在途回复。`test/safety_gate_test.dart` 覆盖首启、复查、重启及异步竞态 |
| P1 | 输入“膝盖不太好，在家20分钟练臀腿，徒手”，保存/调出后“难一点”会失去保护条件；腰、肩、手腕同样受影响 | 可选 `TrainingPlan.avoid` 随 JSON、复制、保存和复用保留；校验合并计划及请求条件。`test/chat_constraints_test.dart` 覆盖四部位、调时、替换和重启 |
| P2 | 从对话卡片的详情开始，绕过对话的开始/结束回调，不能按该入口生成总结 | 详情返回实际计划，由对话统一进入跟练。`test/chat_details_test.dart` 验证返回对话、历史、最近计划及主题切换保留状态 |
| P2 | 详情手动换动作后沿用旧 ID，结束后保存会指向原卡片，已存原版与改版混淆 | 成功替换生成新版本 ID，开始时持久化实际训练卡片。`test/chat_started_snapshot_test.dart` 覆盖原版与改版同时保存、保存提示重启后使用 |
| P2 | 自绘按钮只有手势事件，Tab/Enter 无法激活；浏览器中名称重复，开场按钮还混入整段免责声明 | `SfPressable` 增加焦点与激活行为，禁用按钮跳过，并显示键盘焦点；独立语义节点保留辅助功能点击并去掉重复名称。`test/chat_controls_regression_test.dart` 覆盖 Tab/Enter/Space、名称和语义点击，浏览器复验名称正确 |
| P2 | 640×360 空计划抽屉溢出 87 px；真实内置字体下 360 px 动作库溢出 0.105 px | 抽屉上部滚动，动作卡按方形图片和缩放文字计算高度。上述回归覆盖 320/360 宽、1.0/1.3 文字缩放；截图脚本通过 |

变更保留离线规则引擎，没有接大模型或新增 pub 依赖。动作包、原始视频、语音时间线、原生播放器核心及 Android 配置与目标 main 无差异。Snow CC BY 4.0 署名及 Noto Sans SC OFL 许可保留。

## 验证

- `flutter analyze --no-pub`：0 issue。
- `flutter test --no-pub --concurrency=1 --reporter expanded`：98/98 通过。
- `flutter test test_screens/shots_test.dart --no-pub --update-goldens`：1/1 通过，使用内置字体，`SF_SCREENSHOT_DIR` 指向临时目录；未覆盖文档历史截图。
- `python -m unittest tools.voice.test_build_voice -v`：1/1 通过；`pubspec.lock` 与原提交一致。
- `flutter build web --release --no-pub --no-web-resources-cdn`：成功。
- `flutter build apk --debug --no-pub`：成功；单次 Gradle JVM 限制 1536 MB、工作线程 1。APK 为 191,462,404 字节，SHA-256 为 `508a069f2ec0405f4dbb5ecab9189f647cca561dd03aa55354400ef83b8d440c`。ZIP 实查含 94 个包 manifest、93 个视频、695 条语音及内置 Noto Sans SC；字体 SHA-256 与源文件一致。APK 仅保存在本机忽略目录。

浏览器使用独立 Chrome 会话，实际主入口及本机 release 产物，360×640：

| 流程 | 结果 |
| --- | --- |
| 首启安全 → 模糊描述 → 核心 → 20 分钟 | 四项安全回答后生成；只追问目标和时长两次，缺省徒手有说明 |
| 保存、卡片开始、暂停、提前结束 | 卡片展开到全屏；自然进入训练及下一动作休息；暂停前后间隔 1.5 秒，计数与进度相同；提前结束记录 1/10，返回对话显示相同总结 |
| 语音 | 第一段走查 41 次 play 成功，33 次观察到时间推进，无播放拒绝；刷新后的最终构建也有播放及时间推进，无错误。未做人工实听 |
| 刷新、复用及外观 | 刷新保留确认、1 套已存计划及历史；“上次那个”调回原计划；浅色、跟随系统及抽屉启动均可用，主题切换保留状态 |
| 重新安全确认回答“是” | 显示相应停止/咨询建议；从抽屉点已存计划的开始仍留在对话，没有新增训练历史 |
| 错误与限制 | 控制台 0 error，运行时错误列表为空。尽管内置常用字字体，仍观察到 `fonts.gstatic.com` 回退请求，Web 预览不能宣称完全离线 |

本机截图：[小屏卡片](screenshots/pr2-local-card-small.png)、[小屏浅色暂停](screenshots/pr2-local-player-light-small.png)。截图展示的是 Web 海报，不代表原生视频验收。

## 合并判定与边界

GitHub 当时没有既有 review、评论、状态检查或分支保护规则。本机审核与 GitHub review 是不同记录，没有冒充提交 GitHub review。已查实问题修复并通过相应验证后再合并，不使用管理员绕过。

Web 当前仍是视频海报替代层，不能证明 Android WebView 视频、镜像或系统音频焦点通过。真机未连接；来电、锁屏、拔耳机、耗电发热、字体实际观感与语音人工复听继续待验。release 仍使用已知的 debug 签名配置，正式 keystore 和 release 验收不在本次 PR 合并完成条件内；`m3-local-verified` 保留待办。没有向参考仓库写入，没有提交密钥、keystore、local.properties、APK 或 build 产物。
