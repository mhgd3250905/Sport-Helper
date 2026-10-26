# AI 训练计划 App · 需求理解与参考仓库评估报告

- 日期：2026-10-18（CST）
- 范围：只读调研。两个参考仓库仅在本项目 `refs/` 下 clone 阅读，未做任何写操作（未 push / PR / issue / 改设置）；未建新仓库、未写业务代码。
- 读取版本：3D-Pose-Hub `main@a727ce9`（docs: align onboarding with HD production and QA evidence）；HipLab `main` 浅克隆（pubspec `0.3.6+11`）。

---

## 1. 需求复述

### 1.1 一句话
用户用自然语言（或几个选项）描述训练场景 → App 生成**规范、可执行**的训练计划 → 计划以「训练小组」形式展示，每个动作直接播放预渲染动画 → 一键进入跟练（计时/计次、组间休息、换侧、语音播报）。

### 1.2 MVP 范围（建议）
1. **场景输入**：结构化选项为主 + 一句话描述为辅（MVP 用关键词/规则解析，不调用 AI）。维度：目标（拉伸放松/柔韧/力量/核心/热身/冷身）、场景与器械（办公室/居家徒手/弹力带/哑铃…）、时长（5/10/15/20/30 分钟）、水平（入门/基础/进阶）、重点部位、需避开的部位。
2. **模板生成器**：一组自定义常规模板（见 4.4），模板 = 结构骨架（热身→主训练→冷身）+ 槽位规则（按标签从动作库选动作）+ 剂量规则（按水平给组数/次数/时长/休息）。输出统一的 `TrainingPlan` JSON（与 AI 共用 schema）。
3. **计划展示**：按训练块（小组）列出动作卡，卡片内循环播放预渲染动画（封面先显、视频首帧接管），显示剂量（3 组 × 12 次 / 每侧 30 秒）、要领 1–2 条、可替换动作。
4. **跟练播放器**：准备 → 动作 → （换侧）→ 组间休息 → 下一组/下一动作 → 完成；支持暂停/跳过/上一项、计时与计次两种模式、语音播报（预生成音频）、屏幕常亮、疼痛反馈降级（复用 HipLab 思路）。
5. **安全**：首次进入安全图卡（孕期/术后/急性伤痛→只浏览不生成）、免责声明。
6. **本地优先**：离线可用、无账号，本地保存最近计划与完成记录。
7. 平台：先 Android，iOS 同代码库跟进（Flutter）。

### 1.3 进阶范围
1. **AI 生成**：接入 LLM，提供「动作库 Skill」（动作清单 + 规则 + 输出 schema 的提示词包），AI 只能引用库内动作 ID，输出经校验后进入同一套展示/跟练流程；失败回落到模板。
2. 对话式微调（"换成不需要器械的""再短一点""膝盖不舒服"）。
3. 多日/周期计划（一周 3 练、渐进加量）、训练记录驱动的进阶。
4. 网页版（Flutter Web 或独立 Web，复用同一 schema 与素材）。
5. 英文界面与英文语音。

### 1.4 暂不做（MVP）
账号/云同步、社交、付费、健身房大型器械动作、饮食、实时姿态识别（摄像头纠错）、可穿戴设备、康复/医疗处方、App 内 3D 实时渲染（只播预渲染视频）、AI 自由文本语音（运行时 TTS）。

### 1.5 待确认的关键问题（附推荐答案）
| # | 问题 | 推荐答案 |
|---|---|---|
| Q1 | 技术栈与平台 | **Flutter，先 Android 后 iOS**，与 HipLab / FlareLab 同栈（Flutter 3.44.7、Dart ^3.12.2），可直接复制其媒体播放、语音、存储模块。 |
| Q2 | 首发人群与动作范围 | **居家 + 办公室；徒手 / 椅子 / 墙 / 弹力带 / 哑铃；拉伸放松 + 基础力量 + 核心**。不含健身房器械与托马斯/Breaking 高难专项（后者做成进阶模板包）。 |
| Q3 | 素材从哪来 | **新 App 作为 Pose-Hub 第三个消费方**：按固定版本 lock 取成片；现成 46 条先用，另向 Pose-Hub 提需求发布 v0.3.0（补齐 MVP 子集，统一 soft-v1、1080/720）。渲染仍由开哥本机 4080 主线维护方负责，新 App 不自己渲染。 |
| Q4 | AI 阶段的模型与后端 | **自建 Cloudflare Worker 代理**（不在 App 里放密钥），默认接 **DeepSeek**（国内可用、便宜、支持 JSON 输出），保留切换到 OpenAI / Claude / 通义的适配层。 |
| Q5 | App 名称与包名 | 需你定。占位建议：中文「AI 训练计划」、包名 `com.ugk.<名称>`，沿用 ugk 家族视觉（石墨底 + 一种主色）。 |

---

## 2. 3D-Pose-Hub 摸排

### 2.1 定位与技术栈
- 定位：FlareLab（托马斯训练助手）与 HipLab（开胯训练助手）共用的**动作库与渲染工厂**，2026-10-17 从 3D-Body 迁出。动作规格、人物模型、渲染工具、成片清单的唯一来源；App 只按发布版本取成片。
- 技术栈：Node（three 0.170.0、lucide、vite 7.3.6）+ Python 3（numpy/scipy/Pillow 渲染合成，媒体脚本仅标准库）+ ffmpeg(libx264) + Playwright/Chromium 无头渲染（GPU：Windows ANGLE D3D11；无 GPU 时使用 CPU 软件渲染后端）。
- 渲染方式：每个动作一个 JS spec（程序化关键帧 + IK 求解 + 肌群高亮 + 相机/阴影/QA 约束）→ 浏览器 three.js 场景逐帧渲染 → 合成绿幕/透明母帧 → 派生深色 H.264 成片和封面。
- 人物模型：`training-human-v2@2.0.1`（Snow 派生卡通人物 + 灰色人台头，13 个固定源 SHA-256），新动作必须用该 profile。

