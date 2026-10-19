"""Shared helpers for drill packs (docs/drill-pack-spec.md).

Pure standard library: the pack tools (build_packs.py, validate_packs.py) must
run in any repo that vendors a copy of tools/packs/, with only python3 and
ffprobe/ffmpeg on PATH (ffmpeg is needed only for the decoded-length check).
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

FORMAT = 'drill-pack'
INDEX_FORMAT = 'drill-pack-index'
FORMAT_VERSION = 1
COMMON_ID = '_common'

ID_RE = re.compile(r'^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$')
LINE_ID_RE = re.compile(r'^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*$')
SEMVER_RE = re.compile(r'^\d+\.\d+\.\d+$')

KINDS = ('exercise', 'common')
CATEGORIES = ('strength', 'core', 'cardio', 'mobility', 'stretch')
EQUIPMENT = ('mat', 'chair', 'wall', 'band', 'dumbbell', 'block', 'slider')
POSITIONS = ('standing', 'seated', 'supine', 'prone', 'quadruped', 'kneeling', 'side_lying')
# What a line is for. Exercise packs: name intro cue side_switch rest finish.
# The common pack: phrase count unit (numbers, units, fixed coaching words).
EXERCISE_ROLES = ('name', 'intro', 'cue', 'side_switch', 'rest', 'finish')
COMMON_ROLES = ('phrase', 'count', 'unit')
REQUIRED_EXERCISE_ROLES = ('name', 'intro', 'cue', 'rest', 'finish')

DURATION_TOLERANCE_MS = 50


def packs_root(repo: Path) -> Path:
    return repo / 'assets' / 'packs'


def pack_dirs(root: Path):
    """Every pack folder (a folder holding pack.json), common pack first."""
    dirs = sorted(p.parent for p in root.glob('*/pack.json'))
    return sorted(dirs, key=lambda d: (d.name != COMMON_ID, d.name))


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path: Path, data) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def voice_file(lang: str, line_id: str) -> str:
    """Path of a line's clip, relative to its pack folder."""
    return f'voice/{lang}/{line_id}.m4a'


def decoded_ms(path: Path, sr: int = 44100) -> int:
    """Length of what actually decodes (the number an app schedules with)."""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 's16le', '-ac', '1',
                          '-ar', str(sr), '-'], capture_output=True, check=True).stdout
    return int(round(len(raw) / 2 / sr * 1000))


def listed_files(pack: dict) -> list[str]:
    """Every file a pack.json says it carries (relative paths)."""
    out = []
    media = pack.get('media') or {}
    for k in ('cover', 'video'):
        if media.get(k):
            out.append(media[k])
    for c in (pack.get('chimes') or {}).values():
        out.append(c['file'])
    voice = pack.get('voice') or {}
    for line in voice.get('lines', []):
        for lang in voice.get('languages', []):
            if lang in (line.get('text') or {}):
                out.append(voice_file(lang, line['id']))
    return out
