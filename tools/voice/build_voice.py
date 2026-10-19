#!/usr/bin/env python3
"""Voice clips for the drill packs (docs/drill-pack-spec.md).

Every voice line lives in a pack: assets/packs/<id>/pack.json → voice.lines
(text per language + role). This tool renders each line with edge-tts and
writes assets/packs/<id>/voice/<lang>/<line>.m4a, then records the clip's
*decoded* length in the line (`ms`), which is what the App schedules with.

Post-processing is HipLab's v4.1 chain (HipLab tools/voice/build_voice.py,
docs/voice-audit-2026-10-18.md), ported unchanged:
  * cut silence only before the first and after the last sound (numpy, 10 ms
    windows above -50 dBFS; keep 40 ms lead / 80 ms tail, 5 ms / 20 ms fades
    inside the silence) — never inside a line;
  * one fixed gain per clip to -16 LUFS, measured on the clip looped to ≥ 3 s
    so single words get a real reading (no loudnorm dynamic mode, no
    dynaudnorm);
  * 12 kHz low-pass + alimiter (-2.5 dBFS, 5 ms look-ahead, latency=1 so the
    tail is not lost, level=0 = no auto gain);
  * mono AAC 64 kbit/s with -cutoff 12000; re-measure the encoded clip and
    correct gain/limit (≤ 6 tries, best kept) toward -16±0.3 LU, ≤ -1.2 dBTP;
  * raw edge-tts output cached in tools/voice/.raw-cache/ (re-processing
    needs no network), processed clips in tools/voice/.voice-cache/ keyed by
    the processing version; identical text is rendered once.

    PYTHONPATH=/path/to/edge_tts:/path/to/numpy python3 tools/voice/build_voice.py build
    python3 tools/voice/build_voice.py build --budget 100   # stop after ~100 s, re-run to resume
    python3 tools/voice/audit_voice.py --raw                # gate: 0 failures

Then seal the packs: python3 tools/packs/build_packs.py --pubspec pubspec.yaml

RISK: edge-tts uses Microsoft Edge's read-aloud endpoint; its terms for
commercial use are unclear. Before a store release regenerate the same lines
with the official Azure Speech API (same voices).
"""
import argparse
import asyncio
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/packs'))
import packlib as P  # noqa: E402

PACKS = P.packs_root(ROOT)
CACHE = ROOT / 'tools/voice/.voice-cache'
RAW_CACHE = ROOT / 'tools/voice/.raw-cache'
RATE = {'zh': '+4%', 'en': '+4%'}

SR = 44100
SILENCE_DB = -50.0   # 10 ms window below this = silence (only at the edges)
LEAD_S = 0.04        # silence kept before the first sound
TAIL_S = 0.08        # silence kept after the last sound
FADE_IN_S = 0.005
FADE_OUT_S = 0.02
TARGET_LUFS = -16.0
LIMIT_DB = -2.5
PROCESS_VERSION = 'v4.1'  # = HipLab v4.1


def _no_proxy_env():
    return {k: v for k, v in os.environ.items()
            if k.lower() not in ('http_proxy', 'https_proxy', 'all_proxy')}


# ── synthesis ───────────────────────────────────────────────────────────

async def _tts(text, voice, rate, mp3):
    import edge_tts
    for attempt in range(4):
        try:
            await edge_tts.Communicate(text, voice, rate=rate).save(str(mp3))
            if mp3.stat().st_size > 500:
                return
        except Exception as e:  # network hiccups
            if attempt == 3:
                raise RuntimeError(f'edge-tts failed for {text!r}: {e}')
        await asyncio.sleep(1.5 * (attempt + 1))


def raw_path(text, voice, rate):
    """Unprocessed edge-tts render (shared with audit_voice.py)."""
    h = hashlib.sha1(f'{voice}|{rate}|{text}'.encode()).hexdigest()[:16]
    return RAW_CACHE / f'{h}.mp3'


def cache_key(text, voice, rate):
    return hashlib.sha1(f'{voice}|{rate}|{text}|{PROCESS_VERSION}'.encode()).hexdigest()[:16]


# ── post-processing (HipLab v4.1) ───────────────────────────────────────

def _decode(path):
    import numpy as np
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1',
                          '-ar', str(SR), '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def decoded_ms(path):
    return int(round(len(_decode(path)) / SR * 1000))


def edge_trim(x):
    """Cut the silence before the first and after the last sound only."""
    import numpy as np
    n = SR // 100
    k = len(x) // n
    w = x[:k * n].reshape(k, n)
    lvl = 20 * np.log10(np.maximum(np.sqrt(np.mean(w ** 2, axis=1)), 1e-9))
    loud = np.where(lvl > SILENCE_DB)[0]
    if len(loud) == 0:
        raise RuntimeError('clip has no audio')
    a = max(0, loud[0] * n - int(LEAD_S * SR))
    b = (loud[-1] + 1) * n + int(TAIL_S * SR)
    y = x[a:b]
    if b > len(x):  # source tail shorter than TAIL_S: pad with silence
        y = np.concatenate([y, np.zeros(b - len(x), dtype=np.float32)])
    fi, fo = int(FADE_IN_S * SR), int(FADE_OUT_S * SR)
    y[:fi] *= np.linspace(0, 1, fi, dtype=np.float32)
    y[-fo:] *= np.linspace(1, 0, fo, dtype=np.float32)
    return y


