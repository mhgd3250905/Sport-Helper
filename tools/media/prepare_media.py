#!/usr/bin/env python3
"""Builds the bundled clips assets/drill_media/sf-<id>.mp4 + .jpg (720², H.264, no audio).

Sources (copied, never modified):
  * Pose-Hub v0.2.0 dark soft-v1 clips as bundled in HipLab (assets/drill_media/hip-<id>.mp4/.jpg)
  * Pose-Hub Drive archive green-screen masters (1080², #00FF00) → keyed onto the same #101013 background.
Run once per media update; one ffmpeg at a time, -threads 2.
    python3 tools/media/prepare_media.py --hiplab ../../refs/HipLab --green ../drive/green
"""
import argparse, json, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/drill_media'
ENC = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '27', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', '-threads', '2']

def run(a): subprocess.run(['ffmpeg', '-v', 'error', '-y'] + a, check=True)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--hiplab'); ap.add_argument('--green'); a = ap.parse_args()
    lib = json.loads((ROOT/'assets/library/exercises.json').read_text())['exercises']
    for e in lib:
        i = e['id']; low = i.lower(); mp4 = OUT/f'sf-{low}.mp4'; jpg = OUT/f'sf-{low}.jpg'
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
            t = e['media']['posterSeconds']
            run(['-ss', str(t), '-i', str(mp4), '-frames:v', '1', '-vf', 'scale=540:540:flags=lanczos', '-q:v', '4', str(jpg)])
        print(i, mp4.stat().st_size // 1024, 'KB', flush=True)
    print('total', sum(p.stat().st_size for p in OUT.glob('sf-*')) // 1024 // 1024, 'MB')

if __name__ == '__main__': main()
