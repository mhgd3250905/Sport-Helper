#!/usr/bin/env python3
"""Per-clip audit of the drill-pack voice clips (assets/packs/*/voice/<lang>/).

Copied from HipLab@fce7ad8 tools/voice/audit_voice.py (mhgd3250905/HipLab,
docs/voice-audit-2026-10-18.md). Checks and thresholds are unchanged; only
the I/O changed: clips and their recorded lengths come from each pack.json
(`--legacy` audits the old flat assets/voice layout for before/after), the
audit runs on 2 threads by default (small sandbox), and the per-window
loudness curve is left out of the JSON to keep reports small.

    python3 tools/voice/audit_voice.py                       # check shipped clips
    python3 tools/voice/audit_voice.py --raw                 # + compare with the edge-tts source
    python3 tools/voice/audit_voice.py --json out.json --md out.md

For every clip it decodes the audio (ffmpeg → float PCM) and checks:

* decode: container duration ≈ stream duration ≈ decoded samples, and the
  manifest length the app schedules with ≈ the real length;
* length vs text: seconds per spoken unit (zh: syllables, en: syllables)
  against the median of the whole set – a clip far below it was cut short;
* truncation vs source (--raw): speech span of the shipped clip against the
  speech span of a fresh edge-tts render of the same text and voice;
* edges: lead/tail silence, and whether the clip *ends* (or starts) while
  the voice is still loud – an abrupt cut mid-syllable;
* gaps: silences inside the speech (a pause long enough to sound like the
  line ended) – reported, failed only when longer than the source has;
* loudness curve: 200 ms RMS windows over the speech; the second half or the
  last word dropping far below the first half (or rising/falling inside a
  phrase) fails, and integrated LUFS / true peak per clip must sit in a
  narrow band across the set.

Exit status 1 when any clip fails, so the build can gate on it.
"""
import argparse
import asyncio
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PACKS = ROOT / 'assets/packs'
RAW_CACHE = ROOT / 'tools/voice/.raw-cache'
SR = 44100

# thresholds (dBFS unless noted)
SILENCE_DB = -50.0        # below this a 10 ms window counts as silence
GAP_MIN_S = 0.45          # an inner pause this long is reported
GAP_FAIL_EXTRA_S = 0.25   # …and fails when longer than the source pause by this
EDGE_LOUD_DB = 18.0       # last/first 10 ms within this many dB of the speech level = abrupt
TAIL_MIN_MS = 40          # at least this much quiet after the last sound
TAIL_MAX_MS = 200
LEAD_MAX_MS = 120
DROP_DB = 9.0             # second-half speech median this far below the first half
LUFS_TARGET = -16.0
LUFS_TOL = 1.0            # loudness band (every clip, measured looped to ≥ 3 s)
TP_MAX = -1.0             # true-peak ceiling (dBTP)
RATE_MIN = 0.62           # seconds-per-syllable below this fraction of median = too short
SPAN_SHORT_MS = 90        # shipped speech span shorter than the source by more than this


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1',
                          '-ar', str(SR), '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def probe(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                          'format=duration:stream=duration,codec_name,channels,sample_rate',
                          '-of', 'json', str(path)], capture_output=True, text=True).stdout
    j = json.loads(out)
    s = j['streams'][0]
    return {
        'fmt_s': float(j['format']['duration']),
        'stream_s': float(s.get('duration') or 'nan'),
        'codec': s['codec_name'], 'channels': int(s['channels']), 'sr': int(s['sample_rate']),
    }


