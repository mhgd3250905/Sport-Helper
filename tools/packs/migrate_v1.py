#!/usr/bin/env python3
"""One-off migration (2026-10-19): the M1/M2 library → drill packs.

Reads the old sources and writes assets/packs/<id>/pack.json, moving (git mv)
each clip and poster into its pack so the App keeps exactly one copy:

    assets/library/exercises.json        metadata, default dose, primary cue
    tools/library/exercises.csv          setup / movement cues (cue1, cue2)
    tools/library/spec_meta.json         English name, Pose-Hub muscle groups, spec path
    assets/drill_media/sf-<id>.mp4/.jpg  →  assets/packs/<id>/demo.mp4 / cover.jpg
    assets/drill_media/player.*          →  assets/media_player/ (App shell, not content)
    assets/voice/chime/*.m4a             →  assets/packs/_common/chime/

Voice line texts (intro, 1–3 cues, side switch, rest, finish) are authored
here from the metadata once; from now on pack.json is the source of truth
and is edited by hand. Then run tools/voice/build_voice.py (clips + decoded
lengths) and tools/packs/build_packs.py (file list, index, pubspec).

    python3 tools/packs/migrate_v1.py
"""
import csv
import difflib
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import packlib as P  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PACKS = P.packs_root(ROOT)
OLD_MEDIA = ROOT / 'assets/drill_media'
SNOW = ('Snow Rig © Blender Foundation | studio.blender.org — CC BY 4.0 '
        '(https://creativecommons.org/licenses/by/4.0/). Modified Snow-derived training '
        'character rendered with the 3D-Body drill renderer.')
VOICE_NOTE = ('edge-tts (Microsoft neural voice zh-CN-XiaoxiaoNeural); commercial terms '
              'unclear — regenerate with Azure Speech before a store release.')

# Spoken body areas: plain words instead of anatomy terms.
AREA = {
    '股四头肌': '大腿前侧', '臀大肌': '臀部', '腘绳肌': '大腿后侧', '胸大肌': '胸部',
    '肱三头肌': '手臂后侧', '竖脊肌': '下背', '小腿': '小腿', '臀中肌': '臀部外侧',
    '三角肌': '肩膀', '腹直肌': '腹部', '腹斜肌': '腰两侧', '胫骨前肌': '小腿前侧',
    '肱二头肌': '手臂前侧', '菱形肌·中下斜方': '上背', '背阔肌': '背部', '肩袖': '肩关节',
    '大腿内侧': '大腿内侧', '髋屈肌': '髋前侧',
}
VERB = {'strength': '练', 'core': '练', 'cardio': '练', 'mobility': '活动', 'stretch': '拉伸'}

# Common pack: fixed coaching words, units, numbers 1–60.
PHRASES = {
    'p.welcome': '准备开始训练', 'p.total': '全程大约', 'p.first': '第一个动作', 'p.next': '下一个动作',
    'p.go': '开始', 'p.go_right': '先做右侧，开始', 'p.switch_left': '换左侧', 'p.rest': '休息',
    'p.nice': '很好', 'p.di': '第', 'p.last_set': '最后一组', 'p.round_done': '这一轮完成',
    'p.ten_left': '还剩十秒', 'p.half': '坚持住，已经过半', 'p.finish': '训练完成，做得很好',
    'p.per_side': '每侧', 'p.resume': '继续', 'p.slow': '动作放慢，控制节奏', 'p.paused': '已暂停',
}
UNITS = {'u.min': '分钟', 'u.sec': '秒', 'u.reps': '次', 'u.sets': '组', 'u.rounds': '轮'}
NUM = '零一二三四五六七八九'


def zh_number(n):
    if n < 10:
        return NUM[n]
    if n < 20:
        return '十' + (NUM[n % 10] if n % 10 else '')
    return NUM[n // 10] + '十' + (NUM[n % 10] if n % 10 else '')


def spoken_name(name):
    name = re.sub(r'(\d+)/(\d+)', r'\1 \2', name)  # 90/90 → "90 90"
    return name.replace('（', '，').replace('）', '').replace('/', '')


def similar(a, b):
    """Re-words the same point: close text, or the same opening clause."""
    head = lambda s: re.split(r'[，,]', s)[0]
    chars = [c for c in a if '\u4e00' <= c <= '\u9fff']
    covered = sum(c in b for c in chars) / max(len(chars), 1)
    return (difflib.SequenceMatcher(None, a, b).ratio() >= 0.45 or head(a) == head(b)
            or covered >= 0.75)


def cues_for(primary, row):
    """Setup cue, the reviewed primary cue, then a movement cue — at most 3,
    dropping CSV cues that only re-word one already kept."""
    out = []
    c1, c2 = (row or {}).get('cue1', '').strip(), (row or {}).get('cue2', '').strip()
    if c1 and not similar(c1, primary):
        out.append(c1)
    out.append(primary)
    if c2 and not any(similar(c2, c) for c in out):
        out.append(c2)
    return out[:3], out.index(primary)


def git_mv(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'mv', '-k', str(src.relative_to(ROOT)), str(dst.relative_to(ROOT))],
                   cwd=ROOT, check=True)


def probe_size(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                          'stream=width,height', '-of', 'json', str(path)],
                         capture_output=True, text=True, check=True).stdout
    s = json.loads(out)['streams'][0]
    return s['width'], s['height']


