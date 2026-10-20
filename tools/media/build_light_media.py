#!/usr/bin/env python3
"""Light-stage media for every exercise pack (docs/design-audit-2026-10-19.md §6).

Writes assets/packs/<id>/demo-light.mp4 + cover-light.jpg next to the dark
demo.mp4 / cover.jpg and records them in pack.json as
`media.light = {"video": "demo-light.mp4", "cover": "cover-light.jpg"}`.
Re-seal afterwards: python3 tools/packs/build_packs.py --pubspec pubspec.yaml

Sources (copied, never modified):
  * Pose-Hub v0.2.0 moves: HipLab's light renders (assets/drill_media/light/
    hip-<id>.mp4/.jpg, light stage #EFEFEF + soft floor shadow, built from the
    Pose-Hub alpha frames) → scaled to 720² like the dark clips.
  * Drive green-screen masters (1080², #00FF00): keyed onto the same #EFEFEF
    stage with the same kind of soft shadow under the figure (alpha → blur →
    7 px down → 14 % ink), so both sources read as one set.
One ffmpeg at a time, -threads 2. Skips packs that already have both files.

    python3 tools/media/build_light_media.py --hiplab ../../refs/HipLab --green ../drive/green [--only id,id]
"""
import argparse, json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / 'assets/packs'
STAGE = '0xEFEFEF'
ENC = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '27', '-pix_fmt', 'yuv420p', '-an',
       '-movflags', '+faststart', '-threads', '2']
KEY = ('[0:v]chromakey=0x00FF00:0.30:0.08,despill=type=green:mix=0.6,scale=720:720:flags=lanczos,'
       'format=rgba,split[fg][a];'
       '[a]alphaextract,gblur=sigma=8,lut=y=val*0.14,pad=iw:ih+7:0:7,crop=720:720:0:0[sh];'
       'color=c=black:s=720x720:r=30,format=rgba[blk];[blk][sh]alphamerge[shadow];'
       f'color=c={STAGE}:s=720x720:r=30[bg];[bg][shadow]overlay=shortest=1[b2];'
       '[b2][fg]overlay=shortest=1,format=yuv420p')


def run(a):
    subprocess.run(['ffmpeg', '-v', 'error', '-y'] + a, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hiplab', required=True)
    ap.add_argument('--green', required=True)
    ap.add_argument('--only', default='')
    a = ap.parse_args()
    only = {s for s in a.only.split(',') if s}
    for f in sorted(PACKS.glob('*/pack.json')):
        e = json.loads(f.read_text(encoding='utf-8'))
        if e['kind'] != 'exercise' or (only and e['id'] not in only):
            continue
        i = e['id']
        d = f.parent
        mp4, jpg = d / 'demo-light.mp4', d / 'cover-light.jpg'
        if not (mp4.exists() and jpg.exists()):
            hip = Path(a.hiplab) / 'assets/drill_media/light' / f'hip-{i.lower()}.mp4'
            if hip.exists():
                run(['-i', str(hip), '-vf', 'scale=720:720:flags=lanczos', *ENC, str(mp4)])
                run(['-i', str(hip.with_suffix('.jpg')), '-vf', 'scale=540:540:flags=lanczos',
                     '-q:v', '4', str(jpg)])
            else:
                g = Path(a.green) / f'{i}.mp4'
                run(['-i', str(g), '-filter_complex', KEY, *ENC, str(mp4)])
                t = e['media'].get('coverSeconds', 0)
                run(['-ss', str(t), '-i', str(mp4), '-frames:v', '1',
                     '-vf', 'scale=540:540:flags=lanczos', '-q:v', '4', str(jpg)])
            print(i, mp4.stat().st_size // 1024, 'KB', flush=True)
        light = {'video': mp4.name, 'cover': jpg.name, 'stage': '#EFEFEF'}
        if e['media'].get('light') != light:
            e['media']['light'] = light
            f.write_text(json.dumps(e, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    total = sum(p.stat().st_size for p in PACKS.glob('*/demo-light.mp4'))
    print('light total', total // 1024 // 1024, 'MB')


if __name__ == '__main__':
    main()
