/// The safety talk that opens the chat on first launch (it replaced the old
/// safety page; same disclaimer, same four questions, same rule: any "是"
/// → no generated plans, browse only).
library;

const disclaimerText =
    '智能健身助手提供的是通用健身与拉伸建议，不是医疗诊断或康复处方。'
    '训练中如出现疼痛、麻木、头晕、胸闷或呼吸困难，请立即停止并及时就医。'
    '有慢性病、伤病或正在康复期，请先咨询医生。动作示范中的肌肉高亮仅为教学示意。';

const safetyQuestions = [
  '孕期或产后 6 个月内',
  '近期做过手术，或医生让你限制运动',
  '最近摔伤、扭伤，或关节、腰背正在疼痛肿胀',
  '有心脏病、未控制的高血压，或运动时出现过胸痛、晕厥',
];

const safetyIntro = '你好，我是你的训练助手。\n告诉我想练什么、在哪儿、有多少时间，我帮你排一套能直接跟练的计划。';

const safetyDisclaimer = '开始之前，先花 10 秒确认安全。\n\n$disclaimerText';

const safetyLead = '再确认 4 件事，符合的话点「是」。';

String safetyQuestionText(int i) =>
    '${i + 1}/${safetyQuestions.length}　${safetyQuestions[i]}？';

const safetyAllClear = '好，都没问题。\n现在说说：想练什么、在哪儿、有多少时间？';

const _advice = [
  '孕期和产后恢复期的训练，需要先由医生或专业人员评估。',
  '术后或被限制运动期间，请按医生的康复安排来。',
  '有急性疼痛或肿胀时先休息，必要时就医，恢复后再练。',
  '心血管方面的情况需要先经医生评估；如果现在就有胸痛或晕厥，请立即就医。',
];

String safetyBlockedText(int question) =>
    '${_advice[question]}\n'
    '为了安全，我先不为你生成训练计划，建议先咨询医生。你仍可以浏览动作库里的示范；'
    '情况变化后，可以在菜单的「关于与设置」里重新确认。';
