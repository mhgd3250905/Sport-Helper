#!/usr/bin/env python3
"""Writes assets/library/templates.json (the fixed MVP templates).

Compact rows: "id[:sets][xREPS|@SECONDS][~REST]" e.g. "h-squat:3x12~30", "s-figure4@30".
Unspecified fields fall back to the exercise's default dose. Edit here and re-run.
"""
import json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
LIB = {e['id']: e for e in json.loads((ROOT/'assets/library/exercises.json').read_text())['exercises']}

def item(s, typ='main'):
    m = re.fullmatch(r'([\w-]+?)(?::(\d+))?(?:x(\d+)|@(\d+))?(?:~(\d+))?', s)
    assert m, s
    i, sets, reps, sec, rest = m.groups()
    e = LIB[i]; d = e['dose']
    mode = 'reps' if reps else 'time' if sec else d['mode']
    out = {'exerciseId': i, 'mode': mode, 'sets': int(sets or (1 if typ in ('warmup', 'cooldown') else d['sets'])),
           'perSide': e['unilateral'], 'restSeconds': int(rest or d['restSeconds'])}
    if mode == 'reps': out['reps'] = int(reps or d.get('reps') or 10)
    else: out['workSeconds'] = int(sec or d.get('seconds') or 30)
    return out

def block(bid, name, typ, rows, rounds=1, rr=0):
    return {'id': bid, 'name': name, 'type': typ, 'rounds': rounds,
            'restBetweenRoundsSeconds': rr, 'items': [item(r, typ) for r in rows.split()]}

