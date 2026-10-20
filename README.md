# 智能健身助手 SmartFit

描述训练场景 → AI 回复与生成规范训练计划（异常时回退本地模板）→ 用预渲染动作直接展示训练小组 → 跟练（计时 / 组 × 次数 / 休息 / 换侧 / 语音播报）。

主界面是一段对话（[docs/chat-home.md](docs/chat-home.md)）：说想怎么练，助手追问一两句后回一张计划卡片，点「开始训练」直接跟练，「保存」后下次说「上次那个」或从左下角抽屉一键开始。

- 包名 `com.ugk.smartfit`（与 `com.ugk.hiplab` 同族），App 名「智能健身助手」
- Flutter（沙盒 3.47.6 / Dart 3.13，`sdk: ^3.12.0`，与 HipLab 3.44.7 兼容），Android 先行，iOS 同代码库
- 无账号，训练记录和已保存计划保存在本机；WebView 通过本机回环地址播放内置视频。
- 启用 AI 时，输入内容、AI 可见的相关对话、显式当前计划与训练条件经 `https://api.uuugk.win/v1` 发送给 AI 服务，并携带本机随机生成的设备标识；已存计划与训练历史不自动上传。服务器按每设备每 10 分钟最多 30 次请求限流，429 会提示并回退本地；断网、超时或生成结果校验失败同样回退本地模板。

## 版本与验收入口

当前 AI 接入分支 `feat/smartfit-ai-replies`，待验版本 `0.1.0+5`，源码 `e549e0f84aa9118ef20752b8926c7b8c602a7e0f`；接口 `https://api.uuugk.win/v1`，模型 `deepseek-v4-flash-0731`。debug 包已覆盖安装并保留旧数据，6 项接口/UUID/鉴权配置测试及分析通过；旧源全量 180 项测试本轮未重跑。新地址实机通用问答通过，但三次计划生成均因上游 `tencent:AbortError` 回退本地模板，新接口计划生成未通过。`+5` 实际界面已验证旧 `+4` AI 计划的保存、局部启动/暂停/提前结束及重启保留；这不代表新地址生成链路或完整训练通过。待服务器恢复后再验新地址，并等待开哥新的合 main / 推送批准；目前不申请合并。包身份及详细观察见 [版本台账](docs/version-management.md) 与 [验收记录](docs/acceptance.md)。2026-10-21 仅做本地文档收束，验证仍沿用 2026-10-20 对应源码的记录，当前待验状态不变。

旧 `0.1.0+4` / `cc16f530944cf4f6034365aa111528536978ecc3` 的分析及 180 项测试通过；旧地址实机曾约 21 秒成功生成 AI 计划，随后追问回落本地。服务调整中，这些记录不代表新地址与 `+5` 已验证通过。

此前主线为 `0.1.0+3`：PR #1、#2、#3、共享训练接入及 `repSeconds` 来源修复均已合并推送，SDK 固定 `9407bf3`；最近里程碑标签仍为 `m7-aesthetic-v2`。键盘恢复及旧训练证据见 [接入及后续修复记录](docs/ugk-trainer-integration.md)。release 构建、正式签名和完整设备验收仍未完成；`0.1.0+2` 的完整训练不能替代新 AI 包验收。

- [版本管理与台账](docs/version-management.md)：当前版本、里程碑 SHA、测试包身份、版本更新及交付规则的统一入口。
- [本机验收记录](docs/acceptance.md)：各检查点的验证证据、环境和待验清单。
- [ugk_trainer 真机记录](docs/trainer-device-check-2026-10-20.md)：`0.1.0+2` 在 Android 16 上的一轮完整训练、锁屏/后台、保存与重启验证，含未覆盖范围。
- [阶段交接记录](docs/HANDOVER.md)：角色与约束，以及明确标记的历史交接内容。

## 目录

