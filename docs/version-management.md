# 版本管理与台账

更新日期：2026-10-20（Asia/Shanghai）。本文件是源码里程碑、App 包版本与交付包身份的统一台账；验收证据及待验清单以 [acceptance.md](acceptance.md) 为准，角色与历史交接见 [HANDOVER.md](HANDOVER.md)。

## 当前版本

| 项目 | 当前事实 / 事实来源 |
| --- | --- |
| 主线与合并 | 本机维护 `main`；PR #1、#2、#3 及 `feat/ugk-trainer-integration` 已合入并推送 |
| 当前源码状态 | main 已合入训练接入；后续本地分支 `fix/chat-keyboard-reopen`，运行提交 `aea8791`、App `0.1.0+3`，待开哥同意后合并推送，见 [后续修复](ugk-trainer-integration.md#后续修复2026-10-20) |
| 共享训练依赖 | 本地分支固定 SDK 来源修复 `9407bf3`，尚未发布；单次本机 Git 映射的严格锁解析通过。包版本仍为 `ugk_coach 0.1.2` / `ugk_trainer 0.1.0`；远端 main 基线为 `ea00ff7` |
| 源码里程碑 | `m7-aesthetic-v2` → `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` |
| 上一阶段文档整理前主线快照 | `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7`；后续 HEAD 由 Git 查询，不把本表固定 SHA 写成永远最新的 HEAD |
| PR #3 合并提交 | `a5997ef7aef2695b24cab3f4b330543bbb2c7027` |
| PR #3 已测源 | `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`；合并树相同，至上述主线快照只增加 3 份文档 |
| Android 身份 | `com.ugk.smartfit`，App 名「智能健身助手」 |
| 默认包版本 | `0.1.0+3`，来自 [pubspec.yaml](../pubspec.yaml)：versionName `0.1.0`、versionCode `3`；原完整训练测试包为 `0.1.0+2` |
| 关于页显示 | `0.1.0+3 (MVP)`，来自 [about_page.dart](../lib/ui/about_page.dart) 的独立常量，尚未自动读取包版本 |
| 资源版本 | 93 个动作包为 `1.1.0`；公共包 `_common` 为 `1.0.0`；格式版本仍为 `1`，见 [小包规范](drill-pack-spec.md) 与 [索引](../assets/packs/index.json) |
| 交付状态 | 后续 `0.1.0+3` 最终 debug 包已覆盖安装、未上传；身份及摘要见 [后续修复](ugk-trainer-integration.md#后续修复2026-10-20)，下表保留 `0.1.0+2` 基线 |
| 验收状态 | 后续 App 156 项、SDK 100 项及分析通过；最终 debug 构建、签名/ZIP/版本检查、安装和软键盘输入/收起重开通过。此前 `0.1.0+2` 的完整训练见 [真机记录](trainer-device-check-2026-10-20.md)，其他发布待办保持不变 |

Git 标签、App 包版本与资源版本分别管理。`m7` 不代表 Android versionCode 为 7；用户此前已取的包是 `0.1.0+1`，训练接入测试包为 `0.1.0+2`，后续目录节奏修复测试包为 `0.1.0+3`。构建命令曾尝试覆盖版本号用于 release，但没有形成可交付 release 包，不能登记为已交付版本。

## ugk_trainer 测试包（真机主链路已验）

| 项目 | 记录 |
| --- | --- |
| 文件 | `.buildlog/install/SmartFit-ugk-trainer-0.1.0+2-debug.apk`，本地忽略目录保存，并已覆盖安装到 Android 16 真机 |
| 大小 / 身份 | 203,720,356 bytes；`com.ugk.smartfit`，versionName `0.1.0`、versionCode `2`；minSdk 24、targetSdk 36；三 ABI |
| SHA-256 | `7fd8c50b521090dd9bf60e2a332f266729c44bdab3e10936ff6de8e7bb4d24fd` |
| SDK 固定提交 | `ea00ff7f2a4b7f46274b70708a45b435f269f993`，已合入 SDK main 并推送，远端可获取，见 [接入记录](ugk-trainer-integration.md) |
| 验证 | debug 签名与旧包一致，ZIP/静音素材/通知图标及单份媒体播放服务和权限检查通过 |
| 真机结果 / 未完成 | 一轮自然完成 7/7、696 活动秒；出声/锁屏/后台/暂停/完成保存/重启读取/服务释放通过。通知可见性及其他系统中断未验；Play Console 声明草稿未提交。代码已经用户同意合入并推送 main |

## 源码里程碑台账

日期按标签所指提交的时间换算为 Asia/Shanghai；完整 SHA 指向 commit，而不是 annotated tag 对象。

| 日期 | 标签 | Commit SHA | 成果与验证边界 |
| --- | --- | --- | --- |
| 2026-10-19 | `m1-core` | `6ed0399c0fea3d6f687240f172725cbf6fc70fef` | MVP 动作库、模板、生成器、会话与 UI；不据此认定本机或真机验收通过 |
| 2026-10-19 | `m2-voice-docs` | `b386d032563a94049ce99a48a49e67051896d691` | 早期中文语音与文档；语音数量和资源路径属于迁移前状态 |
| 2026-10-19 | `m3-local-tests` | `7b500abe075dfe7c264d0cf5a4e54d807f3f80dc` | 本机分析、31 项测试通过；当时 release 与真机未通过 |
| 2026-10-19 | `m3-web-qa` | `4e45b7e7aa23f0952bd463b3f85da51e8a0c5417` | 38 项测试、Web release 和浏览器走查；Web 视频仍为海报 |
| 2026-10-19 | `m4-drill-packs` | `adafcf9f1fac259ddc2d5f8b1f8898fa6078c897` | PR #1，93 个动作包与公共包、695 条语音；44 项测试、语音审计及 Web release / Android debug 构建通过 |
| 2026-10-19 | `m5-chat-home` | `3ae70c61170326039d70f303310da36268c3e3a1` | PR #2，对话首页、计划保存复用与视觉；98 项测试及本机构建通过，完整真机验收待办 |
| 2026-10-19 | `m6-input-focus` | `6d4eb30fd16172f393d152225d2c725a63f84ad0` | 输入点击区域修复；102 项测试及本机构建通过，小米 Android 16 安装启动与输入获用户确认 |
| 2026-10-20 | `m7-aesthetic-v2` | `d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` | PR #3，统一控件、动效与浅色媒体；144 项测试、5 项独立检查、资源校验及本机构建通过；完整设备验收待办 |

以上标签均已核对指向，且其 commit 均为文档整理前主线快照的祖先。`m3-local-verified` 尚未创建，须待完整设备与 release 验收通过。本次文档提交沿用 M7 里程碑，不另造发布标签。

## M7 历史交付包台账

| 项目 | 记录 |
| --- | --- |
| 文件 | `SmartFit-m7-d0b1c7e-debug.apk`，仅本机忽略目录 `.buildlog/install/` 保存 |
| 用途 | 用户个人远程测试验证；已取包，未收到本包测试通过反馈 |
| 类型 / 大小 | Android debug，多 ABI（arm64-v8a、armeabi-v7a、x86_64）；228,341,715 bytes |
| 包身份 | `com.ugk.smartfit`，versionName `0.1.0`，versionCode `1`；minSdk 24、targetSdk 36 |
| 构建来源 | PR #3 已测源 `7ef80d75331a150b6a258ef3ba0c27832fd1e54b`；与 `m7-aesthetic-v2` 的运行源码、资源及配置一致，文件名中的主线 SHA 仅标识对应检查点 |
| 文件 SHA-256 | `adde572a760e425a0c45779b6d4337eb4d8fdcf1ba59b8e12967913c4e8a10ec` |
| 签名证书 SHA-256 | `3761270a4764157f0e389014a9e5b800b05403bfddce0f4f7f8c039f6a53bdc7`；与旧版相同的本机 debug 证书，可覆盖安装 |
| 既有包检查 | ZIP 完整性通过；1167 个小包文件与源一致，含 94 份 manifest、93 组深色和 93 组浅色视频/封面、695 条语音；签名校验通过 |
| 未完成项 | 无可交付 release APK；`release` 配置仍使用 debug 签名；未将此包记作真机已验收 |

包摘要及检查结果是 2026-10-20 上一阶段本地交付时的记录，不代表当前 HEAD 重新构建或重新安装该 M7 包。该阶段文档收束未读取构建产物、未重跑构建或上传 APK；当前训练接入包单独记录在上方台账。后续替换文件必须重新记录身份、摘要和验证结果，不能沿用本行摘要。

## M7 历史验证证据与源码绑定

2026-10-20 本机审核在固定源 `7ef80d75331a150b6a258ef3ba0c27832fd1e54b` 完成，来源为上一阶段 [PR #3 本机审核记录](pr3-local-review.md)。

| 命令 / 观察 | 记录结果 | 适用范围 |
| --- | --- | --- |
| `flutter pub get --offline` | 成功，pub.dev，lock 未变 | 固定审核源 |
| `flutter analyze --no-pub` | 0 issue | 固定审核源；至 M7 文档提交 `e8981ee` 仅文档变更，不能泛化到后续训练接入代码 |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 144 项通过 | 同上；不代替设备实测 |
| `python tools/packs/validate_packs.py` | 0 errors | 同上；93 个动作包、公共包与 695 条语音 |
| 独立媒体复现 / 无障碍检查 | 2 + 3 项通过 | 固定审核源上的补充检查；不计入 144 项常规测试 |
| Web release / Android debug 构建 | 上一阶段记录成功 | 固定审核源上的构建观察；原记录未完整列出构建参数，本次不冒充当前 HEAD 的新构建证据 |
| `git diff --name-status 7ef80d75331a150b6a258ef3ba0c27832fd1e54b..d0b1c7ef6198a469a7f0a7cedcaa7c9f2512dbe7` | 仅 `docs/HANDOVER.md`、`docs/acceptance.md`、`docs/pr3-local-review.md` | 上一阶段 Preflight 重新核对，说明当时已有运行源码验证为何仍适用 |

PR #3 合并提交与已测源的树均为 `029a952876a816ffa72f28def688cd62ba34b1d1`。该阶段文档整理期间核对运行源码与配置无差异，并校验文档链接、标签指向、版本字段及差异格式，没有因文档变化重复全量 Flutter 测试。这是 M7 的历史范围；训练接入使用当前上方记录的 156 项测试及独立真机证据。

## 后续版本维护规则

1. 本机维护主线、审核合并与打包；云端仅在明确指派时使用 `feat/*` + PR。3D-Pose-Hub、HipLab 保持只读。
2. 新功能里程碑使用独立 commit + `mN-xxx` 标签；已有标签不移动。文档对齐不自动新增里程碑、公开发布或标记验收通过。
3. 后续新交付包递增 Android versionCode；在 `pubspec.yaml` 维护默认 `versionName+versionCode`，若通过 `--build-name` / `--build-number` 覆盖，必须在包台账记实际值和命令。关于页独立版本常量需同步核对。
4. 每次交付记录源码 SHA、构建命令及环境、包名、版本、类型、ABI、大小、SHA-256、签名类型、交付方式和待验边界；记录的是实际产物，不以分支名、标签或文件名推断包身份。
5. 覆盖安装前核对包名、签名和版本兼容性，保留用户数据。正式 keystore 仅在本机管理，切换证书须另行安排迁移，不能把现有 debug 证书记为正式签名。
6. 动作包版本按 [小包规范 §6](drill-pack-spec.md#6-版本规则) 更新；生成内容通过 `tools/` 重建并校验，不手改生成的文件清单与索引。
7. 新验证结果先写验收记录，再更新本台账的状态和交接入口。APK、build 产物、密钥、keystore、`local.properties` 不入 Git；Snow CC BY 4.0 署名保留。

查询当前主线、里程碑和本台账最近提交：

```bash
git rev-parse HEAD
git rev-parse 'm7-aesthetic-v2^{commit}'
git log -1 --format='%H %s' -- docs/version-management.md
git status --porcelain=v1 --untracked-files=all
```
