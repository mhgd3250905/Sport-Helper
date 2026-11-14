#!/usr/bin/env python3
"""Add pack clips that the LC32 speech bundle does not have yet (2026-11-06).

compress_voice_lc32.py converted the original 695 Chinese clips once, with a
checksum ledger that refuses any change to its source inventory. New clips
(the English voice, the new 「最后一个」 line) are added here instead: each
pack clip assets/packs/<pack>/voice/<lang>/<line>.m4a that has no entry in
assets/voice_lc32/v1/manifest.json is decoded to 22050 Hz mono PCM and
encoded to the bundle's format (AAC-LC, mono, 22050 Hz, 32 kbit/s CBR, .m4a),
then appended to the manifest with its decoded length. Existing entries and
files are never touched.

Encoder: fdkaac (the original conversion's) when given with --fdkaac, else
ffmpeg's native AAC-LC encoder at the same settings with `-aac_coder fast`
(the sandbox has no fdkaac build; ffmpeg's default twoloop coder overshoots
true peak by up to +4 dB at 32 kbit/s, the fast coder keeps the source's
<= -2.5 dBFS ceiling).

    python3 tools/voice/add_lc32_clips.py [--fdkaac /path/to/fdkaac] [--budget 100]
"""
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/voice_lc32/v1'
FDK = ['-S', '-p', '2', '-b', '32000', '-m', '0', '-a', '1', '-G', '2', '--moov-before-mdat']


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def run(cmd):
    subprocess.run([str(c) for c in cmd], check=True, capture_output=True)


def true_peak(path):
    err = subprocess.run(['ffmpeg', '-nostats', '-hide_banner', '-nostdin', '-i', str(path),
                          '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    return float([l for l in err.splitlines() if l.strip().startswith('Peak:')][-1].split()[1])


def decoded_ms(path, tmp):
    wav = Path(tmp) / 'check.wav'
    if wav.exists():
        wav.unlink()
    run(['ffmpeg', '-v', 'error', '-nostdin', '-i', path, '-map', '0:a:0', '-c:a', 'pcm_s16le', wav])
    with wave.open(str(wav), 'rb') as w:
        assert w.getnchannels() == 1 and w.getframerate() == 22050, path
        return round(w.getnframes() / w.getframerate() * 1000)


def duration_ms(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
                          'stream=duration,codec_name,profile,channels,sample_rate', '-of', 'json',
                          str(path)], check=True, capture_output=True, text=True).stdout
    s = json.loads(out)['streams'][0]
    assert (s['codec_name'], s['profile'], int(s['channels']), int(s['sample_rate'])) == \
        ('aac', 'LC', 1, 22050), (path, s)
    return round(float(s['duration']) * 1000)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fdkaac')
    ap.add_argument('--budget', type=float, help='seconds before stopping (re-run to resume)')
    a = ap.parse_args()
    manifest_path = OUT / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    have = {(c['pack'], c['lang'], c['line']) for c in manifest['clips']}
    added = 0
    budget_end = time.time() + (a.budget or 1e9)

    def save():
        manifest['clips'].sort(key=lambda c: (c['pack'], c['lang'] != 'zh', c['lang'], c['line']))
        tmp_path = manifest_path.with_name('manifest.json.tmp')
        tmp_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n',
                            encoding='utf-8', newline='\n')
        os.replace(tmp_path, manifest_path)

    with tempfile.TemporaryDirectory() as tmp:
        for src in sorted(ROOT.glob('assets/packs/*/voice/*/*.m4a')):
            pack, lang, line = src.parts[-4], src.parts[-2], src.stem
            if (pack, lang, line) in have:
                continue
            if time.time() > budget_end:
                save()
                print(f'{added} clips added; budget used, run again to resume')
                raise SystemExit(3)
            dst = OUT / pack / lang / f'{line}.m4a'
            if dst.exists():
                raise SystemExit(f'unrecorded file already exists: {dst}')
            dst.parent.mkdir(parents=True, exist_ok=True)
            pcm = Path(tmp) / 'src.wav'
            if pcm.exists():
                pcm.unlink()
            run(['ffmpeg', '-v', 'error', '-nostdin', '-i', src, '-map', '0:a:0', '-vn',
                 '-c:a', 'pcm_s16le', '-ar', '22050', '-ac', '1', pcm])
            part = dst.with_suffix('.part.m4a')
            if a.fdkaac:
                run([a.fdkaac, *FDK, '-o', part, pcm])
            else:
                # Keep true peak <= -1.3 dBTP (Pose-Hub voice standard): if the
                # encode overshoots, trim the input 0.5 dB at a time.
                for trim in (0, -0.5, -1.0, -1.5):
                    run(['ffmpeg', '-v', 'error', '-nostdin', '-y', '-i', pcm, '-af', f'volume={trim}dB',
                         '-c:a', 'aac', '-aac_coder', 'fast',
                         '-profile:a', 'aac_low', '-b:a', '32000', '-ar', '22050', '-ac', '1',
                         '-movflags', '+faststart', '-f', 'mp4', part])
                    if true_peak(part) <= -1.3:
                        break
            os.replace(part, dst)
            manifest['clips'].append({
                'pack': pack, 'line': line, 'lang': lang,
                'asset': dst.relative_to(ROOT).as_posix(),
                'bytes': dst.stat().st_size, 'sha256': sha(dst),
                'decoded_ms': decoded_ms(dst, tmp), 'duration_ms': duration_ms(dst),
                'source': {'asset': src.relative_to(ROOT).as_posix(), 'sha256': sha(src)}})
            added += 1
    save()
    print(f'{added} clips added, {len(manifest["clips"])} in the bundle')


if __name__ == '__main__':
    main()
