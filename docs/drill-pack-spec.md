# 动作「资源小包」格式（drill pack，format 1）

> 2026-10-19 · 分支 `feat/drill-packs` · 工具：`tools/packs/`、`tools/voice/`

一个动作 = 一个文件夹 = 一个「小包」。包里有这个动作在任何 App 里跟练需要的全部东西：元数据（名称、分类、器械、体位、单侧、难度、默认剂量、要领、注意部位、署名）、封面静态帧、示范视频、以及这个动作专属的语音台词（文本 + 预录音频 + 实际解码时长）。数字、单位、通用口令和提示音放在一个共享的**公共包** `_common`，所有动作包都依赖它。

格式与 App 无关：不含 Flutter / SmartFit 的任何概念，路径都相对包文件夹，JSON + 普通媒体文件。HipLab 或以后的新 App 可以直接拷贝包使用。

## 1. 目录

```
assets/packs/
  index.json                 包索引（App 先读它）
  _common/                   公共包（kind=common）
    pack.json
    chime/tick.m4a start.m4a end.m4a finish.m4a silence.m4a
    voice/zh/p.go.m4a … n.1.m4a … n.60.m4a … u.sets.m4a …
  h-squat/                   动作包（kind=exercise），文件夹名 = 动作 id
    pack.json
    cover.jpg                封面静态帧（540²）
    demo.mp4                 示范视频（720²，H.264，无声，循环）
    cover-light.jpg          可选：浅色舞台封面（540²，见 media.light）
    demo-light.mp4           可选：浅色舞台示范视频（720²，与 demo.mp4 同步同长）
    voice/zh/name.m4a intro.m4a cue1.m4a cue2.m4a rest.m4a finish.m4a
    voice/zh/side_switch.m4a （仅单侧动作）
```

动作 id 沿用 3D-Pose-Hub 的 drill id（字母数字以 `-` 连接，可含大写，如 `glute-max-A`）。

## 2. `pack.json`（动作包）

```jsonc
{
 "format": "drill-pack", "formatVersion": 1,
 "kind": "exercise",
 "id": "h-squat",
 "version": "1.0.0",                 // 包内容版本，改任何内容就升级（见 §6）
 "name": {"zh": "徒手深蹲", "en": "Bodyweight Squat"},
 "category": "strength",             // strength | core | cardio | mobility | stretch
 "muscles": ["股四头肌", "臀大肌"],   // 展示用
 "muscleGroups": ["quadriceps", "glute-max"],  // Pose-Hub 肌群 id（高亮/检索用）
 "equipment": [],                    // mat chair wall band dumbbell block slider；[] = 徒手
 "position": "standing",             // standing seated supine prone quadruped kneeling side_lying
 "unilateral": false,                // true = 左右各做一遍
 "level": 1,                         // 1 入门 · 2 基础 · 3 进阶
 "scenes": ["home", "office"],
 "defaultDose": {"mode": "reps", "sets": 3, "reps": 12, "restSeconds": 30},
                                     // 计时动作：{"mode": "time", "sets": 1, "seconds": 30, "restSeconds": 10}
                                     // 单侧动作的 reps/seconds 指每侧
 "cues": {"zh": ["脚略宽于髋，脚尖微外", "臀部向后下坐，膝盖和脚尖同向"]},  // 1–3 条，按说的顺序
 "primaryCue": 1,                    // 最核心的一条（换侧时复述它）
 "cautions": ["膝"],                 // 需要留意的部位（生成器据此避让）
 "contraindications": [],            // 明确禁忌（自由文本，暂空，待专业审核后补）
 "alternative": null,                // 做不了时的替代动作 id（须是同库的包）
 "media": {
  "cover": "cover.jpg", "coverSeconds": 0,       // 封面取自视频第几秒（视频首帧对齐用）
  "video": "demo.mp4", "width": 720, "height": 720,
  "loopSeconds": 8.0,                // 视频一个循环的长度
  "repSeconds": 4.0,                 // 视频里一次动作的秒数（reps 模式按它数拍）
  "showsSide": "right",              // 单侧动作：视频演示的是哪一侧（另一侧镜像播放）
  "light": {                         // 可选：浅色主题用的同一段动作（浅色舞台重新合成）
   "video": "demo-light.mp4", "cover": "cover-light.jpg",   // 两项都要有；与深色版同尺寸、同循环
   "stage": "#EFEFEF"                // 舞台底色 #RRGGBB，App 用它铺视频四周
  }
 },
 "voice": {
  "languages": ["zh"],
  "voices": {"zh": "zh-CN-XiaoxiaoNeural"},
  "requires": "_common",             // 数字/单位/口令/提示音来自公共包
  "postProcess": "HipLab v4.1: …",
  "lines": [
   {"id": "name",  "role": "name",  "text": {"zh": "徒手深蹲"}, "ms": {"zh": 912}},
   {"id": "intro", "role": "intro", "text": {"zh": "徒手深蹲，练大腿前侧和臀部"}, "ms": {"zh": 2240}},
   {"id": "cue1",  "role": "cue",   "text": {"zh": "脚略宽于髋，脚尖微外"}, "ms": {"zh": 2054}},
   {"id": "cue2",  "role": "cue",   "text": {"zh": "臀部向后下坐，膝盖和脚尖同向"}, "ms": {"zh": 2600}},
   {"id": "rest",  "role": "rest",  "text": {"zh": "放松一下。下一组记住，臀部向后下坐，膝盖和脚尖同向"}, "ms": {"zh": 4100}},
   {"id": "finish","role": "finish","text": {"zh": "徒手深蹲，完成"}, "ms": {"zh": 1500}}
  ]
 },
 "credits": {"media": "…", "mediaSource": "pose-hub-v0.2.0", "spec": "drill-anim/specs/h-squat.js",
             "license": "Snow Rig © Blender Foundation … CC BY 4.0 …", "voice": "edge-tts …", "text": "…"},
 "files": {"cover.jpg": {"bytes": 31523, "sha256": "…"}, "demo.mp4": {…}, "voice/zh/cue1.m4a": {…}}
}
```

