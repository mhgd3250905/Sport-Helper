#!/usr/bin/env python3
"""English wording for SF's voice lines (2026-11-06).

Writes `text.en` next to every `text.zh` in assets/packs/*/pack.json and adds
`en` to voice.languages / voice.voices. Then render with
`tools/voice/build_voice.py build --lang en` and re-seal the speech bundle.

Shared lines (_common) reuse Flare's English wording (Flare app
tools/trainer_voice/english-text.json, same drill-pack ids) plus `p.last_rep`
(HipLab tools/voice/voice_lines.py: "Last one"). Exercise packs follow SF's
Chinese templates exactly:
  intro  = name + "，练/拉伸/活动 <parts>"  ->  "<Name>. Works/Stretches/Mobilizes <parts>."
  rest   = "放松一下。下一组记住，<cue>"    ->  "Relax for a moment. Next set, remember: <cue>"
  side_switch = "左侧同样，<cue>"          ->  "Now the left side. <cue>"
  finish = name + "，完成"                 ->  "<Name>, done."
so only names and key points are translated below (per pack, cue1..cue3).

    python3 tools/voice/english_text.py          # write text.en into the packs
    python3 tools/voice/english_text.py --check  # exit 1 if any zh line lacks en
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / 'assets/packs'
EN_VOICE = 'en-US-JennyNeural'  # HipLab's English voice (tools/voice/build_voice.py)

COMMON = {
    'p.welcome': 'Get ready to train.',
    'p.total': 'Total time, about',
    'p.first': 'First exercise.',
    'p.next': 'Next exercise.',
    'p.go': 'Start.',
    'p.go_right': 'Right side. Start.',
    'p.switch_left': 'Switch left.',
    'p.rest': 'Rest.',
    'p.nice': 'Well done.',
    'p.di': 'Number',
    'p.last_set': 'Last set.',
    'p.round_done': 'Round complete.',
    'p.ten_left': 'Ten seconds left.',
    'p.half': 'Halfway. Keep going.',
    'p.finish': 'Training complete. Well done.',
    'p.per_side': 'per side',
    'p.resume': 'Resume.',
    'p.slow': 'Slow down. Stay in control.',
    'p.paused': 'Paused.',
    'u.min': 'minutes',
    'u.sec': 'seconds',
    'u.reps': 'repetitions',
    'u.sets': 'sets',
    'u.rounds': 'rounds',
}
# The last counted rep (SDK VoiceCall.lastRep). New in both languages: SF had
# no such line, so a custom 15 said 「十五」 instead of 「最后一个」.
LAST_REP = {'zh': '最后一个', 'en': 'Last one.'}

_ONES = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
         'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
         'sixteen', 'seventeen', 'eighteen', 'nineteen']
_TENS = {2: 'twenty', 3: 'thirty', 4: 'forty', 5: 'fifty', 6: 'sixty'}


def number_en(n):
    if n < 20:
        return _ONES[n]
    t, o = divmod(n, 10)
    return _TENS[t] + (f' {_ONES[o]}' if o else '')  # Flare: "twenty one"


VERB = {'练': 'Works', '拉伸': 'Stretches', '活动': 'Mobilizes'}
PART = {
    '臀部': 'the glutes', '臀部外侧': 'the outer hips', '大腿内侧': 'the inner thighs',
    '大腿后侧': 'the hamstrings', '大腿前侧': 'the quads', '腰两侧': 'the sides of the waist',
    '背部': 'the back', '上背': 'the upper back', '下背': 'the lower back',
    '肩膀': 'the shoulders', '肩关节': 'the shoulder joint', '胸部': 'the chest',
    '腹部': 'the abs', '小腿': 'the calves', '小腿前侧': 'the shins',
    '手臂后侧': 'the triceps', '手臂前侧': 'the biceps', '髋前侧': 'the front of the hips',
}

# id -> (spoken English name, [cue1, cue2, cue3] as present in the pack)
PACKS_EN = {
    'glute-max-A': ('Single-leg glute bridge', [
        'One leg straight, push through the other heel and lift your hips',
        'Drive the hips up with your glutes, keep the pelvis level']),
    'h-9090-liftoff': ('Ninety-ninety rear leg lift-off', [
        'Sit tall, lift the back knee slowly, then lower it slowly']),
    'h-adductor-rock': ('Quadruped adductor rock-back', [
        'One leg out to the side, sit your hips back slowly',
        'Rock the hips back, feel the inner thigh lengthen']),
    'h-banana': ('Supine banana stretch', [
        'Lie on your back, move your arms and legs to the same side',
        'Curve your body into a banana shape, feel your side lengthen']),
    'h-band-hip-ir': ('Seated band hip internal rotation', [
        'Sit on the chair, band around the ankle',
        'Keep the knee still, turn the shin outward']),
    'h-band-leg-out': ('Supine band leg lower-out', [
        'Band around the foot, raise the straight leg',
        'Keep the leg straight and lower it out to the side slowly']),
    'h-band-pallof': ('Band Pallof press', [
        'Stand side-on to the anchor, feet steady',
        'Press both hands straight out, do not let the band twist you']),
    'h-band-pull-apart': ('Band pull-apart', [
        'Arms straight out in front, hold the band',
        'Arms straight at shoulder height, pull the band apart',
        'Pull it apart to your chest, shoulders down']),
    'h-band-row': ('Seated band row', [
        'Sit tall, pull your elbows back close to your body, squeeze your shoulder blades']),
    'h-bridge-march': ('Glute bridge march', [
        'Lift into a bridge first, keep the pelvis level',
        'Hold the bridge steady, lift one knee at a time']),
    'h-bulgarian': ('Chair Bulgarian split squat', [
        'Back foot on the chair, front knee over the toes, lower straight down',
        'Lower until the front thigh is nearly level']),
    'h-butterfly-active': ('Active supine butterfly', [
        'Lie on your back, soles together',
        'Soles together, open the knees slowly and bring them back',
        'Open the knees on purpose, then close them']),
    'h-calf-raise': ('Wall-supported calf raise', [
        'Hands on the wall, stand on the balls of your feet',
        'Lift your heels as high as you can, pause, lower slowly']),
    'h-catcow-quad': ('Quadruped cat-cow', [
        'Breathe in, drop the belly and look up. Breathe out, round the back and look down']),
    'h-chair-dip': ('Chair dip', [
        'Hands on the edge of the chair, hips off the seat',
        'Shoulders down away from your ears, bend the elbows back, then push up',
        'Bend the elbows to lower, shoulders down']),
    'h-chair-kickback': ('Chair-supported standing kickback', [
        'Hold the chair, stand steady, do not lean forward',
        'Hold the chair back, lift the leg behind you, do not arch your back',
        'Kick the leg back and up, squeeze your glutes']),
    'h-chair-lat': ('Chair-supported lat stretch', [
        'Hands on the chair, push your hips back, let your chest sink',
        'Chest sinks, feel the stretch under your arms']),
    'h-chair-step-up': ('Chair step-up', [
        'Whole foot on the seat, stand up with the front leg',
        'Drive up with the front leg, do not bounce off the back foot']),
    'h-chair-tspine': ('Kneeling chair thoracic extension', [
        'Kneel, elbows on the seat',
        'Elbows on the seat, let your chest sink slowly']),
    'h-cobra': ('Cobra stretch', [
        'Lie face down, hands beside your chest',
        'Hips on the floor, push through your hands and lift your chest slowly',
        'Press the upper body up, hips down, shoulders down']),
    'h-couch-stretch': ('Couch stretch, rear foot on a stool', [
        'Back of the rear foot against the seat',
        'Back foot up, squeeze your glutes, hips forward']),
    'h-crunch': ('Crunch', [
        'Knees bent, lie on your back, hands lightly by your ears',
        'Low back on the floor, curl your shoulder blades up with your abs',
        'Curl the upper back up with your abs, do not tuck your chin']),
    'h-db-curl': ('Alternating dumbbell curl', [
        'Upper arms against your body, move only the forearms',
        'Curl one side at a time, do not swing your body']),
    'h-db-floor-press': ('Dumbbell floor press', [
        'Lie on your back, knees bent, upper arms on the floor',
        'Upper arms about forty-five degrees from your body, press the dumbbells up over your chest',
        'Press straight up, then lower slowly']),
    'h-db-lateral': ('Dumbbell lateral raise', [
        'Elbows slightly bent, shoulders down',
        'Elbows soft, raise out to the side to shoulder height, do not shrug',
        'Raise your arms to shoulder height']),
    'h-db-press': ('Standing dumbbell shoulder press', [
        'Brace your abs, press the dumbbells from your shoulders overhead, do not lean back',
        'Press the dumbbells straight overhead']),
    'h-db-rdl': ('Dumbbell Romanian deadlift', [
        'Slide the dumbbells down your legs, hips back, keep your back straight']),
    'h-db-reverse-fly': ('Bent-over dumbbell reverse fly', [
        'Hinge forward with a flat back, open your arms to the sides, squeeze your shoulder blades']),
    'h-db-row': ('Chair-supported one-arm dumbbell row', [
        'One hand on the chair, back flat',
        'Back flat, pull your elbow back to your side',
        'Pull the elbow back and up, squeeze the shoulder blade']),
    'h-dd-shoulder': ('Downward dog shoulder press', [
        'Push the floor away, hips up and back, chest toward your thighs',
        'Press your chest toward your legs']),
    'h-forearm-plank': ('Forearm plank', [
        'Elbows right under your shoulders',
        'Elbows under shoulders, body in one straight line, hips neither sagging nor piked']),
    'h-good-morning': ('Bodyweight good morning', [
        'Knees soft, push your hips back',
        'Back straight, push your hips back until the hamstrings feel tight, then stand up']),
    'h-hip-gate': ('Chair-supported hip gate opener', [
        'Hold the chair, stand steady, lift the knee',
        'Hold the chair, lift the knee and circle it open']),
    'h-incline-pushup': ('Incline push-up on a stool', [
        'Hands firm on the stool, body in one straight line, chest down close, then push up']),
    'h-knee-hug': ('Supine knees to chest', [
        'Hug your knees and breathe slowly',
        'Knees toward your chest, relax your back']),
    'h-quad-cars': ('Quadruped hip circles', [
        'On all fours, keep your trunk steady',
        'On all fours, draw a big circle with the knee, keep the low back still',
        'Circle the knee slowly out and back']),
    'h-reverse-clam': ('Side-lying reverse clamshell', [
        'Lie on your side, knees bent and together',
        'Knees together, lift the shin up slowly',
        'Lift the shin up to rotate the hip in']),
    'h-reverse-crunch': ('Reverse crunch', [
        'Lie on your back, knees bent, legs up',
        'Knees bent, curl your pelvis off the floor, lower slowly',
        'Curl the pelvis up, knees toward your chest']),
    'h-russian-twist': ('Russian twist, feet down', [
        'Sit and lean back, feet on the floor',
        'Lean back a little, back straight, turn your shoulders side to side',
        'Turn the upper body side to side, keep the pelvis still']),
    'h-seated-reachback': ('Seated reach-back shoulder stretch', [
        'Hands on the floor behind you, slide your hips forward slowly',
        'Slide your hips forward, open your chest']),
    'h-side-er': ('Side-lying external rotation', [
        'Elbow against your side, rotate the forearm up',
        'Rotate the forearm up, do not let the shoulder roll forward']),
    'h-side-leg-raise': ('Standing side leg raise', [
        'Stand tall, toes forward',
        'Stay upright, lift the leg out to the side, then lower slowly']),
    'h-squat': ('Bodyweight squat', [
        'Feet a little wider than hips, toes slightly out',
        'Sit your hips back and down, knees in line with your toes']),
    'h-step-jack': ('Low-impact step jack', [
        'Step out to the side, one side at a time',
        'Step one foot out to the side and raise both arms',
        'Raise the arms at the same time, keep the rhythm']),
    'h-sumo-pry': ('Sumo squat hold with elbow pry', [
        'Wide stance, sit into a deep squat, palms together',
        'Sit low and gently press the knees out with your elbows',
        'Elbows push the knees out, lift your chest']),
    'h-superman': ('Prone superman', [
        'Lie face down, arms and legs straight',
        'Lift your arms and legs gently off the floor, neck neutral',
        'Lift arms and legs together, pause, then lower']),
    'h-supine-twist': ('Supine bent-knee twist', [
        'Lie on your back, knees bent, arms open',
        'Drop both knees to one side, shoulders stay down']),
    'h-tabletop': ('Reverse tabletop bridge', [
        'Hands behind your shoulders, fingers forward',
        'Hands under your shoulders, push the floor and lift your hips to table height',
        'Lift the hips into a tabletop, open your chest']),
    'h-tib-raise': ('Wall tibialis raise', [
        'Back against the wall, lift your toes and lower them, heels stay down']),
    'h-wall-angel': ('Wall angel', [
        'Back and head on the wall, arms in a W',
        'Back and arms on the wall, slide up slowly, then down',
        'Slide your arms up the wall, keep your low back on the wall']),
    'h-wall-calf': ('Wall calf stretch', [
        'Back leg straight, heel down, lean forward',
        'Lean forward, feel the calf lengthen']),
    'h-wall-straddle': ('Legs up the wall straddle', [
        'Hips against the wall, legs up the wall',
        'Legs up the wall, let them fall open to the sides',
        'Let your legs slide apart slowly']),
    'hip-flexors-A': ('Seated pike leg lift', [
        'Sit tall, lift the straight leg, pause, then lower',
        'Lift the straight leg off the floor, hold for one second']),
    'n-chair-wiper': ('Seated knee drop-in', [
        'Sit on the chair, feet apart',
        'Sitting on the chair, swing the shins out and drop the knees in',
        'Drop the knees in, one side at a time']),
    'n-half-split': ('Half-kneeling half split', [
        'Half kneel, front leg straight',
        'Front leg straight, fold forward from the hips, hands on the blocks',
        'Sit the hips back, feel the hamstrings lengthen']),
    'n-leg-circles': ('Supine straight-leg circles', [
        'Lie on your back, one leg straight up',
        'Leg straight, draw slow circles, keep the pelvis still']),
    'n-pelvis-circle': ('Standing pelvis circles', [
        'Hands on hips, knees soft',
        'Feet still, circle your pelvis slowly']),
    'n-prone-hip-ext': ('Prone bent-knee hip extension', [
        'Lie face down, one knee bent',
        'Face down, knee bent, lift the thigh slowly off the floor',
        'Push the sole toward the ceiling, squeeze your glutes']),
    'n-prone-ir': ('Prone hip internal rotation', [
        'Lie face down, knees bent to ninety degrees',
        'Face down, knees bent, swing the shins out to the sides']),
    'n-seated-ir-drop': ('Seated hip internal rotation drop', [
        'Sit on the floor, hands behind you, knees bent',
        'Hands on the floor behind you, drop one knee inward']),
    'n-seated-knee-lift': ('Seated knee lift hover', [
        'Sit tall, lift the knee and hover',
        'Lift the knee off the seat, hold for three seconds']),
    'n-seated-squeeze': ('Seated block knee squeeze', [
        'Something soft between your knees',
        'Squeeze the yoga block hard between your knees',
        'Squeeze in, hold for three seconds, then release']),
    'n-slider-lateral': ('Slider lateral slide', [
        'Slide one foot out to the side, then bring it back']),
    'n-squat-shift': ('Low squat side-to-side shift', [
        'Wide stance, deep squat',
        'Stay low, shift your weight slowly side to side']),
    'n-straddle-fold': ('Seated straddle forward fold', [
        'Sit on the floor, legs wide apart',
        'Legs apart, sit tall, lean forward slowly from the hips',
        'Lean forward with a straight back']),
    'n-thomas-test': ('Supine single knee to chest', [
        'Lie on your back, hug one knee to your chest',
        'Hug one knee, let the other leg relax straight']),
    'n-wide-fold': ('Standing wide-leg fold with a chair', [
        'Wide stance, hands on the chair',
        'Feet apart, hold the chair, fold forward from the hips',
        'Lean forward with a flat back, feel the inner and back thighs lengthen']),
    'n-windshield': ('Supine windshield wipers', [
        'Lie on your back, knees bent, feet wide',
        'Drop both knees slowly side to side, shoulders stay down']),
    'o-seated-catcow': ('Seated cat-cow', [
        'Sit on the front of the chair, hands on your knees',
        'On the front half of the chair, breathe in and lift your chest, breathe out and round your back',
        'Chest up and look up, then round your back and look down']),
    'o-seated-fig4': ('Seated figure four stretch', [
        'Ankle on the knee, keep the back straight and lean forward',
        'Lean forward with a straight back, feel the glutes lengthen']),
    'o-seated-ham': ('Seated hamstring stretch', [
        'Sit on the front edge of the chair, one leg straight',
        'Leg straight, toes up, lean forward with a straight back',
        'Lean forward with a straight back, feel the hamstrings lengthen']),
    'o-seated-twist': ('Seated chair twist', [
        'Sit tall, hold the chair back and turn slowly. Grow tall first, then turn',
        'Breathe out as you turn to one side']),
    'o-stand-crossreach': ('Chair-supported cross-leg side reach', [
        'Cross one leg behind, reach your arm up and over to the side',
        'Reach up and over, feel the outer hip lengthen']),
    'o-stand-lunge': ('Chair-supported standing hip flexor stretch', [
        'Hold the chair in a lunge, back leg straight',
        'Hold the chair, squeeze the back glute, push your hips forward']),
    'o-stand-quad': ('Chair-supported standing quad stretch', [
        'Hold the chair, pull your foot toward your glutes, knee pointing down',
        'Knee points down, feel the front of the thigh lengthen']),
    'o-stand-sidebend': ('Standing overhead side bend', [
        'Arms overhead, feet steady',
        'Arms overhead, bend to the side, do not lean forward']),
    's-9090': ('Ninety-ninety hip switch', [
        'Bend both legs to ninety degrees',
        'Both legs at right angles, sit tall, then switch sides',
        'Switch sides, keep your trunk upright']),
    's-butterfly': ('Seated butterfly stretch', [
        'Soles together, sit tall, let the knees drop',
        'Let the knees drop on their own, do not force them']),
    's-figure4': ('Supine figure four stretch', [
        'Ankle over the other knee, pull the legs toward your chest',
        'Hold the thigh and pull it toward your chest']),
    's-frog': ('Frog stretch', [
        'Knees wide, toes out, sit your hips back slowly']),
    's-kneel-hipflex': ('Half-kneeling hip flexor stretch', [
        'Half kneel, trunk upright',
        'Squeeze the back glute and ease the hips forward']),
    's-lizard': ('Lizard lunge', [
        'Front foot outside your hand, sink the hips',
        'Sink the hips, breathe and relax']),
    's-pigeon': ('Upright pigeon with blocks', [
        'Front leg bent across in front of you',
        'Stay upright, hands on the blocks, sink the hips',
        'Lean forward, feel the glutes lengthen']),
    's-seated-fold': ('Seated forward fold', [
        'Sit on the floor, legs straight',
        'Knees straight, fold forward from the hips',
        'Lean forward from the hips with a straight back']),
    't-seated-straddle-lift-1leg': ('Seated straddle single-leg lift', [
        'Legs apart, sit tall, lift one leg off the floor']),
    'w-bird-dog': ('Bird dog', [
        'Hands under shoulders, knees under hips',
        'Reach the opposite arm and leg long, keep your back level and still']),
    'w-chair-hip-thrust': ('Chair hip thrust', [
        'Upper back on the edge of the chair, feet planted',
        'Upper back on the chair, drive your hips up until your body is in one straight line']),
    'w-clamshell': ('Side-lying clamshell', [
        'Feet together, open the top knee, do not let the pelvis roll back']),
    'w-dead-bug': ('Dead bug', [
        'Low back pressed to the floor, reach the opposite arm and leg away slowly',
        'Lower the opposite arm and leg slowly, low back stays down']),
    'w-feet-on-chair-bridge': ('Feet-on-chair glute bridge', [
        'Heels on the seat, knees slightly bent',
        'Heels on the chair, squeeze your glutes and lift your hips, ribs down',
        'Feel the hamstrings and glutes working as you lift']),
    'w-fire-hydrant': ('Quadruped fire hydrant', [
        'Hands under shoulders, knees under hips',
        'On all fours, lift the knee out to the side, do not tilt your trunk']),
    'w-prone-swimmer': ('Prone swimmers', [
        'Lie face down, forehead just off the floor',
        'Chest slightly up, sweep your arms from the front to your sides',
        'Arms sweep an arc close to the floor, shoulder blades down']),
    'w-wall-sit': ('Wall sit', [
        'Slide down the wall, knees at about ninety degrees',
        'Back on the wall, thighs nearly level, knees over the ankles',
        'Knees in line with your toes, breathe steadily']),
}


def intro_en(name_en, zh_rest):
    for verb_zh, verb_en in VERB.items():
        if zh_rest.startswith(verb_zh):
            parts = zh_rest[len(verb_zh):].replace('和', '、').split('、')
            words = [PART[p] for p in parts]
            joined = words[0] if len(words) == 1 else ', '.join(words[:-1]) + ' and ' + words[-1]
            return f'{name_en}. {verb_en} {joined}.'
    raise KeyError(zh_rest)


def english_lines(pack):
    """line id -> English text for one pack (raises on anything unmapped)."""
    lines = {l['id']: l['text']['zh'] for l in pack['voice']['lines']}
    if pack['id'] == '_common':
        out = {}
        for lid in lines:
            if lid.startswith('n.'):
                out[lid] = number_en(int(lid[2:]))
            elif lid == 'p.last_rep':
                out[lid] = LAST_REP['en']
            else:
                out[lid] = COMMON[lid]
        return out
    name_en, cues_en = PACKS_EN[pack['id']]
    cue_ids = sorted(k for k in lines if k.startswith('cue'))
    if len(cue_ids) != len(cues_en):
        raise ValueError(f"{pack['id']}: {len(cue_ids)} cues, {len(cues_en)} English")
    by_zh = {lines[k]: en for k, en in zip(cue_ids, cues_en)}
    name_zh = lines['name']
    out = {'name': name_en, 'finish': f'{name_en}, done.',
           'intro': intro_en(name_en, lines['intro'][len(name_zh) + 1:])}
    for k, en in zip(cue_ids, cues_en):
        out[k] = en
    out['rest'] = 'Relax for a moment. Next set, remember: ' + \
        by_zh[lines['rest'].removeprefix('放松一下。下一组记住，')]
    if 'side_switch' in lines:
        out['side_switch'] = 'Now the left side. ' + \
            by_zh[lines['side_switch'].removeprefix('左侧同样，')]
    return out


def main():
    check = '--check' in sys.argv
    missing = 0
    for f in sorted(PACKS.glob('*/pack.json')):
        pack = json.loads(f.read_text(encoding='utf-8'))
        v = pack['voice']
        if pack['id'] == '_common' and not any(l['id'] == 'p.last_rep' for l in v['lines']):
            if check:
                missing += 1
                continue
            at = next(i for i, l in enumerate(v['lines']) if l['id'] == 'p.last_set') + 1
            v['lines'].insert(at, {'id': 'p.last_rep', 'role': 'phrase',
                                   'text': {'zh': LAST_REP['zh']}})
        en = english_lines(pack)
        for line in v['lines']:
            if check:
                missing += 'en' not in line['text']
            else:
                line['text']['en'] = en[line['id']]
        if not check:
            if 'en' not in v['languages']:
                v['languages'].append('en')
            v['voices']['en'] = EN_VOICE
            f.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    if check and missing:
        print(f'{missing} lines without English')
        sys.exit(1)


if __name__ == '__main__':
    main()
