# 动作 AI 标签（ai-tags）

给 AI 选动作用的结构化标签，每个定稿动作一个文件。**只新增文件，不改现有动作定义**：v3 文案（`catalog/production/v3-text/`）、配方、spec、渲染产物和 `media/` 都不动。

状态：第一阶段（词表 + schema + 校验 + 5 个样例），`status: ai-draft`，未经人工审核。

## 文件

| 路径 | 内容 |
|---|---|
| `vocabulary.json` | 固定词表 v0.1.0：33 个维度，每个值带 zh/en 和一句定义；器械/肌群带 v3 同义写法（aliases / v3Aliases） |
| `ai-tags.schema.json` | 单个标签文件的 JSON Schema（draft 2020-12），枚举由词表生成 |
| `actions/<id>.json` | 每个动作的标签（`pose-hub-ai-tags@1`），`source.textSha256Lf` 固定所依据的 v3 文案 |
| `reports/baseline-20261103.md` | 249 个动作现有标签的分布与数据问题（`tools/ai-tags/baseline_report.py` 生成） |

权威动作清单：`catalog/production/v3-text/*.json` 249 份，与 `remaining219-r1/recipes`（217）+ `remaining32-r4/groups`（32）逐一对应。

## 校验

```bash
python tools/ai-tags/validate.py           # 现在：只报告缺多少，不判失败
python tools/ai-tags/validate.py --strict  # 批量完成后：缺标签也失败
```

检查：值都在词表、必填不缺、关联动作 id 是 249 之一、id 与文件名一致、schema 与词表同步；警告：与 v3 的单侧/交替、cautions 部位、文案哈希、场景合理性（办公室+着地、酒店+高冲击等）。

## 约定要点

- 肌群沿用 taxonomy 20 个 id，新增 `neck`、`upper-traps`、`hip-rotators`、`peroneals`（原因见词表 `addedReason`）。v3 的 core/glutes/upper-back/lower-back/abductors 按动作实际做法拆分，不机械替换。
- 拉伸类：被拉肌放 `stretchedMuscles`，不放 `primaryMuscles`。
- 能从 v3 推出来的字段与 v3 一致；冲突以真实做法为准，写进 `notes`（field / existing / chosen / reason）。
- `aiSummary` 是唯一面向 AI 的自由文本；`notes`、`reviewNotes` 给人看。

## 批量打 249 个的计划

1. **预填（脚本，约 0.5 天）**：从 v3 tags 机械预填可推字段——laterality（unilateral + training.kind/perSide）、contraction（hold/rep_hold）、requiredEquipment（alias 归一）、floorRequired（体位 + mat）、difficulty 初值、jointStress 初值（cautions 条件部位）。预填值标 `confidence: low`，必须逐个过目。
2. **分批人工/AI 打标（约 20 批 × 12 个）**：按肌群组和前缀聚类（同组的 A/B/C、h-db-*、o-*、n-*、t-* 放一批），这样关联动作 id 和难度梯度在一批内一起定。每批读文案、cues、spec 头注释，必要时看 256px 关键帧。每批后跑 `validate.py`。
3. **交叉复核**：每批由另一个独立 agent 只看文案和 spec 重打关键字段（scenes、trainingType、primary/stretched、difficulty、laterality、jointStress），与第一遍做 diff；不一致的进入 `reviewNotes` 并标 `confidence: medium/low`，由开哥裁定。全部完成后再做一次全库一致性扫描：同模式动作难度梯度、alternatives 双向性、办公室集合抽查。
4. **用户审核**：输出 low/medium 清单和按场景的动作集合，开哥过目后把 `status` 改为 `user-reviewed`，再把 `validate.py --strict` 设为必过。

预计：预填 0.5 天；打标约 20 批，每批 30–45 分钟，共 2–3 天（串行，2 CPU 无压力）；交叉复核与一致性扫描约 1 天；合计 4–5 天，另加开哥审核时间。