音频文件路径不写在每条台词里，固定为 `voice/<lang>/<line id>.m4a`。

### 2.1 台词角色（role）

| role | 内容 | 什么时候说（SmartFit 的用法，其他 App 可自定） |
|---|---|---|
| `name` | 动作名（口语化，括号/斜杠已处理） | 列表预览、"下一个：X" 等短提示 |
| `intro` | 动作名 + 练/拉伸/活动哪里 | 准备阶段、动作之间的休息里预告 |
| `cue` ×1–3 | 动作要领，按 `cues` 顺序 `cue1…cue3` | 预告后、计时动作进行中 |
| `side_switch` | "左侧同样，＋核心要领"（**仅且必须**单侧动作有） | 换到第二侧开始后 |
| `rest` | "放松一下。下一组记住，＋一条要领" | 同一动作组间休息 |
| `finish` | "X，完成" | 这个动作最后一组结束 |

公共包的 role：`phrase`（口令，如 `p.go` 开始、`p.rest` 休息、`p.switch_left` 换左侧、`p.ten_left` 还剩十秒）、`unit`（`u.sets` 组、`u.reps` 次、`u.sec` 秒、`u.min` 分钟、`u.rounds` 轮）、`count`（`n.1`…`n.60`）。提示音在 `chimes`：`tick` 倒数滴答、`start` 开始、`end` 一组结束、`finish` 全部完成、`silence`（2 s 静音，后台保活用）。

### 2.2 `ms`：实际解码时长

`ms` 是这条音频**解码后的真实长度**（不是容器标称值，HipLab 审计发现两者可差 90 ms），由 `tools/voice/build_voice.py` 写入。App 用它排时间线：保证句子不重叠、长句不被倒数切断。校验工具会重新解码核对（±50 ms）。

## 3. `index.json`

```json
{"format": "drill-pack-index", "formatVersion": 1, "common": "_common",
 "packs": [{"id": "_common", "kind": "common", "version": "1.0.0", "name": {…}, "bytes": 812345, "sha256": "<pack.json 的 sha256>"},
           {"id": "h-squat", "kind": "exercise", "version": "1.0.0", "name": {…}, "bytes": 240112, "sha256": "…"}]}
```

App 启动读 `index.json` → 逐个读 `pack.json`。`bytes` 是包内全部文件之和，可用于下载/缓存（以后按需下载小包时用）。

### 可选的安装包语音变体（2026-10-22）

SmartFit 的索引可额外声明 `voiceBundle: {asset, bytes, sha256}`，固定独立语音清单。
当前为 `assets/voice_lc32/v1/manifest.json`，695 条 AAC-LC / 32kbps / 22.05kHz / 单声道。
清单逐条记录 `pack/line/lang/asset/bytes/sha256/decoded_ms/duration_ms/source`。
`source` 固定原文件路径与 SHA-256；`decoded_ms` 是新文件完整解码的调度时长。

原 `pack.json`、`files`、台词和语音文件保持源素材含义，原件仍可供其他 App 拷贝使用。
SmartFit 的 `VoiceLibrary` 仅覆盖新语音的路径与时长，语义、台词、数字拼接和播放队列继续使用共用 `ugk_trainer`。
提示音仍读 `_common/chime/`，不在这 695 条转换内。

`build_packs.py` 生成 assets 段时会读取并保留 `voiceBundle`，验证清单、目标和原件的哈希，
只打包所选版本的语音目录。没有该字段时保留原有打包行为。
新原件或清单不匹配时拒绝生成，不能带着旧 LC 声音发布新台词。
以后更新原素材须生成新变体并重新固定索引中的清单 bytes/SHA-256，再生成 pubspec；不能把旧变体直接覆盖成新来源。

## 4. 工具