T = [
 dict(id='office-relax', name='工位肩颈腰放松', goal='relax', scenes=['office'], equipment=[], minutes=8, level=[1,3],
      summary='坐着站着都能做，不用换衣服，缓解久坐僵硬。',
      keywords='办公室 工位 久坐 肩颈 颈椎 腰酸 上班 午休 放松',
      blocks=[block('b1','唤醒','warmup','n-pelvis-circle@30 o-seated-catcow@40'),
              block('b2','拉伸放松','main','o-seated-twist@40 h-chair-lat@30 o-stand-sidebend@25 o-stand-quad@25 o-seated-fig4@25 o-stand-lunge@25')]),
 dict(id='office-active', name='工位 10 分钟激活', goal='fullbody', scenes=['office'], equipment=[], minutes=10, level=[1,2],
      summary='不出汗的小循环：蹲、推、提踵，把久坐的身体叫醒。',
      keywords='办公室 工位 激活 提神 下午 犯困 久坐 站起来',
      blocks=[block('b1','热身','warmup','n-pelvis-circle@30 h-good-morning:1x10'),
              block('b2','激活循环','circuit','h-squat:1x10~10 h-incline-pushup:1x8~10 h-calf-raise:1x15~10 h-chair-kickback:1x10~10', rounds=2, rr=30),
              block('b3','放松','cooldown','o-stand-lunge@25 h-chair-lat@30')]),
 dict(id='morning-wake', name='晨起唤醒', goal='mobility', scenes=['home'], equipment=[], minutes=8, level=[1,3],
      summary='从关节画圈到轻微出汗，起床后 8 分钟让身体醒过来。',
      keywords='早上 晨起 起床 早晨 唤醒 精神',
      blocks=[block('b1','关节唤醒','warmup','h-catcow-quad@40 n-pelvis-circle@30 h-hip-gate:1x6'),
              block('b2','轻激活','main','h-squat:2x10~20 h-wall-angel:1x10 h-step-jack@40'),
              block('b3','舒展','cooldown','o-stand-sidebend@25')]),
 dict(id='bedtime', name='睡前放松', goal='relax', scenes=['home'], equipment=[], minutes=10, level=[1,3],
      summary='全程躺着做，慢呼吸，放松腰背和髋。',
      keywords='睡前 晚上 失眠 睡觉 放松 助眠 躺着',
      blocks=[block('b1','放松','main','h-knee-hug@40 n-windshield:1x8 s-figure4@30 h-supine-twist@40 h-banana@30 h-wall-straddle@60 n-thomas-test@30')]),
 dict(id='fullbody-bodyweight', name='居家徒手全身', goal='strength', scenes=['home'], equipment=[], minutes=20, level=[1,3],
      summary='不需要器械的全身循环：下肢、推、后链、核心各一个。',
      keywords='全身 徒手 居家 在家 健身 力量 减脂 无器械 自重',
      blocks=[block('b1','热身','warmup','h-step-jack@40 h-catcow-quad@40 h-good-morning:1x10'),
              block('b2','全身循环','circuit','h-squat:1x12~15 h-incline-pushup:1x10~15 w-feet-on-chair-bridge:1x12~15 w-bird-dog:1x8~15 h-forearm-plank@30~15', rounds=3, rr=60),
              block('b3','放松','cooldown','o-stand-quad@25 h-chair-lat@30 h-cobra@30')]),
 dict(id='dumbbell-fullbody', name='哑铃全身力量', goal='strength', scenes=['home'], equipment=['dumbbell'], minutes=25, level=[1,3],
      summary='一对哑铃完成推、拉、髋铰链和肩部训练。',
      keywords='哑铃 力量 增肌 塑形 全身 器械',
      blocks=[block('b1','热身','warmup','h-step-jack@40 h-good-morning:1x10 h-wall-angel:1x8'),
              block('b2','力量','main','h-db-rdl:3x10~45 h-db-floor-press:3x10~45 h-db-row:3x10~30 h-db-press:2x10~45 h-db-curl:2x12~30 h-db-lateral:2x12~30'),
              block('b3','核心','main','w-dead-bug:2x10~20'),
              block('b4','放松','cooldown','h-chair-lat@30 h-seated-reachback@30')]),
 dict(id='band-upper-posture', name='弹力带上肢与体态', goal='strength', scenes=['home'], equipment=['band'], minutes=15, level=[1,3],
      summary='弹力带划船、拉开、抗旋转，改善圆肩含胸。',
      keywords='弹力带 圆肩 驼背 含胸 体态 肩 背 上肢',
      blocks=[block('b1','热身','warmup','h-wall-angel:1x10 h-catcow-quad@30'),
              block('b2','弹力带','main','h-band-row:3x12~30 h-band-pull-apart:3x15~30 h-band-pallof:2x10~30 h-side-er:2x12~20 h-incline-pushup:2x10~30'),
              block('b3','放松','cooldown','h-chair-tspine@30 h-seated-reachback@30')]),
 dict(id='core', name='核心强化', goal='core', scenes=['home'], equipment=[], minutes=12, level=[1,3],
      summary='腹部、腰背和抗旋转一起练，保护腰椎。',
      keywords='核心 腹肌 马甲线 腰腹 小肚子 腹部 平板',
      blocks=[block('b1','热身','warmup','h-catcow-quad@30'),
              block('b2','核心','main','w-dead-bug:2x10~20 h-crunch:2x15~20 h-reverse-crunch:2x12~20 h-russian-twist:2x16~20 h-forearm-plank:2@30~20 w-bird-dog:2x8~20 h-superman:2x10~20'),
              block('b3','放松','cooldown','h-cobra@30 h-knee-hug@30')]),
 dict(id='glutes-legs', name='臀腿强化', goal='strength', scenes=['home'], equipment=[], minutes=18, level=[1,3],
      summary='臀中肌激活 + 臀推 + 分腿蹲，练出稳定有力的下肢。',
      keywords='臀 臀部 翘臀 腿 下肢 臀腿 美腿',
      blocks=[block('b1','激活','warmup','w-clamshell:1x15 w-fire-hydrant:1x12'),
              block('b2','力量','main','w-chair-hip-thrust:3x12~40 h-bulgarian:3x8~40 h-bridge-march:2x10~30 w-wall-sit:2@30~30 h-calf-raise:2x15~20'),
              block('b3','放松','cooldown','s-figure4@30 o-stand-quad@25')]),
 dict(id='hip-open', name='开胯灵活', goal='mobility', scenes=['home'], equipment=[], minutes=12, level=[1,3],
      summary='先动后拉：髋关节画圈、90/90、蝴蝶、屈髋拉伸。',
      keywords='开胯 髋 胯 髋关节 劈叉 柔韧 一字马 灵活 舞蹈',
      blocks=[block('b1','活动','warmup','n-pelvis-circle@30 h-quad-cars:1x5'),
              block('b2','开胯','main','s-9090@40 h-adductor-rock@30 s-butterfly@40 s-kneel-hipflex@30 h-reverse-clam:2x12~20 s-figure4@30'),
              block('b3','放松','cooldown','h-wall-straddle@60')]),
 dict(id='sedentary-posterior', name='久坐后链激活', goal='strength', scenes=['home'], equipment=[], minutes=12, level=[1,2],
      summary='唤醒久坐变弱的臀和腰背，预防腰酸。',
      keywords='久坐 腰酸 后背 腰 臀 激活 程序员 学生',
      blocks=[block('b1','激活','main','w-bird-dog:2x8~20 w-dead-bug:2x10~20 w-feet-on-chair-bridge:2x12~30 w-clamshell:2x12~20 w-prone-swimmer:2x10~20 h-good-morning:2x10~20'),
              block('b2','放松','cooldown','h-knee-hug@30 h-supine-twist@30')]),
 dict(id='warmup', name='运动前热身', goal='warmup', scenes=['home','office'], equipment=[], minutes=6, level=[1,3],
      summary='跑步、打球、健身前 6 分钟动态热身。',
      keywords='热身 运动前 跑步前 打球 准备活动',
      blocks=[block('b1','动态热身','warmup','h-step-jack@40 n-pelvis-circle@30 h-hip-gate:1x6 h-squat:1x10 h-wall-angel:1x8 h-good-morning:1x10')]),
 dict(id='cooldown', name='运动后拉伸', goal='cooldown', scenes=['home'], equipment=[], minutes=8, level=[1,3],
      summary='运动后把腿、髋、背拉开，缓解酸痛。',
      keywords='拉伸 运动后 跑步后 放松 酸痛 冷身',
      blocks=[block('b1','拉伸','cooldown','o-stand-quad@30 h-wall-calf@30 s-kneel-hipflex@30 s-seated-fold@40 s-figure4@30 h-chair-lat@30 h-cobra@30')]),
]
for t in T:
    t['keywords'] = t['keywords'].split()
(ROOT/'assets/library/templates.json').write_text(json.dumps({'schemaVersion': 1, 'templates': T}, ensure_ascii=False, indent=1)+'\n')
used = {i['exerciseId'] for t in T for b in t['blocks'] for i in b['items']}
print(len(T), 'templates;', len(used), 'exercises used;', 'unused:', len(set(LIB)-used))