### 2.2 目录结构（要点）
```
drill-anim/specs/<id>.js      动作规格（183 个，含 10 个 -r2/-r3 修订）+ 4 个共用模块 _*.mjs
drill-anim/page/ lib/ tools/  浏览器求解/着色、Node/Python 渲染合成、QA、HD 制作工具
drill-anim/models/            training-human-v2.json（模型清单）
drill-anim/themes/            glow-b（方案 B）、glow-soft（soft-v1，HipLab 新成片）、outfit-sand/teal
drill-anim/data/drills.json   FlareLab 51 动作元数据（唯一一份带要领/剂量/安全文案的数据）
drill-anim/data/home-pr-candidates.json  新动作 spec 哈希登记
runtime/                      渲染用 3D 场景（index.html、src/、public/coach、public/anatomy）
tools/                        人物制作：blender/、mannequin/、cloth/、face/
media/manifest.json           成片清单（schema pose-hub/media-manifest@1），releases 0.1.0 / 0.2.0
media/tools/ingest|pack|sync.py  入库 / 打包 / App 同步（sync.py 单文件可复制到 App）
media/inventory/              本地就绪但未发布的批次登记（PR5+PR6 14 条）
docs/drill-catalog.md         自动生成的动作总表；docs/consumers.md App 接入说明
licenses/                     three(MIT)、lucide(ISC)、Drill-media-ATTRIBUTION.md
```

### 2.3 动作数量与分类
去掉修订版后共 **173 个动作 ID**，其中 6 个 `a-*` 是自测对比静图，**可用于训练的 167 个**。

| 系列 | 数量 | 内容 | 器械 |
|---|---:|---|---|
| FlareLab 肌群 `<肌群>-A/B/C` | 51 | 17 肌群 × A 徒手 / B 家用 / C 健身房，偏力量与支撑（Breaking 托马斯向） | A：垫；B：弹力带/哑铃/平行杆/瑞士球；C：绳索/器械/双杠/吊环/GHD |
| `s-*` 拉伸 | 8 | 90/90、蝴蝶、4 字、青蛙、半跪屈髋、蜥蜴、鸽子、坐姿体前屈 | 垫 |
| `t-*` 托马斯专项 | 12 | L 撑、V 撑、分腿支撑、团身俄挺等高难度 | 垫 |
| `o-*` 办公室 | 8 | 坐姿/扶椅拉伸 | 办公椅 |
| `w-*` 久坐强化 | 8 | 鸟狗、死虫、蚌式、臀桥、靠墙静蹲、游泳式等 | 垫/椅/墙 |
| `h-*` 居家补充 | 65 | 核心/全身/臀腿、开胯、开肩胸椎、小器械力量（哑铃 8、壶铃 1、弹力带 4）、徒手后链 | 徒手/椅/墙/毛巾/弹力带/哑铃/壶铃 |
| `n-*` 开胯新增 | 15 | HipLab MVP 专用开胯动作 | 垫/椅/滑垫 |
| `a-*` 自测静图 | 6 | 不用于训练 | — |

按性质粗分（167）：拉伸/放松/灵活性约 70、力量约 60、核心约 25、有氧/全身（低冲击开合跳、登山跑等）少量；部位覆盖全身 17 个肌群 + 小腿、胫前、二头。**明显缺口**：有氧/心肺类很少、下肢单侧力量（弓步类）少、上肢拉类徒手动作少、无跑跳类。

### 2.4 每个动作的数据字段（spec）
以 `drill-anim/specs/h-squat.js` 为例：`id`、`name`（中文）、`nameEn`、`modelProfile`、`timeline.duration`（秒，多为 8s）、`pose`（关键帧/轨道）、`highlight{groups[肌群 id], side, pulseTrack}`、`camera`、`frame`、`stillAt`（封面时刻）、`props`（道具）、`keyFrames`、`qa`（接触/伸直约束）。注释里写了动作描述与节奏（如「2 reps / 8 s：1.5 s 下、0.4 s 停、1.4 s 起、0.7 s 站」），**但不是结构化字段**。

### 2.5 资产格式与体积
| 资产 | 格式 | 规格 | 体积 | 分发 |
|---|---|---|---|---|
| 深色成片 | MP4 H.264 yuv420p、30fps、CRF18、无音轨、faststart、底色 #101013 | 1080×1080，通常 8s/240 帧循环 | 单条 0.32–1.49 MB，均值 0.84 MB；46 条共 38.7 MB | 公开 ZIP（谷歌云盘） |
| 封面 | JPG | 540×540（v0.1.0 为 1080） | 46 张共 0.42 MB | 公开 ZIP |
| 绿幕视频 | MP4 | 1080 | 46 条 82 MB | **仅本地** |
| 透明母帧 | RGBA PNG 序列 | 1080，straight alpha | 46 组 11,220 张，1.88 GB | **仅本地**（可派生浅色底/其他尺寸，无需重渲 3D） |
| 人物/场景 | GLB + JSON | — | — | Git |