def exercise_pack(e, row, meta):
    cues, primary = cues_for(e['cue'], row)
    name = spoken_name(e['name'])
    areas = []
    for m in e['muscles']:
        a = AREA.get(m, m)
        if any(a.startswith(x) for x in areas):
            continue  # 臀部 already covers 臀部外侧
        areas = [x for x in areas if not x.startswith(a)] + [a]
    where = areas[0] if len(areas) == 1 else '、'.join(areas[:-1]) + '和' + areas[-1]
    intro = f"{name}，{VERB[e['category']]}{where}"
    lines = [
        {'id': 'name', 'role': 'name', 'text': {'zh': name}},
        {'id': 'intro', 'role': 'intro', 'text': {'zh': intro}},
    ]
    for k, c in enumerate(cues, 1):
        lines.append({'id': f'cue{k}', 'role': 'cue', 'text': {'zh': c}})
    if e['unilateral']:
        lines.append({'id': 'side_switch', 'role': 'side_switch',
                      'text': {'zh': f'左侧同样，{cues[primary]}'}})
    lines.append({'id': 'rest', 'role': 'rest', 'text': {'zh': f'放松一下。下一组记住，{cues[-1]}'}})
    lines.append({'id': 'finish', 'role': 'finish', 'text': {'zh': f'{name}，完成'}})

    m = e['media']
    v = ROOT / m['video']
    w, h = probe_size(v)
    v02 = m['source'] == 'pose-hub-v0.2.0'
    pack = {
        'format': P.FORMAT,
        'formatVersion': P.FORMAT_VERSION,
        'kind': 'exercise',
        'id': e['id'],
        'version': '1.0.0',
        'name': {'zh': e['name'], **({'en': meta['nameEn']} if meta.get('nameEn') else {})},
        'category': e['category'],
        'muscles': e['muscles'],
        'muscleGroups': meta.get('groups', []),
        'equipment': e['equipment'],
        'position': e['position'],
        'unilateral': e['unilateral'],
        'level': e['level'],
        'scenes': e['scenes'],
        'defaultDose': e['dose'],
        'cues': {'zh': cues},
        'primaryCue': primary,
        'cautions': e['cautions'],
        'contraindications': [],
        'alternative': e['alternative'],
        'media': {
            'cover': 'cover.jpg',
            'coverSeconds': m['posterSeconds'],
            'video': 'demo.mp4',
            'width': w,
            'height': h,
            'loopSeconds': m['loopSeconds'],
            'repSeconds': e['repSeconds'],
            **({'showsSide': 'right'} if e['unilateral'] else {}),
        },
        'voice': {
            'languages': ['zh'],
            'voices': {'zh': 'zh-CN-XiaoxiaoNeural'},
            'requires': P.COMMON_ID,
            'lines': lines,
        },
        'credits': {
            'media': ('3D-Pose-Hub v0.2.0 dark soft-v1 clip (as frozen in HipLab), re-encoded 720²'
                      if v02 else
                      '3D-Pose-Hub Drive archive green-screen master, keyed onto #101013 '
                      'by tools/media/prepare_media.py'),
            'mediaSource': m['source'],
            'spec': meta.get('spec'),
            'license': SNOW,
            'voice': VOICE_NOTE,
            'text': 'SmartFit (智能健身助手) authors, 2026-10-19',
        },
    }
    git_mv(v, PACKS / e['id'] / 'demo.mp4')
    git_mv(ROOT / m['poster'], PACKS / e['id'] / 'cover.jpg')
    return pack


def common_pack():
    lines = [{'id': k, 'role': 'phrase', 'text': {'zh': v}} for k, v in PHRASES.items()]
    lines += [{'id': k, 'role': 'unit', 'text': {'zh': v}} for k, v in UNITS.items()]
    lines += [{'id': f'n.{n}', 'role': 'count', 'text': {'zh': zh_number(n)}} for n in range(1, 61)]
    chimes = {}
    for c in sorted((ROOT / 'assets/voice/chime').glob('*.m4a')):
        git_mv(c, PACKS / P.COMMON_ID / 'chime' / c.name)
        chimes[c.stem] = {'file': f'chime/{c.name}'}
    return {
        'format': P.FORMAT,
        'formatVersion': P.FORMAT_VERSION,
        'kind': 'common',
        'id': P.COMMON_ID,
        'version': '1.0.0',
        'name': {'zh': '公共语音包：数字、单位、口令、提示音', 'en': 'Shared counts, units, calls, chimes'},
        'chimes': chimes,
        'voice': {
            'languages': ['zh'],
            'voices': {'zh': 'zh-CN-XiaoxiaoNeural'},
            'lines': lines,
        },
        'credits': {'voice': VOICE_NOTE,
                    'chimes': 'Synthesised sine tones (ffmpeg), no third-party material.',
                    'text': 'SmartFit (智能健身助手) authors, 2026-10-19'},
    }


def main():
    lib = P.read_json(ROOT / 'assets/library/exercises.json')['exercises']
    rows = {r['id']: r for r in csv.DictReader(
        (ROOT / 'tools/library/exercises.csv').open(encoding='utf-8'), delimiter='|')}
    meta = P.read_json(ROOT / 'tools/library/spec_meta.json')
    PACKS.mkdir(parents=True, exist_ok=True)
    c = common_pack()
    (PACKS / P.COMMON_ID).mkdir(parents=True, exist_ok=True)
    P.write_json(PACKS / P.COMMON_ID / 'pack.json', c)
    for e in lib:
        pack = exercise_pack(e, rows.get(e['id']), meta.get(e['id'], {}))
        P.write_json(PACKS / e['id'] / 'pack.json', pack)
    for f in ('player.html', 'player.js', 'player.css'):
        git_mv(OLD_MEDIA / f, ROOT / 'assets/media_player' / f)
    print(len(lib), 'exercise packs + common pack ->', PACKS.relative_to(ROOT))


if __name__ == '__main__':
    main()
