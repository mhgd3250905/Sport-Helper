# TrainingPlan v1（模板生成与 AI 生成共用）

```jsonc
{
  "schemaVersion": 1,
  "id": "plan-1760800000000",
  "source": "template",            // template | ai
  "templateId": "fullbody-bodyweight",
  "title": "居家徒手全身", "summary": "…",
  "goal": "strength",              // relax|mobility|strength|core|fullbody|warmup|cooldown
  "scene": "home",                 // home|office
  "equipment": ["chair","wall","mat","block","dumbbell"],
  "level": 1,                      // 1 入门 2 基础 3 进阶
  "targetMinutes": 20,
  "blocks": [
    {"id": "b2", "name": "全身循环", "type": "circuit",   // warmup|main|circuit|cooldown
     "rounds": 3, "restBetweenRoundsSeconds": 60,
     "items": [
       {"exerciseId": "h-squat", "mode": "reps", "sets": 1, "reps": 12, "perSide": false, "restSeconds": 15},
       {"exerciseId": "s-figure4", "mode": "time", "sets": 1, "workSeconds": 30, "perSide": true, "restSeconds": 10}
     ]}
  ],
  "notes": ["「椅子保加利亚分腿蹲」换成「徒手深蹲」（难度偏高）"],
  "safetyNotes": ["…"]
}
```

规则（`lib/domain/plan_validator.dart`，模板和 AI 输出都要过）：
- `exerciseId` 必须在 `assets/library/exercises.json`；`perSide` 必须等于该动作的 `unilateral`
- sets 1–6、reps 1–30、workSeconds 10–120、restSeconds 0–180、rounds 1–6
- 动作所需器械 ⊆ 用户可用器械；办公室场景不能有趴/躺/跪地动作；不得包含用户要保护部位的动作
- 热身块不能排在放松块之后

AI 接入（进阶，未接任何模型）：实现 `PlanGenerator`（`lib/domain/plan_generator.dart` 里的 `AiPlanGenerator` 占位），输出本 schema；校验失败时 App 回落到 `TemplatePlanGenerator`。语音只由库内动作名 + 数字 + 固定短语拼成，AI 文案只做字幕。