发布现状：
- **v0.2.0（published，soft-v1 高亮）只覆盖 HipLab 46 个动作**；ZIP 39.15 MB，SHA-256 `f422c051…c317c772`，App 用 `pose-hub.lock.json` + `sync.py --from-dir` 同步并逐文件校验。
- PR5+PR6 **14 条**（10 条小器械力量 + 4 条徒手后链）HD 绿幕/透明母帧已在开哥本机就绪（local-ready），**未发布**。
- FlareLab 51 的媒体在 3D-Body App 里（720²、旧 v7/glow-B 外观，23 ready / 28 待复核），**未经 Pose-Hub 发布**。
- 其余 **58 个动作只有 spec、没有任何可用成片**（全部 `t-*` 11 个、`w-*` 6 个、`o-*` 4 个、`h-*` 37 个，清单见附录 A）。
- 合计：167 个训练动作中，可直接拿到统一新外观成片的只有 46 个；加上待发布 14 个 = 60；其余需要 Pose-Hub 渲染发布。

### 2.6 元数据完整度
| 字段 | spec（167） | FlareLab drills.json（51） | HipLab 内容包（46） |
|---|---|---|---|
| 中/英名 | ✅ zh + en | ✅ zh + en | 中文；英文名只在语音脚本 `voice_lines.py` |
| 目标肌群 | ✅ 高亮组（17 肌群 id + 左右侧） | ✅ 分组 + 肌群作用说明 | 只有髋部方向（屈/伸/外展/内收/内旋/外旋） |
| 器械/道具 | ✅ props（但词表不统一） | ✅ 自由文本 | 场景 home/chair |
| 难度 | ❌ | ✅ 1–3 | ✅ beginner/advanced |
| 时长/次数建议 | ❌（只有视频时长） | ⚠️ 自由文本「3 组 × 每侧 20–30 秒」 | ⚠️ 在成套训练 step 里：dose 文本 + seconds + sided |
| 视频内节奏（每循环几次） | ⚠️ 只在注释 | ❌ | ❌ |
| 要领文案 | ❌ | ✅ 2 条 cues + 常见错误 + why | ❌（只有一句 note；语音按练法用通用提示） |
| 禁忌/注意 | ❌ | ✅ safety 文本 | ✅ cautions（膝/腰等部位） |
| 替代/降级 | ❌ | ❌ | ✅ alternative（L1 替代） |
| 体位（站/坐/卧…） | ❌ | ❌ | ❌ |
| 多语言 | 名称双语 | 中文（why 偏 Breaking 语境） | 中文；语音中英 |

结论：**动作「看得到」的部分很完整，「怎么练」的元数据严重不足**——只有 51 个 FlareLab 动作有要领/剂量/安全文案，且是 Breaking 语境；其余 116 个缺难度、剂量、要领、禁忌、体位。这是计划生成（模板和 AI）最大的前置工作。

### 2.7 缺口清单
1. 成片覆盖：167 中仅 46 已发布；14 待发布；58 无成片；FlareLab 51 外观/分辨率与新片不一致。
2. 结构化元数据缺失（见 2.6），需新建统一动作库并补字段（AI 起草 + 人工审核）。
3. 词表不统一：器械（垫/椅/办公椅/墙/滑垫…）、肌群（FlareLab 17 组 vs HipLab 方向 vs 面板 id `deltRear/infraspi`）。
4. 视频内动作次数/节奏未结构化，计次模式需要它来对齐语音和动画。
5. 单侧动作只有一侧的成片（HipLab 靠播放器镜像），镜像方案要沿用。
6. 无浅色主题成片（可从透明母帧派生，不必重渲）。
7. 部分动作有已知限制（如 deltoids-B 只到半程土耳其起立、adductors-B 是静态版、6 项有肢体可达告警），入库时要带状态位。

### 2.8 许可证 / 素材来源风险
- 仓库无整体 LICENSE（仓库属你本人，自用无问题；但不能对外声称 MIT）。
- 人物：**Snow Rig © Blender Foundation，CC BY 4.0**——可商用、可改，但**必须在 App 内署名并注明已修改**（HipLab 已有 `assets/licenses/Drill-media-ATTRIBUTION.md`，可复制）。头部参考 Human Base Meshes 为 CC0。
- three.js MIT、lucide ISC（仅渲染工具用，App 不打包则无需）。
- 肌群高亮是教学示意，非肌电数据——文案中需保留这句说明。
- 风险等级：低，前提是保留署名文件。

---

## 3. HipLab 摸排

### 3.1 技术栈与架构
- Flutter 3.44.7 stable、Dart ^3.12.2；Android + iOS；中文界面、深/浅色、中英语音；完全离线、无账号。
- 依赖：shared_preferences、webview_flutter（视频播放）、just_audio + audio_session（语音、ducking、iOS 后台保活）、clock（可测时钟）、wakelock_plus（屏幕常亮）。
- 代码约 10.9k 行：
  - `lib/hip/domain/` 纯规则（模型、自测计分、计划编排、疼痛阶梯、连续天数），全部单测；
  - `lib/hip/control/hip_store.dart` 本地持久化（单 key `hiplab.state.v1`）；
  - `lib/hip/ui/` 页面（安全图卡 → 首页 → 自测 → 结果 → 跟练 → 进度/设置）；
  - `lib/hip/voice/` 语音（阶段台词时间线、播放队列、just_audio 输出）；
  - `lib/core/` 从 3D-Body 复制的公共代码（媒体播放、存储、屏幕常亮）。