```
lib/domain/      训练领域：exercise / plan(TrainingPlan v1) / template / scenario(描述匹配) /
                 plan_generator(本地模板生成) / plan_validator / session(SDK 计划及节奏适配)
lib/voice/       ugk_trainer 导出入口；App 语言偏好与素材测试适配，训练语音由 SDK 负责
lib/core/        复制自 HipLab（媒体播放 WebView、本地存储、屏幕常亮），文件头注明来源
lib/chat/        对话：ChatEngine 接口、AI 回复与本地规则回退、SlotParser、
                 ChatController（会话、开场安全确认、保存计划、本地历史）、safety_script（免责声明与 4 问）
lib/ui/chat/     对话主界面：星尘背景、色调气泡、计划卡片、已存计划抽屉
lib/ui/          训练计划(训练小组) → 跟练 → 动作库 / 设置；custom_plan_page = 原表单（对话「自己选条件」）
lib/packs/       动作小包读取（与 App 无关，可整体拷走）
assets/packs/    动作小包：每个动作一个文件夹 <id>/{pack.json, cover.jpg, demo.mp4, voice/zh/*.m4a}，
                 公共包 _common/（数字、单位、口令、提示音）+ index.json —— 格式见 docs/drill-pack-spec.md
assets/library/  templates.json（13 套模板，生成文件）
assets/media_player/ player.html/js/css（WebView 播放页）
tools/packs/     build_packs.py（封包、索引、pubspec）、validate_packs.py（校验）、migrate_v1.py（一次性迁移记录）
tools/library/   build_templates.py（模板）
tools/media/     prepare_media.py（Pose-Hub 成片转码 / 绿幕抠像 → 小包 demo.mp4 / cover.jpg）
tools/voice/     build_voice.py（edge-tts + HipLab v4.1 后处理，台词来自小包；商用前换 Azure）、audit_voice.py（逐条检测）
test/            领域测试 + 对话引擎/保存测试 + App 主流程测试；test_screens/ 截图（不随 flutter test 运行；
                 web_shots_main.dart + tools/shots/chat_shots.py 生成 docs/screenshots/chat-*.png）
docs/            评估报告、验收清单、风险、计划 schema、截图
```

## 构建

AI debug 包使用本机 Worker App Key 文件，通过脚本只注入 `--dart-define=SMARTFIT_AI_TOKEN`，不把密钥写入源码或资产：

```powershell
./tools/coach/build_debug.ps1 -AppKeyFile '<本机 App Key 文件绝对路径>'
```

当前模型为 `deepseek-v4-flash-0731`，BaseURL 为 `https://api.uuugk.win/v1`。App 沿用原 App Key 和原设备 UUID，只发送 `X-App-Key` 与 `X-Device-Id` 鉴权头，不发送 `Authorization`。设备 UUIDv4 首次成功持久化后才启用 AI；密钥未配置或设备标识存储失败时使用本地引擎。SDK 对不合格输出最多重写一次，网络超时后回退本地。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release        # 本机工具链及验收状态见 docs/acceptance.md
# 截图（使用内置字体）：flutter test test_screens/shots_test.dart --update-goldens
# 仅检查渲染：设置 SF_SCREENSHOT_DIR 为临时目录的绝对路径，避免改写文档截图
```

## 本机 Web 预览

```bash
flutter build web --release --no-web-resources-cdn
python -m http.server 8766 --bind 127.0.0.1 --directory build/web
```

打开 `http://127.0.0.1:8766`。Web 可验证界面、计划生成、跟练计时、语音和浏览器存储；动作视频目前只有封面，中文字体首次加载可能联网。Web 走查结果与 Android 待验项见 [验收记录](docs/acceptance.md)。

## 数据再生成

```bash
# 动作内容（名称、要领、剂量、台词…）直接改 assets/packs/<id>/pack.json，并升该包 version
python3 tools/library/build_templates.py
python3 tools/media/prepare_media.py --hiplab <HipLab> --green <Drive 绿幕目录>
PYTHONPATH=<edge_tts>:<numpy> python3 tools/voice/build_voice.py build   # 可加 --budget 秒数分段跑
python3 tools/voice/audit_voice.py --raw                                  # 必须 0 失败
python3 tools/packs/build_packs.py --pubspec pubspec.yaml
python3 tools/packs/validate_packs.py --decode
```

## 素材与许可

动作视频来自 Pose-Hub（mhgd3250905/3D-Pose-Hub）：46 条为 v0.2.0 深色成片（经 HipLab 冻结版本），47 条为 Pose-Hub 云盘归档的绿幕母版，本仓库抠像到同色背景。
人物派生自 Blender Studio Snow（CC BY 4.0，署名见 `assets/licenses/Drill-media-ATTRIBUTION.md`，App「关于」页展示）。
3D-Pose-Hub 与 HipLab 只作参考与素材来源，本仓库不向它们写入任何内容。