def loop_lufs(wav, seconds):
    """(integrated LUFS, true peak dBTP) of the clip repeated to ≥ 3 s."""
    loops = max(0, int(3 / max(seconds, .05)))
    err = subprocess.run(['ffmpeg', '-v', 'info', '-nostats', '-threads', '1',
                          '-stream_loop', str(loops), '-i', str(wav),
                          '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    summ = err[err.rfind('Summary:'):]
    i = re.search(r'I:\s+(-?[\d.]+) LUFS', summ)
    p = re.search(r'Peak:\s+(-?[\d.]+|-inf) dBFS', summ)
    return float(i.group(1)), float(p.group(1)) if p and p.group(1) != '-inf' else -99.0


def process(src, dst):
    """Edge-trim, one fixed gain to −16 LUFS, peak-limit, encode mono AAC."""
    y = edge_trim(_decode(src))
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / 'a.wav'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '1',
                        '-i', '-', '-c:a', 'pcm_f32le', str(wav)], input=y.tobytes(), check=True)
        gain = TARGET_LUFS - loop_lufs(wav, len(y) / SR)[0]
        limit_db = LIMIT_DB
        best = None
        for k in range(6):
            limit = 10 ** (limit_db / 20)
            af = (f'volume={gain:.2f}dB,lowpass=f=12000:p=2,'
                  f'alimiter=limit={limit:.4f}:attack=5:release=50:level=0:latency=1')
            out = Path(td) / f'try{k}.m4a'
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-threads', '1', '-i', str(wav),
                            '-af', af, '-ar', str(SR), '-ac', '1', '-c:a', 'aac', '-b:a', '64k',
                            '-cutoff', '12000', '-movflags', '+faststart', str(out)], check=True)
            lufs, tp = loop_lufs(out, len(y) / SR)
            score = abs(lufs - TARGET_LUFS) + 10 * max(0.0, tp + 1.2)
            if best is None or score < best[0]:
                best = (score, out)
            if abs(lufs - TARGET_LUFS) <= .3 and tp <= -1.2:
                break
            if tp > -1.2:
                limit_db -= tp + 1.6
            gain += TARGET_LUFS - lufs
        shutil.copyfile(best[1], dst)


# ── packs ────────────────────────────────────────────────────────────────

def jobs_from_packs():
    """[(pack_dir, line, lang, text, voice)] for every line of every pack."""
    out = []
    for d in P.pack_dirs(PACKS):
        pack = P.read_json(d / 'pack.json')
        v = pack.get('voice') or {}
        for line in v.get('lines', []):
            for lang in v.get('languages', []):
                text = (line.get('text') or {}).get(lang)
                if text:
                    out.append((d, line['id'], lang, text, v['voices'][lang]))
    return out


async def render(unique, budget_end):
    """Fetch raw renders (network, 4 at a time); process one clip at a time
    (2-core sandbox: never run encoders in parallel)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    RAW_CACHE.mkdir(parents=True, exist_ok=True)
    sem = asyncio.Semaphore(4)

    async def fetch(text, voice, rate):
        raw = raw_path(text, voice, rate)
        if raw.exists() and raw.stat().st_size > 500:
            return
        async with sem:
            part = raw.with_suffix('.part.mp3')
            await _tts(text, voice, rate, part)
            os.replace(part, raw)

    await asyncio.gather(*(fetch(*u) for u in unique.values()))
    done = 0
    for key, (text, voice, rate) in unique.items():
        cached = CACHE / f'{key}.m4a'
        if cached.exists():
            continue
        if time.time() > budget_end:
            return False
        tmp = cached.with_suffix('.tmp.m4a')
        process(raw_path(text, voice, rate), tmp)
        os.replace(tmp, cached)  # an interrupted build never caches half a clip
        done += 1
        if done % 25 == 0:
            print(f'  processed {done}', flush=True)
    return True


def cmd_build(a):
    jobs = jobs_from_packs()
    unique = {}
    for d, lid, lang, text, voice in jobs:
        unique[cache_key(text, voice, RATE[lang])] = (text, voice, RATE[lang])
    print(f'{len(jobs)} clips in {len({j[0] for j in jobs})} packs, {len(unique)} unique renders',
          flush=True)
    os.environ.clear()
    os.environ.update(_no_proxy_env())
    finished = asyncio.run(render(unique, time.time() + (a.budget or 1e9)))
    left = sum(1 for k in unique if not (CACHE / f'{k}.m4a').exists())
    if not finished or left:
        print(f'budget used: {left} renders left — run again to resume', flush=True)
        sys.exit(3)
    # place clips, record decoded lengths, drop stale clips
    by_pack = {}
    for d, lid, lang, text, voice in jobs:
        by_pack.setdefault(d, []).append((lid, lang, text, voice))
    total = 0
    for d, items in by_pack.items():
        pack = P.read_json(d / 'pack.json')
        lines = {l['id']: l for l in pack['voice']['lines']}
        keep = set()
        for lid, lang, text, voice in items:
            rel = P.voice_file(lang, lid)
            dst = d / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            src = CACHE / f'{cache_key(text, voice, RATE[lang])}.m4a'
            if not dst.exists() or P.sha256(dst) != P.sha256(src):
                shutil.copyfile(src, dst)
            lines[lid].setdefault('ms', {})[lang] = decoded_ms(dst)
            keep.add(rel)
            total += dst.stat().st_size
        for f in (d / 'voice').rglob('*.m4a'):
            if f.relative_to(d).as_posix() not in keep:
                f.unlink()
        pack['voice']['postProcess'] = (f'HipLab {PROCESS_VERSION}: edge trim, -16 LUFS fixed gain, '
                                        'alimiter -2.5 dBFS, AAC 64k mono 44.1 kHz cutoff 12 kHz')
        P.write_json(d / 'pack.json', pack)
    print(f'{len(jobs)} clips placed, {total / 1024 / 1024:.1f} MB', flush=True)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--budget', type=float, help='seconds of processing before stopping (resume later)')
    a = p.parse_args()
    {'build': cmd_build}[a.cmd](a)


if __name__ == '__main__':
    main()