- 内容管线：`tools/hip_content/source/`（动作表 CSV、成套训练 MD、自测设计 MD、hip-media.json）→ `build_hip_content.py` → `assets/hip/hip-content.json`（生成文件）。
- 测试：158 项通过/1 跳过（含资源边界测试：内容包引用文件必须存在、drill_media 只能有 hip-* 成对文件）。

### 3.2 动作展示实现
- 视频用 **WebView + 本地 HTTP 资源服务器 + HTML5 `<video>`**：`lib/core/media/scene_asset_server.dart` / `scene_asset_router.dart` 在本机起服务，`assets/drill_media/player.html/js/css` 播放 `hip-<id>.mp4`。
- 体验细节已打磨：Flutter 先盖封面，视频首帧真正渲染后再揭开（requestVideoFrameCallback），无黑框跳变；透明 WebView；fit/align 与封面一致；iOS 内联静音自动播放；后台返回自动续播；浅色主题自动找 `light/` 版本。
- 单侧动作：同一条成片，播放器镜像得到另一侧。
- 优点：已在 Android 16 真机和 iOS 适配验证；Web 分支在 3D-Body 原版里存在（HipLab 删了），将来做网页能直接接回。缺点：每个播放位一个 WebView，列表里多卡同时播放要控制数量（建议只播放可见的 1–2 个，其余显示封面）。

### 3.3 训练中界面 / 状态机
- 计划：`TrainingPlanner`（`lib/hip/domain/hip_session.dart`）按场景+时长选 1–2 套成套训练，按水平替换进阶动作、按自测锁定方向、单侧不对称时紧侧加时；动作间统一 15 s 休息（含下一动作语音预告 + 3-2-1）。
- 阶段：`PhaseKind { prep, work, switchSide, rest, done }`（`lib/hip/voice/session_script.dart`）。
- 时钟：`SessionEngine`（`lib/hip/voice/session_engine.dart`）用**绝对的有效训练时间**驱动固定长度阶段，掉帧/后台不漂移；过期的提示直接丢弃不迟播；支持 skip、replaceFrom（疼痛降级时替换后续步骤）、finish。
- 疼痛阶梯：`lib/hip/domain/hip_pain.dart`——关节夹痛：第一次减幅度 → 再痛换 L1 替代 → 替代也痛则该方向今天只做放松；麻/刺/放射痛立即结束。
- 播放器页面：`lib/hip/ui/hip_player_page.dart`（898 行）：环形倒计时、左右侧指示、阶段遮罩、下一动作卡、暂停/跳过、音频打断处理、预缓存下一条视频、完成/中止页。
- **限制**：全部是**按时间**的练法，没有「组 × 次数」、没有多组循环/超级组、没有计次节奏——新 App 的力量训练需要扩展。

### 3.4 语音播报实现
- **预生成音频，不是运行时 TTS**：`tools/voice/build_voice.py` 用 `edge-tts`（微软神经语音 zh-CN-XiaoxiaoNeural / en-US-JennyNeural）离线批量生成，ffmpeg+numpy 去静音、-16 LUFS 响度统一、-2.5 dBFS 限幅、单声道 AAC `.m4a`。
- 中英各 244 段，共 7.2 MB；`assets/voice/manifest.json` 记录每段时长，用于在时间线上排布台词；另有提示音（start/end/tick/finish）。
- 台词组成：通用短语 + 数字 + 动作名 + 剂量 + 套名 + 提示（`tools/voice/voice_lines.py`），内容行从 hip-content.json 读取；只重新生成改动过的段落（缓存）。
- 播放：`voice_queue.dart`（优先级：count > call > info > coach，过期容忍度不同）、`voice_line_controller.dart` + `just_audio_output.dart`（音乐 ducking、iOS 后台保活静音循环、打断恢复），平台接口可在测试中替换为假实现。
- **对新 App 的影响**：预生成方案只能说「词表里有的话」。模板计划没问题；AI 计划必须把语音限制为「动作名 + 数字 + 固定短语」的组合（结构化输出天然满足），AI 自由文本只做字幕。
- **风险**：edge-tts 走的是微软 Edge 朗读的非公开接口，商用条款不明确。上架商用前建议改用官方 Azure Speech（同一批声音，按量计费，几千段一次性成本约几十元人民币以内）重新生成。

### 3.5 计划 / 课程数据结构
- `hip-content.json`：`drills[46]`（id、name、directions、methods、scenes、level、cautions、alternative、note、media{video,poster,duration_seconds,poster_time_seconds,status}）、`routines[7]`（id、name、audience、scene、seconds、transition_seconds、steps[drill, dose 文本, seconds, sided, alternative, tip]）、`assessment`（6 项自测、权重、等级带、推荐路线）、`safety_cards[3]`、`directions[6]`。
- 7 套：A 办公室 5 分钟、B 睡前 8 分钟、C 晨起唤醒 6 分钟、D 久坐解压 10 分钟、E 训练前激活 7 分钟、F Breaking 开胯 12 分钟、M 椅边 2 分钟。
- 编排规则（`tools/hip_content/source/成套训练.md`）：先动后拉、单侧同侧连做（先右后左）、少换体位（站→坐→跪→卧）、按难度自动替换、按自测加量、按疼痛降级、场景开关——这些规则可直接沿用到新 App 的模板引擎。