| 命令 | 作用 |
|---|---|
| `python3 tools/voice/build_voice.py build [--budget 100]` | 按每个包的台词文本合成语音（edge-tts → HipLab v4.1 后处理），写 `voice/<lang>/*.m4a` 并回写 `ms`；只重做文本变了的；`--budget` 秒数用完就停，再跑一次接着做 |
| `python3 tools/voice/audit_voice.py --raw` | 逐条解码检测（格式/时长一致、首尾、句中静音、截断对照源、响度 -16±1 LUFS、真峰值 ≤ -1 dBTP、语速），有失败退出码 1 |
| `python3 tools/packs/build_packs.py --pubspec pubspec.yaml` | 封包：写每个包的 `files`（大小 + sha256）、`index.json`，并重写 pubspec 里自动生成的 assets 段（Flutter 不会递归包含子目录） |
| `python3 tools/packs/validate_packs.py [--decode]` | 校验：字段与取值、id/版本、要领 1–3 条、角色齐全（单侧 ⇔ 有 `side_switch`）、文件存在且 sha256 一致、无多余文件、公共包齐全、索引一致；`--decode` 再逐条核对时长 |
| `python3 tools/packs/migrate_v1.py` | 一次性迁移（已执行）：旧 `exercises.json` + `drill_media` → 小包；保留作记录 |

`tools/packs/` 只用 Python 标准库（`--decode` 需要 ffmpeg），可整个拷到别的仓库用。语音合成需要 `edge-tts` 和 `numpy`。

日常改内容的流程：**改 `pack.json`（如台词、要领、剂量）→ 升 `version` → `build_voice.py build` → `audit_voice.py --raw` → `build_packs.py --pubspec pubspec.yaml` → `validate_packs.py --decode`**。

## 5. 其他 App 如何复用

1. **拷包**：把需要的动作文件夹和 `_common/` 拷进自己的资源目录（或整个 `assets/packs/`），跑 `validate_packs.py --root <目录>` 确认完整；`index.json` 用 `build_packs.py --root <目录>` 重建（只含你拷的包）。
2. **读取**：读 `index.json` → `pack.json`。字段含义见 §2；不认识的字段忽略即可（同一 formatVersion 内只会新增可选字段）。
3. **视频**：`media.video` 循环播放；先显示 `media.cover`，视频第一帧出来后再盖上去（封面取自 `coverSeconds`，无黑闪）。单侧动作第二侧按 `showsSide` 镜像。
4. **语音**：一条台词 = 一个 m4a，路径 `voice/<lang>/<id>.m4a`，时长看 `ms`。剂量这类可变内容用公共包拼（如 `n.3`+`u.sets`+`p.per_side`+`n.12`+`u.reps` = "3 组 每侧 12 次"）。播放链路建议直接用 SmartFit/HipLab 的 `VoiceLineController`（播到 completed 才算一句结束、会话操作串行、释放 duck 前确认无声，见 `lib/voice/`）。
5. **署名**：展示 `credits.license`（视频使用 CC BY 4.0 的 Snow 角色，必须署名）。
6. **Flutter**：asset 目录要逐个列出（`build_packs.py --pubspec` 自动生成）。Web/原生 App 直接按文件路径读。

## 6. 版本规则

- `formatVersion`：格式本身。只加可选字段不升；改字段含义/删字段才升，并在本文件记录迁移方法。读取方遇到不认识的 `formatVersion` 应拒绝该包。
- `version`（每个包，`MAJOR.MINOR.PATCH`）：
  - PATCH：重新生成音频（后处理/音色变了）、修错字、换更清晰的封面；
  - MINOR：增删台词或要领、改默认剂量、替换视频、新增/替换 `media.light` 浅色媒体；
  - MAJOR：动作本身变了（不同动作不应复用 id，正常不会发生）。
- `files` 列出包里每个文件，**包括 `media.light` 的浅色视频和封面**（`packlib.listed_files()` 枚举，`validate_packs.py` 校验 `media.light` 字段并把未列出的文件报为 stray）。
- `files` 里的 sha256 让拷贝方能判断某个文件是否和源一致；`index.json` 里的 `sha256` 让 App 判断包有没有变（以后做增量更新用）。

## 7. 现状（2026-10-19）

- 93 个动作包 + 1 个公共包；全部中文语音（`zh`）。2026-10-20：93 个动作包加入 `media.light`（浅色视频 + 封面，已进 `files` 与 `index.json`），内容版本升到 1.1.0；公共包仍为 1.0.0。英文语音格式已支持（`languages` 加 `en`、台词加 `text.en`），暂未生成。
- 要领来自原 `exercises.json` 的审过的主要领 + `tools/library/exercises.csv` 的准备/动作要领（去掉了换种说法重复的），每个动作 1–3 条；intro/rest/side_switch/finish 由元数据按固定句式生成，**需要人工复听润色**，改 `pack.json` 后重跑上面的流程即可。
- `contraindications` 暂空：不编造医学禁忌，等专业审核补充；`cautions`（注意部位）已有。
