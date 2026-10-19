#!/usr/bin/env python3
"""Builds each drill pack's clip and cover: assets/packs/<id>/demo.mp4 + cover.jpg (720² H.264, no
audio; cover 540²). Re-seal afterwards: python3 tools/packs/build_packs.py --pubspec pubspec.yaml

Sources (copied, never modified):
  * Pose-Hub v0.2.0 dark soft-v1 clips as bundled in HipLab (assets/drill_media/hip-<id>.mp4/.jpg)
  * Pose-Hub Drive archive green-screen masters (1080², #00FF00) → keyed onto the same #101013 background.
Run once per media update; one ffmpeg at a time, -threads 2.
    python3 tools/media/prepare_media.py --hiplab ../../refs/HipLab --green ../drive/green
"""
import argparse, json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / 'assets/packs'
ENC = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '27', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', '-threads', '2']

def run(a): subprocess.run(['ffmpeg', '-v', 'error', '-y'] + a, check=True)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--hiplab'); ap.add_argument('--green'); a = ap.parse_args()
    for f in sorted(PACKS.glob('*/pack.json')):
        e = json.loads(f.read_text(encoding='utf-8'))
        if e['kind'] != 'exercise': continue
        i = e['id']; low = i.lower(); mp4 = f.parent/e['media']['video']; jpg = f.parent/e['media']['cover']
        if mp4.exists() and jpg.exists(): continue
        hip = Path(a.hiplab)/'assets/drill_media'/f'hip-{low}.mp4'
        if hip.exists():
            run(['-i', str(hip), '-vf', 'scale=720:720:flags=lanczos', *ENC, str(mp4)])
            run(['-i', str(hip.with_suffix('.jpg')), '-vf', 'scale=540:540:flags=lanczos', '-q:v', '4', str(jpg)])
        else:
            g = Path(a.green)/f'{i}.mp4'
            key = ('[0:v]chromakey=0x00FF00:0.30:0.08,despill=type=green:mix=0.6,scale=720:720:flags=lanczos[fg];'
                   'color=c=0x101013:s=720x720:r=30[bg];[bg][fg]overlay=shortest=1,format=yuv420p')
            run(['-i', str(g), '-filter_complex', key, *ENC, str(mp4)])
            t = e['media']['coverSeconds']
            run(['-ss', str(t), '-i', str(mp4), '-frames:v', '1', '-vf', 'scale=540:540:flags=lanczos', '-q:v', '4', str(jpg)])
        print(i, mp4.stat().st_size // 1024, 'KB', flush=True)
    print('total', sum(p.stat().st_size for p in PACKS.glob('*/demo.mp4')) // 1024 // 1024, 'MB')

if __name__ == '__main__': main()