### 3.6 模块复用清单
**可直接复用（复制后改包名/前缀）**
| 路径 | 用途 | 备注 |
|---|---|---|
| `lib/core/media/drill_media.dart`、`media_controller.dart`、`media_view.dart`、`media_view_native.dart`、`media_view_stub.dart` | 动作视频播放 | 原样 |
| `lib/core/media/scene_asset_server.dart`、`scene_asset_router.dart` | 本地资源服务 | 原样 |
| `assets/drill_media/player.html` / `player.css` / `player.js` | WebView 播放页 | `player.js` 的 id 前缀规则从 `hip-` 改为新前缀 |
| `lib/core/storage/local_state_storage.dart` | 本地存储 | 原样 |
| `lib/core/platform/screen_awake.dart` | 屏幕常亮 | 原样 |
| `lib/hip/voice/voice_queue.dart`、`voice_line_controller.dart`、`just_audio_output.dart`、`voice_library.dart`、`hip_voice.dart` | 语音队列与输出 | 改名去 hip 前缀 |
| `tools/pose_hub_sync.py` + `pose-hub.lock.json` + `tools/pose-hub-manifest.json` 模式 | 固定版本取素材 | 新 lock 的 ids/命名模板 |
| `tools/voice/build_voice.py`、`audit_voice.py`、`assets/voice/chime/` | 语音生成与审计 | 换 TTS 后端（见 3.4） |
| `assets/licenses/Drill-media-ATTRIBUTION.md`、`NotoSansSC-OFL.txt` | 许可署名 | 必须保留 |
| `test/core/*` | 公共代码测试 | 随代码复制 |

**需改造**
| 路径 | 改造点 |
|---|---|
| `lib/hip/voice/session_engine.dart` | 时钟设计很好，保留；阶段扩展为「组/轮/计次」 |
| `lib/hip/voice/session_script.dart` | 增加 set/round 阶段、组间休息、计次播报（"第 2 组，12 次"）、按视频节奏数次 |
| `lib/hip/domain/hip_session.dart` | PlanStep/TrainingPlan 换成通用 schema；TrainingPlanner 改为模板引擎 |
| `lib/hip/domain/hip_pain.dart` | 从「髋部方向」泛化为「身体部位/动作模式」 |
| `lib/hip/ui/hip_player_page.dart` | 布局和交互作参考，按新引擎重写 |
| `lib/hip/ui/hip_theme.dart`、`hip_widgets.dart`、`hip_icons.dart`、`hip_segmented.dart` | 家族视觉可沿用，换主色/品牌 |
| `lib/hip/control/hip_store.dart` | 持久化模式沿用，状态结构重定义 |
| `lib/hip/domain/hip_progress.dart` | 连续天数/提醒规则可沿用 |
| `tools/hip_content/build_hip_content.py` | 内容管线思路沿用：源表 → 生成 JSON + 校验 |
| `tools/voice/voice_lines.py` | 台词词表重写（力量/组数/次数/通用指令） |
| 安全图卡内容（`safety_cards`） | 扩充为全身版（心血管、高血压等） |

**不建议复用**
| 路径 | 原因 |
|---|---|
| `lib/hip/domain/hip_assessment.dart`、`lib/hip/ui/hip_assessment_page.dart`、`assets/hip/assessment/` | 开胯专用自测；进阶可另做全身评估 |
| `tools/sync_drill_media.py` | 3D-Body 旧同步工具，已废弃 |
| `assets/hip/posters/`、`assets/hip/onboarding/` | HipLab 专用美术 |
| `android/`、`ios/` 工程 | 新包名新建；只借鉴签名回退（key.properties）、本地服务网络安全配置等做法 |
| `assets/fonts/NotoSansSC.ttf`（17 MB 全量） | 复用但建议子集化，减小安装包 |

---

## 4. 新项目方案建议

### 4.1 技术栈
- **App**：Flutter（与 HipLab/FlareLab 一致，可直接搬模块），先 Android 后 iOS；状态管理沿用 HipLab 的简单 store 模式（或 Riverpod，二选一，推荐沿用以降低迁移成本）。
- **视频**：沿用 WebView 播放器（已验证）；列表页只让可见卡片播放。
- **语音**：预生成音频 + 队列（沿用），TTS 后端换官方 Azure Speech。
- **素材**：Pose-Hub 第三个消费方，`pose-hub.lock.json` 固定版本 + sync 校验；App 内建议用 **720² 成片**（约为 1080 的一半体积），首发包 ~60–80 动作约 30–40 MB；全库后续可按「动作包」下载。
- **AI（进阶）**：Cloudflare Worker 代理（你已有 Cloudflare 账号与 Worker 经验）→ LLM；App 不存密钥；Worker 做限流、校验、日志。
- **网页（以后）**：Flutter Web（把 3D-Body 原 media_view 的 web 分支接回）或独立 Web，共用动作库 JSON 和计划 schema。

