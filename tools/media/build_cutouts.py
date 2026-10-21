#!/usr/bin/env python3
"""Alpha figures for the plan card (assets/cutouts/<id>.webp + <id>-cover.webp).

Source: Pose-Hub Drive green-screen masters (1080², #00FF00, 8 s @ 30 fps), copied, never modified.
Key: fps=12, scale 600², chromakey 0x00FF00:0.28:0.06, despill green mix .35 (keeps the cyan
muscle highlight), crop to the union alpha box, 420 px wide; animated WebP q60 (yuva420p, loop),
still cover = frame 12 (1.0 s, the pack's coverSeconds) q82.
    python3 tools/media/build_cutouts.py --green ../drive/green
"""
import argparse, glob, subprocess, tempfile
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/cutouts'
CROPS = {'h-catcow-quad': (0, 155, 600, 495), 'w-dead-bug': (40, 200, 566, 474)}

def ff(*a): subprocess.run(['ffmpeg', '-v', 'error', '-y', *a], check=True)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--green', required=True); a = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for i, box in CROPS.items():
        with tempfile.TemporaryDirectory() as t:
            ff('-i', f'{a.green}/{i}.mp4', '-vf', 'fps=12,scale=600:600:flags=lanczos,chromakey=0x00FF00:0.28:0.06,'
               'despill=type=green:mix=0.35:expand=0,format=rgba', '-threads', '2', f'{t}/%03d.png')
            for f in sorted(glob.glob(f'{t}/*.png')):
                im = Image.open(f).crop(box)
                im.resize((420, round(420 * im.height / im.width)), Image.LANCZOS).save(f)
            ff('-framerate', '12', '-start_number', '1', '-i', f'{t}/%03d.png', '-c:v', 'libwebp_anim', '-q:v', '60',
               '-compression_level', '3', '-loop', '0', '-pix_fmt', 'yuva420p', '-threads', '2', str(OUT / f'{i}.webp'))
            ff('-i', f'{t}/013.png', '-c:v', 'libwebp', '-q:v', '82', '-pix_fmt', 'yuva420p', str(OUT / f'{i}-cover.webp'))
        print(i, (OUT / f'{i}.webp').stat().st_size // 1024, 'KB')

if __name__ == '__main__': main()