def loudness(path, loops=0):
    """(integrated LUFS, true peak dBTP). [loops] repeats the clip so the
    400 ms gating blocks also cover single words."""
    err = subprocess.run(['ffmpeg', '-v', 'info', '-nostats', '-stream_loop', str(loops),
                          '-i', str(path), '-af',
                          'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    summ = err[err.rfind('Summary:'):]
    i = re.search(r'I:\s+(-?[\d.]+|-inf) LUFS', summ)
    tp = re.search(r'Peak:\s+(-?[\d.]+|-inf) dBFS', summ)
    f = lambda m: float(m.group(1)) if m and m.group(1) != '-inf' else float('-inf')
    return f(i), f(tp)


def db(x):
    return 20 * math.log10(max(float(x), 1e-9))


def win_db(x, ms):
    n = int(SR * ms / 1000)
    k = len(x) // n
    if k == 0:
        return np.array([db(np.sqrt(np.mean(x ** 2))) if len(x) else -180.0])
    w = x[:k * n].reshape(k, n)
    return 20 * np.log10(np.maximum(np.sqrt(np.mean(w ** 2, axis=1)), 1e-9))


def speech_span(x):
    """(first, last) 10 ms window index above SILENCE_DB, in seconds."""
    d = win_db(x, 10)
    idx = np.where(d > SILENCE_DB)[0]
    if len(idx) == 0:
        return None
    return idx[0] * .01, (idx[-1] + 1) * .01, d


def gaps(d):
    """Inner silent runs (10 ms windows) between first and last sound, seconds."""
    idx = np.where(d > SILENCE_DB)[0]
    if len(idx) == 0:
        return []
    out, run = [], 0
    for v in d[idx[0]:idx[-1] + 1]:
        if v <= SILENCE_DB:
            run += 1
        else:
            if run * .01 >= GAP_MIN_S:
                out.append(round(run * .01, 2))
            run = 0
    return out


ZH_DIGITS = {'0': 1, '1': 1, '2': 1, '3': 1, '4': 1, '5': 1, '6': 1, '7': 1, '8': 1, '9': 1}


def units(text, lang):
    """Rough spoken syllables."""
    if lang == 'zh':
        n = len(re.findall(r'[\u4e00-\u9fff]', text))
        for num in re.findall(r'\d+', text):
            v = int(num)
            n += 1 if v <= 10 else (2 if v < 20 or v % 10 == 0 and v < 100 else 3)
        return max(n, 1)
    n = 0
    for w in re.findall(r"[A-Za-z']+|\d+", text):
        if w.isdigit():
            v = int(w)
            n += 1 if v <= 12 else 2 if v < 20 else 2 if v % 10 == 0 else 3
            continue
        g = re.findall(r'[aeiouy]+', w.lower())
        s = len(g) - (1 if w.lower().endswith('e') and len(g) > 1 and not w.lower().endswith('le') else 0)
        n += max(s, 1)
    return max(n, 1)


async def _raw_tts(jobs, conc=6):
    import edge_tts
    sem = asyncio.Semaphore(conc)
    RAW_CACHE.mkdir(parents=True, exist_ok=True)

    async def one(text, voice, rate, dst):
        if dst.exists() and dst.stat().st_size > 500:
            return
        async with sem:
            for attempt in range(4):
                try:
                    await edge_tts.Communicate(text, voice, rate=rate).save(str(dst))
                    if dst.stat().st_size > 500:
                        return
                except Exception:
                    if attempt == 3:
                        raise
                await asyncio.sleep(1.5 * (attempt + 1))
    await asyncio.gather(*(one(*j) for j in jobs))


def raw_path(text, voice, rate):
    h = hashlib.sha1(f'{voice}|{rate}|{text}'.encode()).hexdigest()[:16]
    return RAW_CACHE / f'{h}.mp3'


def audit_clip(path, text, lang, manifest_ms, raw=None):
    p = probe(path)
    x = decode(path)
    dec_s = len(x) / SR
    r = {'key': path.stem, 'lang': lang, 'text': text, 'fails': [], 'notes': []}
    r.update({'fmt_ms': round(p['fmt_s'] * 1000), 'stream_ms': round(p['stream_s'] * 1000),
              'decoded_ms': round(dec_s * 1000), 'manifest_ms': manifest_ms})
    if p['channels'] != 1 or p['sr'] != SR or p['codec'] != 'aac':
        r['fails'].append(f"format {p['codec']}/{p['channels']}ch/{p['sr']}")
    if abs(p['fmt_s'] - dec_s) > .05 or abs(p['stream_s'] - dec_s) > .05:
        r['fails'].append('container/stream/decoded length mismatch')
    if manifest_ms is not None and abs(manifest_ms - dec_s * 1000) > 50:
        r['fails'].append(f'manifest {manifest_ms} ms vs decoded {round(dec_s * 1000)} ms')

    span = speech_span(x)
    if span is None:
        r['fails'].append('no audio above silence')
        return r
    a, b, d10 = span
    r['lead_ms'] = round(a * 1000)
    r['tail_ms'] = round(dec_s * 1000 - b * 1000)
    r['speech_ms'] = round((b - a) * 1000)
    seg = x[int(a * SR):int(b * SR)]
    sp_rms = db(np.sqrt(np.mean(seg ** 2)))
    r['speech_rms_db'] = round(sp_rms, 2)
    r['peak_db'] = round(db(np.max(np.abs(x))), 2)
    # abrupt edges: compare the outermost 10 ms of the file with the speech level
    last10 = db(np.sqrt(np.mean(x[-441:] ** 2))) if len(x) > 441 else -180
    first10 = db(np.sqrt(np.mean(x[:441] ** 2))) if len(x) > 441 else -180
    r['end_10ms_db'] = round(last10, 1)
    if last10 > sp_rms - EDGE_LOUD_DB:
        r['fails'].append(f'abrupt end (last 10 ms {last10:.1f} dB vs speech {sp_rms:.1f})')
    if first10 > sp_rms - EDGE_LOUD_DB:
        r['fails'].append(f'abrupt start (first 10 ms {first10:.1f} dB)')
    if r['tail_ms'] < TAIL_MIN_MS:
        r['fails'].append(f"tail {r['tail_ms']} ms < {TAIL_MIN_MS}")
    if r['tail_ms'] > TAIL_MAX_MS:
        r['fails'].append(f"tail {r['tail_ms']} ms > {TAIL_MAX_MS}")
    if r['lead_ms'] > LEAD_MAX_MS:
        r['fails'].append(f"lead {r['lead_ms']} ms > {LEAD_MAX_MS}")
    r['gaps_s'] = gaps(d10)

    # loudness curve over speech, 200 ms windows, voiced windows only
    d200 = win_db(seg, 200)
    voiced = d200[d200 > sp_rms - 20]
    r['curve_db'] = [round(float(v), 1) for v in d200]
    if len(voiced) >= 4:
        h = len(voiced) // 2
        first, second = float(np.median(voiced[:h])), float(np.median(voiced[h:]))
        r['half_drop_db'] = round(first - second, 1)
        r['_drop'] = first - second
        spread = float(np.percentile(voiced, 90) - np.percentile(voiced, 10))
        r['spread_db'] = round(spread, 1)

    lufs, tp = loudness(path, loops=max(0, math.ceil(3 / max(dec_s, .05)) - 1))
    r['lufs'] = None if math.isinf(lufs) else round(lufs, 1)
    r['true_peak'] = None if math.isinf(tp) else round(tp, 1)
    if r['true_peak'] is not None and tp > TP_MAX:
        r['fails'].append(f'true peak {tp:.1f} dBTP > {TP_MAX}')
    if r['lufs'] is None or abs(lufs - LUFS_TARGET) > LUFS_TOL:
        r['fails'].append(f'LUFS {lufs:.1f} outside {LUFS_TARGET}±{LUFS_TOL}')

    r['units'] = units(text, lang)
    r['s_per_unit'] = round((b - a) / r['units'], 3)

    if raw is not None and raw.exists():
        y = decode(raw)
        rs = speech_span(y)
        if rs:
            ra, rb, rd = rs
            r['raw_speech_ms'] = round((rb - ra) * 1000)
            r['raw_gaps_s'] = gaps(rd)
            if r['speech_ms'] < r['raw_speech_ms'] - SPAN_SHORT_MS:
                r['fails'].append(f"truncated: speech {r['speech_ms']} ms vs source "
                                  f"{r['raw_speech_ms']} ms")
            # a level drop the source already has (a soft final "s") is speech,
            # not processing; fail only what processing added.
            rseg = y[int(ra * SR):int(rb * SR)]
            rd200 = win_db(rseg, 200)
            rv = rd200[rd200 > db(np.sqrt(np.mean(rseg ** 2))) - 20]
            if len(rv) >= 4 and '_drop' in r:
                h = len(rv) // 2
                r['raw_half_drop_db'] = round(float(np.median(rv[:h]) - np.median(rv[h:])), 1)
                if r['_drop'] > r['raw_half_drop_db'] + 3:
                    r['fails'].append(f"second half {r['_drop']:.1f} dB quieter "
                                      f"(source {r['raw_half_drop_db']})")
            rg = max(r['raw_gaps_s'] or [0])
            for g in r['gaps_s']:
                if g > rg + GAP_FAIL_EXTRA_S:
                    r['fails'].append(f'inner silence {g} s (source max {rg} s)')
    elif r.get('_drop', 0) > DROP_DB:
        r['fails'].append(f"second half {r['_drop']:.1f} dB quieter")
    r.pop('_drop', None)
    return r


def pack_work(root, langs, use_raw):
    """(path, text, lang, recorded ms, raw render) for every line of every pack."""
    sys.path.insert(0, str(ROOT / 'tools/packs'))
    import packlib as P
    import build_voice as B
    rows, work, jobs = [], [], []
    for d in P.pack_dirs(root):
        pack = P.read_json(d / 'pack.json')
        v = pack.get('voice') or {}
        for line in v.get('lines', []):
            for lang in v.get('languages', []):
                if lang not in langs:
                    continue
                text = (line.get('text') or {}).get(lang)
                if not text:
                    continue
                key = f"{d.name}/{line['id']}"
                path = d / P.voice_file(lang, line['id'])
                voice, rate = v['voices'][lang], B.RATE[lang]
                raw = raw_path(text, voice, rate) if use_raw else None
                if use_raw:
                    jobs.append((text, voice, rate, raw))
                if not path.exists():
                    rows.append({'key': key, 'lang': lang, 'text': text, 'fails': ['missing file']})
                    continue
                work.append((path, text, lang, (line.get('ms') or {}).get(lang), raw, key))
    return rows, work, jobs


def legacy_work(base, texts, langs, use_raw, voice, rate):
    """The pre-pack flat layout (assets/voice/<lang>/<key>.m4a + manifest.json),
    kept so the before/after comparison runs the same checks."""
    m = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
    t = json.loads(Path(texts).read_text(encoding='utf-8'))
    rows, work, jobs = [], [], []
    for lang in langs:
        for key, ms in sorted(m['clips'].get(lang, {}).items()):
            text = t[key]
            raw = raw_path(text, voice, rate) if use_raw else None
            if use_raw:
                jobs.append((text, voice, rate, raw))
            work.append((base / lang / f'{key}.m4a', text, lang, ms, raw, key))
    return rows, work, jobs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=str(PACKS), help='packs folder')
    ap.add_argument('--raw', action='store_true', help='compare with the edge-tts source render')
    ap.add_argument('--json')
    ap.add_argument('--md')
    ap.add_argument('--label', default='')
    ap.add_argument('--lang', choices=['zh', 'en'], action='append',
                    help='audit one language (repeatable); default every language present')
    ap.add_argument('--shard', default='1/1', help='I/N: audit every N-th clip (slow machines)')
    ap.add_argument('--merge', nargs='+', metavar='JSON',
                    help='only merge --json outputs into one report')
    ap.add_argument('--legacy', metavar='DIR', help='audit an old flat assets/voice folder')
    ap.add_argument('--texts', help='--legacy: JSON {key: text}')
    ap.add_argument('--voice', default='zh-CN-XiaoxiaoNeural', help='--legacy: voice of the clips')
    ap.add_argument('--rate', default='+4%', help='--legacy: edge-tts rate of the clips')
    ap.add_argument('--threads', type=int, default=2)
    a = ap.parse_args()
    langs = tuple(a.lang or ('zh', 'en'))
    if a.merge:
        rows = [r for f in a.merge for r in json.loads(Path(f).read_text(encoding='utf-8'))['clips']]
        sys.exit(report(rows, a))
    if a.legacy:
        rows, work, jobs = legacy_work(Path(a.legacy), a.texts, langs, a.raw, a.voice, a.rate)
    else:
        rows, work, jobs = pack_work(Path(a.root), langs, a.raw)
    if a.raw and any(not j[3].exists() for j in jobs):
        env = {k: v for k, v in os.environ.items()
               if k.lower() not in ('http_proxy', 'https_proxy', 'all_proxy')}
        os.environ.clear()
        os.environ.update(env)
        asyncio.run(_raw_tts(jobs))
    si, sn = (int(v) for v in a.shard.split('/'))
    work = work[si - 1::sn]
    from concurrent.futures import ThreadPoolExecutor

    def one(w):
        r = audit_clip(*w[:5])
        r['key'] = w[5]
        r.pop('curve_db', None)
        return r
    with ThreadPoolExecutor(max(1, a.threads)) as ex:
        rows += list(ex.map(one, work))
    sys.exit(report(rows, a))


def report(rows, a):
    langs = sorted({r['lang'] for r in rows}, reverse=True)
    # set-wide check: speaking rate against the median of the language
    for lang in langs:
        rs = [r for r in rows if r['lang'] == lang and 's_per_unit' in r]
        if len(rs) < 20:
            continue
        med = float(np.median([r['s_per_unit'] for r in rs if r['units'] >= 3]))
        for r in rs:
            r['fails'] = [f for f in r['fails'] if not f.startswith('too short')]
            if r['s_per_unit'] < RATE_MIN * med:
                r['fails'].append(f"too short for its text ({r['s_per_unit']} s/syll vs median "
                                  f'{med:.3f})')
    bad = [r for r in rows if r['fails']]
    summary = {'label': a.label, 'clips': len(rows), 'failing': len(bad),
               'by_lang': {lang: sum(1 for r in bad if r['lang'] == lang) for lang in langs}}
    for lang in langs:
        rs = [r for r in rows if r['lang'] == lang and r.get('lufs') is not None]
        tp = [r['true_peak'] for r in rows if r['lang'] == lang and r.get('true_peak') is not None]
        summary[lang] = {
            'lufs_min': min(r['lufs'] for r in rs), 'lufs_max': max(r['lufs'] for r in rs),
            'true_peak_max': max(tp),
        }
    cats = {}
    for r in bad:
        for f in r['fails']:
            c = re.sub(r'[\d.\-]+', '#', f.split('(')[0]).strip()
            cats[c] = cats.get(c, 0) + 1
    summary['fail_kinds'] = dict(sorted(cats.items(), key=lambda kv: -kv[1]))
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    if a.json:
        Path(a.json).write_text(json.dumps({'summary': summary, 'clips': rows},
                                           ensure_ascii=False, indent=1), encoding='utf-8')
    if a.md:
        L = [f"## {a.label or 'audit'}", '', f"{len(rows)} clips, **{len(bad)} failing**", '']
        L += ['| lang | key | text | ms | speech | src | tail | LUFS | TP | problems |',
              '|---|---|---|---|---|---|---|---|---|---|']
        for r in sorted(bad, key=lambda r: (r['lang'], r['key'])):
            L.append(f"| {r['lang']} | `{r['key']}` | {r['text'][:28]} | {r.get('decoded_ms', '')} | "
                     f"{r.get('speech_ms', '')} | {r.get('raw_speech_ms', '')} | {r.get('tail_ms', '')} | "
                     f"{r.get('lufs', '')} | {r.get('true_peak', '')} | {'; '.join(r['fails'])} |")
        Path(a.md).write_text('\n'.join(L) + '\n', encoding='utf-8')
    return 1 if bad else 0


if __name__ == '__main__':
    main()
