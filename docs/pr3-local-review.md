# PR #3 本机审核与合并记录

2026-10-20（Asia/Shanghai）。PR：[SmartFit 美学升级 v2](https://github.com/mhgd3250905/Sport-Helper/pull/3)。检查点：`m7-aesthetic-v2`。

## 审核版本与合并

- 首轮源：`d1f0781573544a4294a655280cff93089fcc4a39`。
- 修复后审核源：`7ef80d75331a150b6a258ef3ba0c27832fd1e54b`（`feat/aesthetic-v2`）。
- 合并前目标及 PR base：`6d4eb30fd16172f393d152225d2c725a63f84ad0`。
- 合并提交：`a5997ef7aef2695b24cab3f4b330543bbb2c7027`，第一父提交为上述目标，第二父提交为上述审核源。
- 合并提交与审核源的文件树均为 `029a952876a816ffa72f28def688cd62ba34b1d1`，本机 main 已快进同步。随后只补充本审核记录、验收与交接文档。

首轮提交了[请求修改的审核](https://github.com/mhgd3250905/Sport-Helper/pull/3#pullrequestreview-5580554176)。作者在 `7ef80d7` 修复后，本机完成增量复审并提交[通过审核](https://github.com/mhgd3250905/Sport-Helper/pull/3#pullrequestreview-5581077871)，五条审核讨论均已解决。用户随后明确授权合并；合并前再次确认两侧 SHA、批准状态和无冲突状态一致，没有绕过仓库合并规则。

## 审核问题与修复

| 级别 | 首轮问题 | 复验结果 |
| --- | --- | --- |
| P1 | 浅色媒体未纳入文件清单，索引哈希未更新，校验有 279 个错误 | 封包工具枚举并校验 `media.light`，93 个动作包升级至 1.1.0，186 个浅色文件及索引大小、SHA-256 全部一致，校验恢复 0 errors；规范与设计审计文档已同步 |
| P2 | 暂停后跳过或返回，进度环保留旧阶段进度 | 手动切换后独立同步进度，仍保持暂停；原复现的进度已从旧值正确重置到 0，正式测试覆盖跳过、返回及后续冻结 |
| P2 | 共享开关与选择项丢失无障碍状态 | 恢复 `toggled`、`selected` 与说明语义；标签唯一，语义、指针及 Space 激活每次仅触发一次 |
| P2 | 详情页外层控件隐藏内部“换一个”的语义 | 预览行与替换按钮改为独立控件，语义点击及键盘均可分别操作；预览不会误触替换 |
| P3 | 最后三秒呼吸动画重挂数字，打断滚动 | 呼吸动画只重启自己的控制器，保留数字组件身份，紧急倒计时新旧数字按约定滚动 |

## 本机验证

Flutter 3.44.7 / Dart 3.12.2，Windows 本机隔离工作副本固定在 `7ef80d7`。验证完成后及合并前均复核了远端版本。

| 检查 | 结果 |
| --- | --- |
| `flutter pub get --offline` | 成功，使用 pub.dev，lock 未变 |
| `flutter analyze --no-pub` | 0 issue |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 144 项全部通过，含新增审核回归 |
| 独立复现与无障碍检查 | 首轮原媒体复现 2 项、无障碍补充 3 项全部通过 |
| `python tools/packs/validate_packs.py` | 93 个动作包 + 公共包、695 条语音，0 errors |
| 临时副本重封 | 连续重封及校验成功，第二次产物无变化 |
| Web release 构建 | 成功，使用本地 CanvasKit 构建参数 |
| Android debug APK 构建 | 成功；首次 Kotlin daemon/编译依赖错误后，Flutter 自动重试成功，期间曾出现本机内存不足 |
| 合并校验 | 合并树与已测源树一致；后续文档通过 `git diff --check` |

首轮还完整解码了 93 个浅色视频，均为 H.264 / yuv420p / 720² / 30 fps / 无音轨；93 张封面均为 540²。深浅视频时长一致。修复提交没有改动媒体二进制，因此复审没有重复解码。所有原有动作、剂量、语音及 Snow CC BY 4.0 署名保留。

首轮 360×640 浏览器走查完成安全确认、生成、保存、开始、暂停、跳过、提前结束及深色切换；复审针对修复做了自动化验证。本机忽略目录保存了原始日志、复现脚本与截图；未将 APK、build 产物、密钥、keystore 或 `local.properties` 提交到公开仓库。

## 验收边界

本次没有安装 APK 或操作手机。最近一次有记录的手机安装检查点为 `m6-input-focus`，当时用户已确认的输入验收不能延伸到本 PR。

Web 视频使用既有海报替代层；不能由 Web 或构建成功证明 Android WebView 首帧、浅色视频交叉淡入、镜像、音频中断、触感、帧率、耗电和发热通过。语音人工复听、release 签名与完整设备验收继续按 [acceptance.md](acceptance.md) 执行，`m3-local-verified` 仍未完成。