### 4.2 动作库统一数据模型（`exercise-library.json`）
```jsonc
{
  "id": "h-squat",                 // = Pose-Hub 动作 id，不改名
  "status": "ready",               // ready | review | hidden
  "name": {"zh": "徒手深蹲", "en": "Bodyweight Squat"},
  "category": "strength",          // stretch | mobility | strength | core | cardio | control | relax
  "pattern": "squat",              // squat|hinge|lunge|push|pull|carry|rotation|anti_rotation|isometric|stretch
  "primaryMuscles": ["quadriceps", "glute-max"],   // 统一用 Pose-Hub 17 肌群 id + 补充 calves/tibialis/biceps
  "secondaryMuscles": ["hamstrings"],
  "bodyRegions": ["lower"],        // upper | lower | core | full | hip | shoulder | spine
  "position": "standing",          // standing|seated|chair|kneeling|quadruped|supine|prone|side_lying
  "equipment": [],                 // none 视为 []；mat|chair|wall|towel|band|dumbbell|kettlebell|slider|bar|rings|gym_machine
  "scenes": ["home", "office", "outdoor"],
  "level": 1,                      // 1 入门 2 基础 3 进阶
  "unilateral": false,             // true → 播放器左右各一遍，镜像同一条视频
  "defaultDose": {"mode": "reps", "sets": [2,4], "reps": [8,15], "restSec": [45,90]},  // mode: reps|time|hold
  "video": {"loopSec": 8, "repsPerLoop": 2, "repSec": 4.0, "posterSec": 0},
  "cues": {"zh": ["脚略宽于髋，脚尖微外", "臀部向后下坐，膝盖跟脚尖同向"], "en": []},
  "mistakes": {"zh": ["膝盖内扣、脚跟离地"]},
  "contraindications": ["knee_acute"],          // 受控词表
  "cautions": ["knee"],
  "regressions": ["w-wall-sit"], "progressions": ["h-bulgarian"],
  "alternatives": [],
  "media": {"video": "assets/exercises/h-squat.mp4", "poster": "assets/exercises/h-squat.jpg",
            "poseHubVersion": "0.3.0", "spec": "drill-anim/specs/h-squat.js", "theme": "glow-soft"},
  "voice": {"nameClip": "ex.h-squat", "cueClips": ["cue.h-squat.1"]}
}
```
数据来源合并：Pose-Hub spec（名称、肌群、道具、时长、节奏注释）+ FlareLab drills.json（要领、错误、安全、难度、剂量）+ HipLab 内容包（场景、难度、注意部位、替代）→ 用脚本生成草稿 → AI 补全缺失字段 → 人工逐条审核。源表放 CSV/YAML，构建脚本生成 JSON 并校验（仿 `build_hip_content.py`）。

### 4.3 训练计划 schema（模板和 AI 共用，`TrainingPlan v1`）
```jsonc
{
  "schemaVersion": 1,
  "id": "plan_20261018_xxxx",
  "source": "template",            // template | ai
  "templateId": "home-fullbody-beginner",
  "title": "居家徒手全身 20 分钟",
  "goal": "strength",              // relax|mobility|strength|core|warmup|cooldown|mixed
  "scene": "home",
  "equipment": ["mat"],
  "level": 1,
  "estimatedMinutes": 20,
  "safetyNotes": ["如有关节刺痛立即停止"],
  "blocks": [
    {
      "id": "b1", "name": "热身", "type": "warmup",       // warmup|main|circuit|superset|cooldown
      "rounds": 1, "restBetweenRoundsSec": 0,
      "items": [
        {"exerciseId": "n-pelvis-circle", "mode": "time", "sets": 1, "workSec": 40,
         "perSide": false, "restSec": 10, "tipKey": null, "alternatives": ["h-catcow-quad"]}
      ]
    },
    {
      "id": "b2", "name": "力量循环", "type": "circuit",
      "rounds": 3, "restBetweenRoundsSec": 60,
      "items": [
        {"exerciseId": "h-squat", "mode": "reps", "sets": 1, "reps": 12, "restSec": 20},
        {"exerciseId": "h-incline-pushup", "mode": "reps", "sets": 1, "reps": 10, "restSec": 20},
        {"exerciseId": "w-dead-bug", "mode": "reps", "sets": 1, "reps": 8, "perSide": true, "restSec": 30}
      ]
    }
  ]
}
```
- 跟练引擎把 blocks 展开成阶段序列（prep → work[side] → switchSide → rest → … → done），计次模式时长 = reps × repSec。
- 同一校验器（Dart + Worker 端 TS/JSON Schema）检查：ID 在库内且 status=ready、器械/场景与用户选择一致、剂量在动作 defaultDose 允许区间、总时长 ±20%、禁忌冲突、单侧动作 perSide 正确、热身在前冷身在后。

### 4.4 常规模板建议清单（MVP 10 套）
| 模板 | 时长 | 场景/器械 | 结构 |
|---|---|---|---|
| 办公室肩颈腰放松 | 5 / 10 | 办公椅 | 全程坐/站，`o-*` + 扶椅拉伸 |
| 晨起唤醒 | 6–10 | 居家垫 | 灵活性 → 轻激活 |
| 睡前放松 | 8–12 | 居家垫 | 全程卧姿拉伸 |
| 久坐后链激活 | 10–15 | 垫/椅/墙 | 臀桥、鸟狗、死虫、蚌式、靠墙静蹲（`w-*`） |
| 居家徒手全身力量（入门/基础） | 15 / 20 / 30 | 徒手 | 热身 → 3 轮循环（下肢/推/核心/后链）→ 冷身 |
| 小器械力量（哑铃/弹力带） | 20 / 30 | 哑铃、弹力带 | 热身 → 上下肢超级组 → 冷身（`h-db-*`、`h-band-*`） |
| 核心强化 | 10 / 15 | 垫 | 抗伸展/抗旋转/屈曲组合 |
| 开胯 | 5–15 | 垫/椅 | 直接迁移 HipLab 7 套规则 |
| 开肩与胸椎 | 8–12 | 垫/墙/毛巾 | `h-*` PR115 系列 |
| 运动前热身 / 运动后拉伸 | 6–10 | 徒手 | 动态激活 / 静态拉伸 |
| （进阶包）Breaking/托马斯专项 | 15–20 | 垫/平行杆 | FlareLab 51 + `t-*`，需素材统一后上线 |

