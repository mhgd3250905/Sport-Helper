#!/usr/bin/env python3
"""Builds assets/library/exercises.json — the unified exercise library.

Sources (read-only, copied facts only):
  * 3D-Pose-Hub drill-anim/specs/<id>.js  (name, highlight muscles, unilateral side, rep timing)
  * HipLab hip-content.json / voice_lines.py (scenes, level, cautions, spoken key point) via
    tools/library/hiplab_points.json
  * curated metadata below (category, equipment, position, level, dose, cues) — written for
    智能健身助手 MVP and reviewed by hand. Edit here, then re-run:

      python3 tools/library/build_library.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POINTS = json.loads((Path(__file__).parent / 'hiplab_points.json').read_text())

MUSCLE = {
    'quadriceps': '股四头肌', 'glute-max': '臀大肌', 'hamstrings': '腘绳肌', 'chest': '胸大肌',
    'triceps': '肱三头肌', 'erectors': '竖脊肌', 'calves': '小腿', 'hip-abductors': '臀中肌',
    'deltoids': '三角肌', 'abs': '腹直肌', 'obliques': '腹斜肌', 'tibialis': '胫骨前肌',
    'biceps': '肱二头肌', 'scapular': '菱形肌·中下斜方', 'lats': '背阔肌', 'rotator-cuff': '肩袖',
    'adductors': '大腿内侧', 'hip-flexors': '髋屈肌',
}

# id: (name, muscles, unilateral, category, equipment, position, level, mode, amount, sets,
#      scenes, cue, cautions, alternative)
# category: strength | core | cardio | mobility | stretch
# equipment: none mat chair wall band dumbbell block slider
# mode: reps (amount = reps per set) | time (amount = seconds per set / per side)
# level: 1 入门 2 基础 3 进阶
R = 'reps'
T = 'time'
H = ['home']
O = ['office']
HO = ['home', 'office']
D = {
    # ---- strength / lower ----
    'h-squat': ('徒手深蹲', 'quadriceps glute-max', 0, 'strength', 'none', 'standing', 1, R, 12, 3, HO,
                '臀部向后下坐，膝盖和脚尖同向', '膝', None),
    'h-bulgarian': ('椅子保加利亚分腿蹲', 'quadriceps glute-max', 1, 'strength', 'chair', 'standing', 3, R, 8, 3, H,
                    '后脚搭椅，前膝对准脚尖，身体垂直下沉', '膝', 'h-squat'),
    'h-chair-step-up': ('椅子上步', 'quadriceps glute-max', 0, 'strength', 'chair', 'standing', 2, R, 10, 3, H,
                        '整只脚踩稳椅面，用前腿发力站起', '膝', 'h-squat'),
    'h-chair-kickback': ('扶椅站姿后踢腿', 'glute-max', 1, 'strength', 'chair', 'standing', 1, R, 12, 2, HO,
                         '扶稳椅背，腿向后抬，腰不要塌', '腰', None),
    'h-side-leg-raise': ('站姿侧抬腿', 'hip-abductors', 1, 'strength', 'none', 'standing', 1, R, 12, 2, HO,
                         '身体保持直立，腿向侧面抬起再慢慢放下', '', None),
    'h-calf-raise': ('扶墙提踵', 'calves', 0, 'strength', 'wall', 'standing', 1, R, 15, 2, HO,
                     '脚跟抬到最高停一下，慢慢落下', '', None),
    'h-tib-raise': ('靠墙勾脚尖', 'tibialis', 0, 'strength', 'wall', 'standing', 1, R, 15, 2, HO,
                    '背靠墙，脚尖勾起再放下，脚跟不离地', '', None),
    'w-wall-sit': ('靠墙静蹲', 'quadriceps glute-max', 0, 'strength', 'wall', 'standing', 2, T, 30, 3, H,
                   '背贴墙，大腿接近水平，膝盖在脚踝上方', '膝', 'h-squat'),
    'glute-max-A': ('单腿臀桥', 'glute-max', 0, 'strength', 'mat', 'supine', 2, R, 10, 3, H,
                    '一腿伸直，另一侧脚跟推地把臀部抬起', '腰', 'w-feet-on-chair-bridge'),
    'w-feet-on-chair-bridge': ('脚踩椅面臀桥', 'hamstrings glute-max', 0, 'strength', 'chair', 'supine', 1, R, 12, 3, H,
                               '脚跟踩椅，收紧臀部抬髋，肋骨不外翻', '', None),
    'w-chair-hip-thrust': ('椅子臀推', 'glute-max', 0, 'strength', 'chair', 'supine', 2, R, 12, 3, H,
                           '上背靠椅沿，臀部推到身体成一条直线', '腰', 'w-feet-on-chair-bridge'),
    'h-bridge-march': ('臀桥交替踏步', 'glute-max hamstrings', 0, 'strength', 'mat', 'supine', 2, R, 10, 3, H,
                       '臀桥撑住不晃，左右膝交替抬起', '腰', 'w-feet-on-chair-bridge'),
    'w-clamshell': ('侧卧蚌式开合', 'hip-abductors', 1, 'strength', 'mat', 'side_lying', 1, R, 15, 2, H,
                    '双脚并拢，上侧膝盖打开，骨盆不后倒', '', None),
    'w-fire-hydrant': ('四足消防栓', 'hip-abductors', 1, 'strength', 'mat', 'quadruped', 1, R, 12, 2, H,
                       '四点跪姿，膝盖向侧面抬起，躯干不倾斜', '膝', None),
    'h-good-morning': ('徒手早安式', 'hamstrings erectors', 0, 'strength', 'none', 'standing', 1, R, 12, 3, HO,
                       '背挺直，臀部向后推，感到大腿后侧拉紧再起身', '腰', None),
    'h-superman': ('俯卧超人式', 'erectors glute-max', 0, 'strength', 'mat', 'prone', 1, R, 10, 2, H,
                   '手脚同时轻轻抬离地面，颈部保持中立', '腰', 'w-prone-swimmer'),
    # ---- strength / upper ----
    'h-incline-pushup': ('扶凳上斜俯卧撑', 'chest triceps', 0, 'strength', 'chair', 'standing', 1, R, 10, 3, HO,
                         '双手撑稳凳面，身体成一条直线，胸口贴近再推起', '手腕 肩', None),
    'h-chair-dip': ('椅子臂屈伸', 'triceps', 0, 'strength', 'chair', 'seated', 2, R, 10, 3, H,
                    '肩膀下沉远离耳朵，肘向后弯曲再撑起', '肩 手腕', 'h-incline-pushup'),
    'h-tabletop': ('桌面式后撑抬髋', 'chest deltoids', 0, 'strength', 'mat', 'seated', 1, R, 10, 2, H,
                   '手在肩下，推地把臀部抬到桌面高度', '手腕 肩', None),
    'h-db-floor-press': ('哑铃地板卧推', 'chest triceps', 0, 'strength', 'dumbbell', 'supine', 1, R, 10, 3, H,
                         '大臂与身体约四十五度，推起时哑铃在胸口正上方', '肩', None),
    'h-db-press': ('站姿哑铃推举', 'deltoids triceps', 0, 'strength', 'dumbbell', 'standing', 2, R, 10, 3, H,
                   '收紧腹部，哑铃从肩旁推到头顶，腰不后仰', '肩 腰', 'h-db-lateral'),
    'h-db-lateral': ('哑铃侧平举', 'deltoids', 0, 'strength', 'dumbbell', 'standing', 1, R, 12, 3, H,
                     '手肘微屈，向侧面抬到肩高，不耸肩', '肩', None),
    'h-db-curl': ('哑铃交替弯举', 'biceps', 0, 'strength', 'dumbbell', 'standing', 1, R, 12, 3, H,
                  '大臂贴住身体，只动小臂', '', None),
    'h-db-row': ('扶椅单臂哑铃划船', 'lats scapular', 1, 'strength', 'dumbbell', 'standing', 1, R, 10, 3, H,
                 '背部平直，手肘向后拉到身侧', '腰', None),
    'h-db-reverse-fly': ('哑铃俯身飞鸟', 'deltoids scapular', 0, 'strength', 'dumbbell', 'standing', 2, R, 12, 3, H,
                         '俯身背平，双臂向两侧打开，夹紧肩胛', '腰', 'h-band-pull-apart'),
    'h-db-rdl': ('哑铃罗马尼亚硬拉', 'hamstrings glute-max', 0, 'strength', 'dumbbell', 'standing', 2, R, 10, 3, H,
                 '哑铃贴腿下滑，臀部向后，背始终挺直', '腰', 'h-good-morning'),
    'h-band-row': ('弹力带坐姿划船', 'lats scapular', 0, 'strength', 'band', 'seated', 1, R, 12, 3, H,
                   '坐直，手肘贴身向后拉，夹紧肩胛', '', None),
    'h-band-pull-apart': ('弹力带水平拉开', 'scapular deltoids', 0, 'strength', 'band', 'standing', 1, R, 15, 2, HO,
                          '手臂伸直与肩同高，把弹力带向两侧拉开', '肩', None),
    'h-band-pallof': ('弹力带抗旋转推', 'obliques', 0, 'core', 'band', 'standing', 2, R, 10, 2, H,
                      '双手向前推直，身体不被弹力带拉转', '', None),
    'h-band-hip-ir': ('坐椅弹力带髋内旋', 'hip-abductors glute-max', 1, 'strength', 'band', 'seated', 1, R, 12, 2, HO,
                      POINTS.get('h-band-hip-ir'), '膝', None),
    'h-side-er': ('侧卧肩外旋', 'rotator-cuff', 1, 'strength', 'mat', 'side_lying', 1, R, 12, 2, H,
                  '肘贴身体侧面，小臂向上转开', '肩', None),
    'h-wall-angel': ('靠墙天使', 'chest lats scapular', 0, 'mobility', 'wall', 'standing', 1, R, 10, 2, HO,
                     '后背和手臂贴墙，慢慢向上滑再向下', '肩', None),
    # ---- core ----
    'h-forearm-plank': ('前臂平板支撑', 'abs obliques', 0, 'core', 'mat', 'prone', 1, T, 30, 3, H,
                        '肘在肩下，身体成一条直线，不塌腰不撅臀', '腰 肩', None),
    'h-crunch': ('卷腹', 'abs', 0, 'core', 'mat', 'supine', 1, R, 15, 3, H,
                 '下背贴地，用腹部把肩胛卷离地面', '颈', None),
    'h-reverse-crunch': ('反向卷腹', 'abs', 0, 'core', 'mat', 'supine', 2, R, 12, 3, H,
                         '屈膝把骨盆卷离地面，慢慢放回', '腰', 'h-crunch'),
    'h-russian-twist': ('俄罗斯转体', 'obliques', 0, 'core', 'mat', 'seated', 2, R, 16, 3, H,
                        '上身微后仰，背挺直，左右转动肩膀', '腰', 'h-band-pallof'),
    'w-dead-bug': ('死虫式', 'abs', 0, 'core', 'mat', 'supine', 1, R, 10, 3, H,
                   '下背紧贴地面，对侧手脚慢慢伸远', '', None),
    'w-bird-dog': ('鸟狗式', 'erectors', 0, 'core', 'mat', 'quadruped', 1, R, 10, 2, H,
                   '对侧手脚伸直，背部保持水平不晃', '膝', None),
    'w-prone-swimmer': ('俯卧游泳式', 'scapular erectors', 0, 'core', 'mat', 'prone', 1, R, 10, 2, H,
                        '胸口微抬，手臂从前方划到身侧', '腰 肩', None),
    'hip-flexors-A': ('坐姿直腿抬腿（压缩）', 'hip-flexors', 0, 'core', 'mat', 'seated', 3, R, 8, 3, H,
                      POINTS.get('hip-flexors-A'), '', 'n-seated-knee-lift'),
    'n-seated-knee-lift': ('坐姿抬膝悬停', 'hip-flexors', 0, 'core', 'chair', 'seated', 1, T, 30, 2, HO,
                           POINTS.get('n-seated-knee-lift'), '', None),
    'n-seated-squeeze': ('坐姿夹砖（膝内夹）', 'adductors', 0, 'strength', 'chair', 'seated', 1, T, 30, 2, HO,
                         POINTS.get('n-seated-squeeze'), '', None),
    # ---- cardio ----
    'h-step-jack': ('低冲击开合跳', 'deltoids hip-abductors', 0, 'cardio', 'none', 'standing', 1, T, 40, 2, HO,
                    '一只脚向侧面迈开，同时双臂上举', '膝', None),
    # ---- mobility / stretch: back, shoulder, core ----
    'h-catcow-quad': ('四足猫牛式', 'erectors abs', 0, 'mobility', 'mat', 'quadruped', 1, T, 40, 1, H,
                      '吸气塌腰抬头，呼气拱背低头', '', None),
    'h-cobra': ('眼镜蛇式', 'abs', 0, 'stretch', 'mat', 'prone', 1, T, 30, 1, H,
                '耻骨贴地，手推地慢慢抬起胸口', '腰', None),
    'h-chair-lat': ('扶椅背阔肌拉伸', 'lats', 0, 'stretch', 'chair', 'standing', 1, T, 30, 1, HO,
                    '双手扶椅，臀部向后推，胸口下沉', '', None),
    'h-chair-tspine': ('跪姿椅面胸椎伸展', 'lats erectors', 0, 'stretch', 'chair', 'kneeling', 1, T, 30, 1, H,
                       '手肘搭椅面，胸口慢慢下沉', '肩', None),
    'h-dd-shoulder': ('下犬式压肩', 'lats chest', 0, 'stretch', 'mat', 'quadruped', 2, T, 30, 1, H,
                      '手推地，臀部向上向后，胸口靠近大腿', '手腕 肩', 'h-chair-lat'),
    'h-wall-calf': ('靠墙小腿拉伸', 'calves', 1, 'stretch', 'wall', 'standing', 1, T, 30, 1, HO,
                    '后腿伸直，脚跟踩实，身体前倾', '', None),
    'h-seated-reachback': ('坐姿后撑滑臀', 'chest deltoids', 0, 'stretch', 'mat', 'seated', 1, T, 30, 1, H,
                           '双手在身后撑地，臀部慢慢向前滑', '肩 手腕', None),
    'h-banana': ('仰卧香蕉式侧伸', 'obliques lats', 0, 'stretch', 'mat', 'supine', 1, T, 30, 1, H,
                 '仰卧把身体弯成香蕉形，感受体侧拉长', '', None),
    'h-knee-hug': ('仰卧抱膝', 'erectors glute-max', 0, 'stretch', 'mat', 'supine', 1, T, 30, 1, H,
                   POINTS.get('h-knee-hug'), '髋', None),
    'h-supine-twist': ('仰卧屈膝扭转', 'obliques erectors', 0, 'stretch', 'mat', 'supine', 1, T, 40, 1, H,
                       POINTS.get('h-supine-twist'), '腰', None),
    'o-seated-catcow': ('坐姿猫牛式', 'erectors', 0, 'mobility', 'chair', 'seated', 1, T, 40, 1, O,
                        '坐在椅子前半部分，吸气挺胸，呼气拱背', '', None),
    'o-seated-twist': ('坐姿扶椅扭转', 'obliques erectors', 0, 'stretch', 'chair', 'seated', 1, T, 40, 1, O,
                       '坐直，手扶椅背慢慢转身，先长高再转', '腰', None),
    'o-stand-quad': ('扶椅站姿股四头肌拉伸', 'quadriceps', 1, 'stretch', 'chair', 'standing', 1, T, 30, 1, HO,
                     '扶稳椅子，手拉脚背贴近臀部，膝盖朝下', '膝', None),
    'o-stand-sidebend': ('站姿举手侧屈', 'obliques', 1, 'stretch', 'none', 'standing', 1, T, 30, 1, HO,
                         '手臂举过头，身体向侧面弯，不前倾', '', None),
    # ---- hip mobility (HipLab set) ----
    'h-9090-liftoff': ('90/90 后腿主动抬起', 'hip-abductors glute-max', 1, 'mobility', 'mat', 'seated', 3, R, 8, 2, H,
                       POINTS.get('h-9090-liftoff'), '膝', 'h-reverse-clam'),
    'h-adductor-rock': ('四足单腿侧伸后摇', 'adductors', 1, 'stretch', 'mat', 'quadruped', 1, T, 30, 1, H,
                        POINTS.get('h-adductor-rock'), '膝', None),
    'h-band-leg-out': ('仰卧弹力带单腿侧落', 'adductors hamstrings', 1, 'stretch', 'band', 'supine', 1, T, 30, 1, H,
                       POINTS.get('h-band-leg-out'), '大腿内侧', None),
    'h-butterfly-active': ('仰卧蝴蝶主动开合', 'adductors', 0, 'mobility', 'mat', 'supine', 1, R, 10, 1, H,
                           POINTS.get('h-butterfly-active'), '', None),
    'h-couch-stretch': ('沙发拉伸（后脚搭矮凳）', 'hip-flexors quadriceps', 1, 'stretch', 'chair', 'kneeling', 3, T, 30, 1, H,
                        POINTS.get('h-couch-stretch'), '膝 腰', 's-kneel-hipflex'),
    'h-hip-gate': ('扶椅站姿开髋门', 'hip-flexors hip-abductors', 1, 'mobility', 'chair', 'standing', 1, R, 6, 1, HO,
                   POINTS.get('h-hip-gate'), '', None),
    'h-quad-cars': ('四足髋关节画圈', 'glute-max hip-abductors', 1, 'mobility', 'mat', 'quadruped', 3, R, 5, 1, H,
                    POINTS.get('h-quad-cars'), '腰', 'h-hip-gate'),
    'h-reverse-clam': ('侧卧反向蚌式', 'hip-abductors glute-max', 1, 'strength', 'mat', 'side_lying', 1, R, 12, 2, H,
                       POINTS.get('h-reverse-clam'), '膝', None),
    'h-sumo-pry': ('相扑深蹲肘推膝停留', 'adductors glute-max', 0, 'stretch', 'none', 'standing', 3, T, 30, 1, H,
                   POINTS.get('h-sumo-pry'), '膝', 'h-squat'),
    'h-wall-straddle': ('靠墙仰卧 V 字分腿', 'adductors hamstrings', 0, 'stretch', 'wall', 'supine', 1, T, 45, 1, H,
                        POINTS.get('h-wall-straddle'), '', None),
    's-9090': ('90/90 坐姿换髋', 'glute-max', 0, 'mobility', 'mat', 'seated', 1, T, 40, 1, H,
               POINTS.get('s-9090'), '膝', None),
    's-butterfly': ('蝴蝶式', 'adductors', 0, 'stretch', 'mat', 'seated', 1, T, 40, 1, H,
                    POINTS.get('s-butterfly'), '', None),
    's-figure4': ('仰卧 4 字拉伸', 'glute-max', 1, 'stretch', 'mat', 'supine', 1, T, 30, 1, H,
                  POINTS.get('s-figure4'), '', None),
    's-frog': ('青蛙式', 'adductors', 0, 'stretch', 'mat', 'quadruped', 3, T, 40, 1, H,
               POINTS.get('s-frog'), '膝', 's-butterfly'),
    's-kneel-hipflex': ('半跪髋屈肌拉伸', 'hip-flexors', 1, 'stretch', 'mat', 'kneeling', 1, T, 30, 1, H,
                        POINTS.get('s-kneel-hipflex'), '膝', None),
    's-lizard': ('蜥蜴式低弓步', 'hip-flexors', 1, 'stretch', 'mat', 'kneeling', 3, T, 30, 1, H,
                 POINTS.get('s-lizard'), '', 'o-stand-lunge'),
    's-pigeon': ('鸽子式（直立扶砖版）', 'glute-max', 1, 'stretch', 'mat', 'seated', 3, T, 30, 1, H,
                 POINTS.get('s-pigeon'), '膝', 's-figure4'),
    's-seated-fold': ('坐姿体前屈', 'hamstrings', 0, 'stretch', 'mat', 'seated', 1, T, 40, 1, H,
                      POINTS.get('s-seated-fold'), '腰', None),
    'o-seated-fig4': ('坐姿四字前压', 'glute-max', 1, 'stretch', 'chair', 'seated', 1, T, 30, 1, HO,
                      POINTS.get('o-seated-fig4'), '膝', None),
    'o-seated-ham': ('坐姿腘绳肌前伸', 'hamstrings', 1, 'stretch', 'chair', 'seated', 1, T, 30, 1, HO,
                     POINTS.get('o-seated-ham'), '', None),
    'o-stand-lunge': ('扶椅站姿弓步屈髋拉伸', 'hip-flexors', 1, 'stretch', 'chair', 'standing', 1, T, 30, 1, HO,
                      POINTS.get('o-stand-lunge'), '腰', None),
    'o-stand-crossreach': ('扶椅站姿交叉侧伸', 'hip-abductors', 1, 'stretch', 'chair', 'standing', 1, T, 30, 1, HO,
                           POINTS.get('o-stand-crossreach'), '', None),
    't-seated-straddle-lift-1leg': ('坐姿分腿单腿抬起', 'hip-flexors', 0, 'core', 'mat', 'seated', 3, R, 8, 2, H,
                                    POINTS.get('t-seated-straddle-lift-1leg'), '', 'n-leg-circles'),
    'n-seated-ir-drop': ('坐姿后撑单膝内倒', 'glute-max hip-abductors', 0, 'mobility', 'mat', 'seated', 1, R, 8, 1, H,
                         POINTS.get('n-seated-ir-drop'), '膝', None),
    'n-windshield': ('仰卧雨刷式', 'glute-max hip-abductors', 0, 'mobility', 'mat', 'supine', 1, R, 8, 1, H,
                     POINTS.get('n-windshield'), '', None),
    'n-chair-wiper': ('坐椅雨刷（膝内倒）', 'hip-abductors glute-max', 0, 'mobility', 'chair', 'seated', 1, R, 6, 1, HO,
                      POINTS.get('n-chair-wiper'), '膝', None),
    'n-prone-ir': ('俯卧小腿外摆', 'hip-abductors glute-max', 0, 'mobility', 'mat', 'prone', 1, R, 10, 1, H,
                   POINTS.get('n-prone-ir'), '膝', None),
    'n-half-split': ('半跪半劈叉', 'hamstrings', 1, 'stretch', 'block', 'kneeling', 1, T, 30, 1, H,
                     POINTS.get('n-half-split'), '膝 腰', 'o-seated-ham'),
    'n-prone-hip-ext': ('俯卧屈膝抬腿', 'glute-max', 1, 'strength', 'mat', 'prone', 1, R, 10, 2, H,
                        POINTS.get('n-prone-hip-ext'), '腰', None),
    'n-slider-lateral': ('滑垫侧向滑', 'adductors', 1, 'mobility', 'slider', 'standing', 3, R, 8, 2, H,
                         POINTS.get('n-slider-lateral'), '膝', 'h-adductor-rock'),
    'n-wide-fold': ('站姿宽距体前屈（扶椅）', 'adductors hamstrings', 0, 'stretch', 'chair', 'standing', 1, T, 30, 1, HO,
                    POINTS.get('n-wide-fold'), '腰', None),
    'n-straddle-fold': ('坐姿分腿体前屈', 'adductors hamstrings', 0, 'stretch', 'block', 'seated', 1, T, 40, 1, H,
                        POINTS.get('n-straddle-fold'), '腰', None),
    'n-pelvis-circle': ('站姿骨盆画圈', 'hip-flexors glute-max hip-abductors', 0, 'mobility', 'none', 'standing', 1, T, 30, 1, HO,
                        POINTS.get('n-pelvis-circle'), '', None),
    'n-squat-shift': ('低位蹲姿左右移重心', 'adductors glute-max', 0, 'mobility', 'none', 'standing', 3, T, 30, 1, H,
                      POINTS.get('n-squat-shift'), '膝', 'h-adductor-rock'),
    'n-leg-circles': ('仰卧直腿画圈', 'hip-flexors hip-abductors', 1, 'mobility', 'mat', 'supine', 1, R, 6, 1, H,
                      POINTS.get('n-leg-circles'), '腰', None),
    'n-thomas-test': ('仰卧单膝抱胸', 'hip-flexors', 1, 'stretch', 'mat', 'supine', 1, T, 30, 1, H,
                      POINTS.get('n-thomas-test'), '髋', None),
}

# Repetition timing inside the 8 s loop, from each spec's header comment ("2 reps / 8 s").
ONE_REP_PER_LOOP = {'h-band-leg-out', 'h-wall-straddle', 'h-seated-reachback'}
# Loops that show several reps of their own pattern but no stated timing: count at a calm pace.
CALM_REP_SECONDS = 3.0

SPEC_DIR = ROOT.parent.parent / 'refs' / '3D-Pose-Hub' / 'drill-anim' / 'specs'
HIPLAB = {d['id']: d for d in json.loads(
    (ROOT.parent.parent / 'refs' / 'HipLab' / 'assets' / 'hip' / 'hip-content.json').read_text())['drills']}
# Clips that come from Pose-Hub v0.2.0 (dark soft-v1, as bundled by HipLab) vs. the
# Pose-Hub Drive archive green-screen masters (keyed to the same dark background here).
SOFT_V1 = set(HIPLAB)


def rep_seconds(i, mode):
    if mode != R:
        return None
    if i in ONE_REP_PER_LOOP:
        return 8.0
    spec = SPEC_DIR / f'{i}.js'
    text = spec.read_text() if spec.exists() else ''
    import re
    m = re.search(r'(\d+)\s*reps?\s*/\s*(\d+)\s*s', text)
    if m:
        return round(int(m.group(2)) / int(m.group(1)), 2)
    return CALM_REP_SECONDS


def main():
    out = []
    for i, v in D.items():
        (name, muscles, uni, cat, eq, pos, lvl, mode, amount, sets, scenes, cue, cautions, alt) = v
        assert cue, i
        assert alt is None or alt in D, (i, alt)
        h = HIPLAB.get(i)
        poster_t = h['media']['poster_time_seconds'] if h else 1.0
        out.append({
            'id': i,
            'name': name,
            'muscles': [MUSCLE[m] for m in muscles.split()],
            'unilateral': bool(uni),
            'category': cat,
            'equipment': [] if eq == 'none' else [eq],
            'position': pos,
            'level': lvl,
            'scenes': scenes,
            'dose': {'mode': mode, 'sets': sets,
                     **({'reps': amount} if mode == R else {'seconds': amount}),
                     'restSeconds': 30 if cat in ('strength', 'core', 'cardio') else 10},
            'repSeconds': rep_seconds(i, mode),
            'cue': cue,
            'cautions': [c for c in cautions.split() if c],
            'alternative': alt,
            'media': {
                'video': f'assets/drill_media/sf-{i.lower()}.mp4',
                'poster': f'assets/drill_media/sf-{i.lower()}.jpg',
                'loopSeconds': 8.0,
                'posterSeconds': poster_t,
                'source': 'pose-hub-v0.2.0' if i in SOFT_V1 else 'pose-hub-drive-greenscreen',
            },
        })
    path = ROOT / 'assets' / 'library' / 'exercises.json'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'schemaVersion': 1, 'generatedBy': 'tools/library/build_library.py',
                                'exercises': out}, ensure_ascii=False, indent=1) + '\n')
    print(len(out), 'exercises ->', path.relative_to(ROOT))


if __name__ == '__main__':
    main()
