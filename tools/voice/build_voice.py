#!/usr/bin/env python3
"""Pre-recorded Chinese coaching clips for 智能健身助手 (same approach as HipLab
tools/voice/build_voice.py): edge-tts neural voice → ffmpeg trim + loudness
normalise → mono AAC .m4a in assets/voice/zh/, plus assets/voice/manifest.json
(clip lengths in ms, chime lengths, spoken lines for subtitles).

    PYTHONPATH=/path/to/edge_tts python3 tools/voice/build_voice.py [--voice zh-CN-XiaoxiaoNeural]

Only clips whose text/voice changed are regenerated (cache: tools/voice/.cache/).
RISK: edge-tts uses Microsoft Edge's read-aloud endpoint; its terms for
commercial use are unclear. Before a store release regenerate the same lines
with the official Azure Speech API (same voices) — see docs/risks.md.
"""
import argparse, asyncio, hashlib, json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/voice/zh'
CACHE = Path(__file__).parent / '.cache'
CHIMES = ROOT / 'assets/voice/chime'
NUM = '零一二三四五六七八九'


def zh_number(n):
    if n < 10: return NUM[n]
    if n < 20: return '十' + (NUM[n % 10] if n % 10 else '')
    return NUM[n // 10] + '十' + (NUM[n % 10] if n % 10 else '')


PHRASES = {
    'p.welcome': '准备开始训练', 'p.total': '全程大约', 'p.first': '第一个动作', 'p.next': '下一个动作',
    'p.go': '开始', 'p.go_right': '先做右侧，开始', 'p.switch_left': '换左侧', 'p.rest': '休息',
    'p.nice': '很好', 'p.di': '第', 'p.last_set': '最后一组', 'p.round_done': '这一轮完成',
    'p.ten_left': '还剩十秒', 'p.half': '坚持住，已经过半', 'p.finish': '训练完成，做得很好',
    'p.per_side': '每侧', 'p.resume': '继续', 'p.slow': '动作放慢，控制节奏', 'p.paused': '已暂停',
    'u.min': '分钟', 'u.sec': '秒', 'u.reps': '次', 'u.sets': '组', 'u.rounds': '轮',
}


def lines():
    out = dict(PHRASES)
    for n in range(1, 61):
        out[f'n.{n}'] = zh_number(n)
    lib = json.loads((ROOT / 'assets/library/exercises.json').read_text())['exercises']
    for e in lib:
        out[f"ex.{e['id']}"] = e['name'].replace('（', '，').replace('）', '').replace('/', '')
        out[f"cue.{e['id']}"] = e['cue']
    return out


async def tts(text, voice, path):
    import edge_tts
    await edge_tts.Communicate(text, voice, rate='+4%').save(str(path))


def ms(path):
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                       capture_output=True, text=True)
    return int(round(float(r.stdout.strip()) * 1000))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--voice', default='zh-CN-XiaoxiaoNeural')
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True); CACHE.mkdir(exist_ok=True)
    L = lines()
    clips = {}
    for key, text in L.items():
        h = hashlib.sha1(f'{a.voice}|{text}'.encode()).hexdigest()[:16]
        raw = CACHE / f'{h}.mp3'
        dst = OUT / f'{key}.m4a'
        if not raw.exists():
            for attempt in range(3):
                try:
                    asyncio.run(tts(text, a.voice, raw)); break
                except Exception as ex:  # network hiccup
                    print('retry', key, ex, file=sys.stderr)
        stamp = CACHE / f'{h}.done'
        if not dst.exists() or not stamp.exists():
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-threads', '1', '-i', str(raw), '-af',
                            'silenceremove=start_periods=1:start_threshold=-45dB,areverse,'
                            'silenceremove=start_periods=1:start_threshold=-45dB,areverse,'
                            'adelay=40,apad=pad_dur=0.08,loudnorm=I=-16:TP=-2:LRA=7',
                            '-ac', '1', '-ar', '44100', '-c:a', 'aac', '-b:a', '64k', str(dst)], check=True)
            stamp.write_text(key)
        clips[key] = ms(dst)
    stale = [p for p in OUT.glob('*.m4a') if p.stem not in L]
    for p in stale: p.unlink()
    chimes = {p.stem: ms(p) for p in sorted(CHIMES.glob('*.m4a'))}
    manifest = {'schema': 1, 'generatedBy': 'tools/voice/build_voice.py', 'voices': {'zh': a.voice},
                'clips': {'zh': clips}, 'chimes': chimes, 'texts': {},
                'lines': {k: {'zh': v} for k, v in L.items() if k.startswith('cue.')}}
    (ROOT / 'assets/voice/manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n')
    print(len(clips), 'clips;', sum(p.stat().st_size for p in OUT.glob('*.m4a')) // 1024, 'KB')


if __name__ == '__main__':
    main()