模板 = 骨架 + 槽位（如「下肢力量·level≤用户·器械⊂用户」）+ 编排规则（先动后拉、同侧连做、少换体位、按难度替换、按疼痛降级）+ 剂量表（按水平）。同一输入多次生成可在候选中轮换，避免每次一样。

### 4.5 AI 接入设计（进阶）
1. **动作库 Skill（提示词包）**：
   - `system`：角色（保守、规范的训练计划编排）、硬规则（只能用给定 ID、剂量区间、结构顺序、安全边界）、输出必须符合 JSON Schema。
   - `library`：按用户器械/场景/禁忌**先在 Worker 端过滤**，只发送 40–80 个候选的紧凑行（`id|名称|类别|模式|肌群|体位|器械|难度|单侧|剂量区间`，约 40–60 token/行，共 3–5k token）。
   - `templates`：2–3 个示例计划（few-shot），教它结构和剂量风格。
   - 同一份 library + 规则 + schema 也可做成 Hark/Claude Skill，用于离线批量生成和审核新模板。
2. **结构化输出与校验**：用模型的 JSON Schema/JSON mode；Worker 端校验（4.3 的规则）→ 不通过则把错误列表回传让模型修正（最多 2 次）→ 仍失败回落到最接近的模板。App 端再校验一次。
3. **只允许库内 ID**：schema 里 `exerciseId` 用候选 ID 的 enum；校验器二次检查；绝不让 AI 生成新动作名或自由描述动作。
4. **安全边界与免责**：
   - 生成前的安全问卷（沿用并扩充 HipLab 安全图卡）；命中则不生成，只给浏览与就医建议。
   - 输入里出现伤病、术后、孕期、胸痛、头晕等关键词 → Worker 直接拒绝生成并给固定安全回复，不交给模型自由发挥。
   - 系统提示禁止诊断、康复处方、减重承诺；所有计划附免责声明（教学建议、非医疗处方）。
   - 跟练中疼痛反馈走本地疼痛阶梯，不依赖 AI。
5. **成本**：单次生成约 5–8k 输入 + 0.8–1.5k 输出 token。DeepSeek 约 ¥0.01–0.02/次；GPT-4o-mini 级约 $0.002–0.004/次；Claude/GPT-4 级约 $0.02–0.05/次。Cloudflare Workers 免费额度足够早期使用。按设备每日限次（如 20 次）防滥用。
6. **语音**：AI 计划只引用库内动作与剂量 → 语音全部可由预生成片段拼出（动作名 + 数字 + 固定短语）；AI 的说明文字只作字幕/卡片文案。

### 4.6 素材复制清单
| 来源 | 内容 | 方式 |
|---|---|---|
| Pose-Hub v0.2.0 ZIP | 46 条深色成片 + 封面 | lock + `pose_hub_sync.py --from-dir`，命名模板改为新前缀 |
| Pose-Hub（待发布 v0.3.0） | PR5/PR6 14 条 + MVP 子集补渲（见附录 A 优先项） | 向 Pose-Hub 提需求（需你同意后提 issue），主线维护方渲染发布 |
| Pose-Hub `media/tools/sync.py`、`media/manifest.json` | 同步脚本与清单副本 | 复制 |
| Pose-Hub `drill-anim/data/drills.json` | 51 条要领/剂量/安全文案 | 读取转换进动作库（文案需去 Breaking 语境） |
| Pose-Hub `drill-anim/specs/*.js` | 名称/肌群/道具/节奏注释 | 脚本只读解析，生成动作库草稿 |
| HipLab `tools/hip_content/source/` | 动作表、7 套成套训练、编排规则、安全图卡 | 转换为开胯模板与规则 |
| HipLab `lib/core/*`、`lib/hip/voice/*`、`assets/drill_media/player.*` | 播放器、语音、存储 | 复制改名（3.6） |
| HipLab `tools/voice/*`、`assets/voice/chime/` | 语音生成与提示音 | 复制，换 TTS 后端与台词 |
| HipLab `assets/licenses/*` | Snow CC BY 4.0 署名、字体 OFL | 必须复制 |

---

## 5. 工作量与里程碑

### 5.1 MVP 分阶段（按 Hark 在沙箱开发 + 你真机验收估算）
| 阶段 | 内容 | 预计 | 产出 |
|---|---|---|---|
| M0 确认与内容建模 | 确认 Q1–Q5；定动作库模型与计划 schema；脚本合并三方数据生成动作库草稿；AI 补字段 + 人工审核 MVP 子集（约 60–80 动作） | 1 周 | `exercise-library` 源表 + 生成 JSON + 校验脚本；向 Pose-Hub 的素材需求清单 |
| M1 工程骨架 | 新仓库、Flutter 工程、复制 core 媒体/存储/语音模块、lock 同步 46 条素材、CI 跑 analyze/test | 0.5–1 周 | 能播放动作视频的空壳 App |
| M2 生成与展示 | 场景输入页、模板引擎（10 套）、计划校验器、训练小组展示页（循环预览、替换动作） | 1–1.5 周 | 输入→计划→展示闭环 |
| M3 跟练 | 泛化 SessionEngine/Script（组/轮/计次/休息/换侧）、播放器页、疼痛阶梯、完成记录 | 1.5 周 | 可完整跟练 |
| M4 语音与打磨 | 新台词词表、Azure TTS 生成中文语音、安全图卡与免责、深浅色、APK 真机验收 | 1 周 | MVP 内测版 APK |
| A1 AI 接入（进阶） | Worker 代理、动作库 Skill/提示词、schema 校验与回落、限流、对话微调 | 1.5–2 周 | AI 生成上线 |

MVP 合计约 **5–6 周**；AI 进阶再 **1.5–2 周**。素材补渲与 App 开发可并行。

### 5.2 风险
1. **素材覆盖（最大风险）**：统一外观的已发布成片只有 46 个（偏开胯/拉伸），力量类几乎都要等 Pose-Hub 发布；补渲依赖开哥本机 4080 和主线维护方排期。缓解：MVP 先围绕「46 + 14」设计模板，力量模板随 v0.3.0 解锁。
2. **元数据质量**：要领/剂量/禁忌要人工把关，AI 起草不能直接上线；FlareLab 文案为 Breaking 语境需改写。
3. **计次与动画对齐**：视频循环节奏只在 spec 注释里，需要逐条提取 `repSec/repsPerLoop`，否则语音数次与画面不同步。
4. **安装包体积**：1080 全库约 145 MB；需 720 版本 + 字体子集 + 分包下载。
5. **TTS 合规**：edge-tts 商用条款不明，上架前换官方 Azure Speech。
6. **AI 安全与合规**：健康类建议的免责、拒答伤病；国内上架如用境外模型有合规问题（推荐国内模型）。
7. **外观一致性**：FlareLab 51 旧外观/720 与 soft-v1 新片混用会割裂，建议统一 soft-v1 后再纳入。
8. **两个参考仓库持续演进**：复制代码后各自演进，在文件头标注来源 commit（沿用 HipLab 做法）。

---

## 附录 A：58 个只有 spec、无任何成片的动作
- `h-*`（37）：h-banana、h-band-pull-apart、h-bear-plank、h-biceps-self、h-bridge-overhead、h-bulgarian、h-calf-raise、h-catcow-quad、h-chair-dip、h-chair-kickback、h-chair-lat、h-chair-tspine、h-cobra、h-crossbody、h-crunch、h-dd-shoulder、h-forearm-plank、h-incline-pushup、h-inner-thigh、h-mountain-climber、h-open-book、h-pike-pushup、h-reverse-crunch、h-reverse-lunge、h-russian-twist、h-seated-reachback、h-side-er、h-side-leg-raise、h-step-jack、h-tabletop、h-tib-raise、h-towel-behind、h-towel-pass、h-towel-pulldown、h-wall-angel、h-wall-calf、h-wall-pec
- `o-*`（4）：o-seated-catcow、o-seated-twist、o-stand-quad、o-stand-sidebend
- `w-*`（6）：w-bird-dog、w-chair-hip-thrust、w-dead-bug、w-fire-hydrant、w-prone-swimmer、w-wall-sit
- `t-*`（11）：t-flare-side-hold、t-half-straddle、t-lsit-open-close、t-lsit-tuck、t-lsit-vsit-circles、t-lsit-wide、t-seated-straddle-ext、t-seated-straddle-lifts、t-straddle-hold、t-tuck-planche、t-vsit

**MVP 补渲优先建议（约 25 个）**：w-bird-dog、w-dead-bug、w-wall-sit、w-chair-hip-thrust、w-fire-hydrant、w-prone-swimmer、h-reverse-lunge、h-bulgarian、h-incline-pushup、h-chair-dip、h-pike-pushup、h-forearm-plank、h-bear-plank、h-crunch、h-reverse-crunch、h-russian-twist、h-mountain-climber、h-step-jack、h-calf-raise、h-cobra、h-catcow-quad、h-open-book、h-wall-angel、o-seated-twist、o-stand-quad（加上待发布 14 条，即可覆盖居家徒手全身/小器械/核心/办公室全部 MVP 模板）。

## 附录 B：已发布 46（HipLab，v0.2.0）
glute-max-A、hip-flexors-A、h-9090-liftoff、h-adductor-rock、h-band-hip-ir、h-band-leg-out、h-butterfly-active、h-couch-stretch、h-hip-gate、h-knee-hug、h-quad-cars、h-reverse-clam、h-squat、h-sumo-pry、h-supine-twist、h-wall-straddle、n-chair-wiper、n-half-split、n-leg-circles、n-pelvis-circle、n-prone-hip-ext、n-prone-ir、n-seated-ir-drop、n-seated-knee-lift、n-seated-squeeze、n-slider-lateral、n-squat-shift、n-straddle-fold、n-thomas-test、n-wide-fold、n-windshield、o-seated-fig4、o-seated-ham、o-stand-crossreach、o-stand-lunge、s-9090、s-butterfly、s-figure4、s-frog、s-kneel-hipflex、s-lizard、s-pigeon、s-seated-fold、t-seated-straddle-lift-1leg、w-clamshell、w-feet-on-chair-bridge。

本地就绪待发布 14（PR5/PR6）：h-band-pallof、h-band-row、h-db-curl、h-db-floor-press、h-db-lateral、h-db-press、h-db-rdl、h-db-reverse-fly、h-db-row、h-kb-swing、h-bridge-march、h-chair-step-up、h-good-morning、h-superman。
