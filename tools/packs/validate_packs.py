#!/usr/bin/env python3
"""Check drill packs against docs/drill-pack-spec.md (format 1).

    python3 tools/packs/validate_packs.py                 # assets/packs of this repo
    python3 tools/packs/validate_packs.py --root path/to/packs --decode
    python3 tools/packs/validate_packs.py --on-demand-media --decode

Checks every pack folder and index.json: required fields and allowed values,
ids, versions, cue count (1–3), voice roles (side_switch exactly when the
move is unilateral), that every listed file exists with the recorded size and
sha256, that no stray file sits in a pack, that the common pack provides
what exercise packs rely on (counts 1–60, units, calls, chimes), and that
index.json matches the folders. --decode also decodes every clip and fails
when the recorded length differs from the real one by more than 50 ms.

Standard library only (+ ffmpeg for --decode). Exit status 1 on any error.

The default remains the complete, self-contained pack contract. The explicit
--on-demand-media mode validates this App's migrated layout: only missing legacy
demo/cover references are replaced by the verified Pose Hub bundle and the App's
fromPoseHub wiring. Pack metadata, sealing/index, voice/chimes and stray-file
checks remain enabled. New bundle integrity is checked against the build report;
the builder's --verify-only additionally checks the read-only source release.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import packlib as P  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
COMMON_NEEDS = ['p.go', 'p.rest', 'p.next', 'p.first', 'p.finish', 'p.switch_left', 'p.go_right',
                'p.per_side', 'u.sets', 'u.reps', 'u.sec', 'u.min'] + [f'n.{k}' for k in range(1, 61)]
CHIME_NEEDS = ['tick', 'start', 'end', 'finish', 'silence']


class Report:
    def __init__(self):
        self.errors = []

    def err(self, pack, msg):
        self.errors.append(f'{pack}: {msg}')


def check_common_fields(r, d, p):
    pid = d.name
    if p.get('format') != P.FORMAT:
        r.err(pid, f"format {p.get('format')!r} != {P.FORMAT!r}")
    if p.get('formatVersion') != P.FORMAT_VERSION:
        r.err(pid, f"formatVersion {p.get('formatVersion')!r} unsupported")
    if p.get('id') != pid:
        r.err(pid, f"id {p.get('id')!r} != folder name")
    if pid != P.COMMON_ID and not P.ID_RE.match(pid):
        r.err(pid, 'id must be letters/digits joined by "-"')
    if p.get('kind') not in P.KINDS:
        r.err(pid, f"kind {p.get('kind')!r}")
    if not P.SEMVER_RE.match(str(p.get('version', ''))):
        r.err(pid, f"version {p.get('version')!r} is not MAJOR.MINOR.PATCH")
    if not (p.get('name') or {}).get('zh'):
        r.err(pid, 'name.zh missing')


def check_exercise(r, d, p, all_ids):
    pid = d.name
    if p.get('category') not in P.CATEGORIES:
        r.err(pid, f"category {p.get('category')!r}")
    for e in p.get('equipment', []):
        if e not in P.EQUIPMENT:
            r.err(pid, f'equipment {e!r}')
    if p.get('position') not in P.POSITIONS:
        r.err(pid, f"position {p.get('position')!r}")
    if not isinstance(p.get('unilateral'), bool):
        r.err(pid, 'unilateral must be true/false')
    if p.get('level') not in (1, 2, 3):
        r.err(pid, f"level {p.get('level')!r} (1 入门, 2 基础, 3 进阶)")
    dose = p.get('defaultDose') or {}
    if dose.get('mode') == 'reps':
        if not isinstance(dose.get('reps'), int) or dose['reps'] < 1:
            r.err(pid, 'defaultDose.reps')
        if not (p.get('media') or {}).get('repSeconds'):
            r.err(pid, 'media.repSeconds needed for a reps dose')
    elif dose.get('mode') == 'time':
        if not isinstance(dose.get('seconds'), int) or dose['seconds'] < 1:
            r.err(pid, 'defaultDose.seconds')
    else:
        r.err(pid, f"defaultDose.mode {dose.get('mode')!r}")
    if not isinstance(dose.get('sets'), int) or dose['sets'] < 1:
        r.err(pid, 'defaultDose.sets')
    if not isinstance(dose.get('restSeconds'), int) or dose['restSeconds'] < 0:
        r.err(pid, 'defaultDose.restSeconds')
    cues = (p.get('cues') or {}).get('zh') or []
    if not 1 <= len(cues) <= 3:
        r.err(pid, f'{len(cues)} cues (want 1–3)')
    if not isinstance(p.get('primaryCue'), int) or not 0 <= p['primaryCue'] < max(len(cues), 1):
        r.err(pid, 'primaryCue out of range')
    alt = p.get('alternative')
    if alt is not None and alt not in all_ids:
        r.err(pid, f'alternative {alt!r} is not a pack here')
    m = p.get('media') or {}
    for k in ('cover', 'video'):
        if not m.get(k):
            r.err(pid, f'media.{k} missing')
    light = m.get('light')
    if light is not None:
        if not isinstance(light, dict):
            r.err(pid, 'media.light must be an object')
        else:
            for k in P.LIGHT_FILE_KEYS:
                if not light.get(k):
                    r.err(pid, f'media.light.{k} missing')
            if 'stage' in light and not P.HEX_COLOR_RE.match(str(light['stage'])):
                r.err(pid, f"media.light.stage {light['stage']!r} is not #RRGGBB")
    if not m.get('loopSeconds'):
        r.err(pid, 'media.loopSeconds missing')
    if p.get('unilateral') and m.get('showsSide') not in ('left', 'right'):
        r.err(pid, 'unilateral move needs media.showsSide')
    if not (p.get('credits') or {}).get('license'):
        r.err(pid, 'credits.license missing')
    roles = [l.get('role') for l in (p.get('voice') or {}).get('lines', [])]
    for role in P.REQUIRED_EXERCISE_ROLES:
        if role not in roles:
            r.err(pid, f'voice role {role!r} missing')
    if roles.count('cue') != len(cues):
        r.err(pid, f"{roles.count('cue')} cue lines for {len(cues)} cues")
    if p.get('unilateral') != ('side_switch' in roles):
        r.err(pid, 'side_switch line exactly when unilateral')
    if (p.get('voice') or {}).get('requires') != P.COMMON_ID:
        r.err(pid, f'voice.requires should be {P.COMMON_ID!r}')


def check_voice(r, d, p, decode):
    pid = d.name
    v = p.get('voice') or {}
    langs = v.get('languages') or []
    if 'zh' not in langs:
        r.err(pid, 'voice.languages must include zh')
    allowed = P.COMMON_ROLES if p.get('kind') == 'common' else P.EXERCISE_ROLES
    seen = set()
    for line in v.get('lines', []):
        lid = line.get('id', '')
        if not P.LINE_ID_RE.match(lid):
            r.err(pid, f'line id {lid!r}')
        if lid in seen:
            r.err(pid, f'duplicate line id {lid!r}')
        seen.add(lid)
        if line.get('role') not in allowed:
            r.err(pid, f"line {lid}: role {line.get('role')!r}")
        for lang in langs:
            text = (line.get('text') or {}).get(lang)
            if not text:
                r.err(pid, f'line {lid}: no {lang} text')
                continue
            ms = (line.get('ms') or {}).get(lang)
            if not isinstance(ms, int) or ms <= 0:
                r.err(pid, f'line {lid} [{lang}]: no decoded length')
                continue
            f = d / P.voice_file(lang, lid)
            if decode and f.is_file():
                real = P.decoded_ms(f)
                if abs(real - ms) > P.DURATION_TOLERANCE_MS:
                    r.err(pid, f'line {lid} [{lang}]: recorded {ms} ms, decodes to {real} ms')
    return seen


def on_demand_replacements(r, root, packs):
    """Fail closed unless the App's exact replacement layout is evidenced.

    This is deliberately App-specific, not a general missing-file exemption.
    Runtime mapping is also covered by on_demand_media_integration_test.dart.
    """
    app = root.parent.parent
    try:
        if root != app / 'assets' / 'packs':
            raise ValueError('requires the App assets/packs layout')
        media_root = app / 'assets' / 'training_media'
        manifests = list(media_root.glob('v*-app/app-manifest.json'))
        if len(manifests) != 1:
            raise ValueError('expected one bundled app-manifest.json')
        main_path = manifests[0]
        manifest = P.read_json(main_path)
        version = manifest['version']
        if not P.SEMVER_RE.fullmatch(version) or main_path.parent.name != f'v{version}-app':
            raise ValueError('media release version/path mismatch')
        actions = {a['id'] for a in manifest['actions']}
        if len(actions) != len(manifest['actions']) or any(not P.ID_RE.fullmatch(a) for a in actions):
            raise ValueError('invalid/duplicate media action ids')
        package_files = {}
        for pid in ('builtin', 'realistic-dark'):
            package = manifest['packages'][pid]
            reference = package['manifest']
            if reference['path'] != f'packages/{pid}.json':
                raise ValueError(f'{pid}: unexpected submanifest path')
            subpath = main_path.parent / reference['path']
            if subpath.stat().st_size != reference['bytes'] or P.sha256(subpath) != reference['sha256']:
                raise ValueError(f'{pid}: submanifest size/sha256 mismatch')
            files = P.read_json(subpath)['files']
            ids = package['actionIds']
            expected = {f'../v{version}/realistic/dark/{action}.mp4' for action in ids}
            if (package['kind'] != 'video' or not set(ids) <= actions
                    or len(set(ids)) != len(ids) or len(files) != package['fileCount']
                    or len(files) != len(expected) or {f['path'] for f in files} != expected
                    or any(type(f['bytes']) is not int or f['bytes'] <= 0
                           or not re.fullmatch(r'[0-9a-f]{64}', str(f['sha256'])) for f in files)
                    or sum(f['bytes'] for f in files) != package['totalBytes']):
                raise ValueError(f'{pid}: media action/file index mismatch')
            package_files[pid] = {f['path']: f for f in files}
        builtin = package_files['builtin']
        downloadable = package_files['realistic-dark']
        if any(downloadable[path] != builtin[path] for path in builtin.keys() & downloadable.keys()):
            raise ValueError('builtin/realistic-dark integrity metadata differs')
        full = builtin | downloadable
        expected_assets = {
            main_path.relative_to(media_root).as_posix(),
            *(f'v{version}-app/packages/{pid}.json' for pid in package_files),
            *(f'v{version}/realistic/dark/{Path(path).name}' for path in builtin),
            *(f'v{version}-app/common-lossy/{group}/{action}.webp'
              for group in ('covers', 'thumbs') for action in actions),
        }
        actual = {f.relative_to(media_root).as_posix(): f
                  for f in media_root.rglob('*') if f.is_file()}
        if set(actual) != expected_assets or any(f.is_symlink() for f in actual.values()):
            raise ValueError('bundled media inventory differs from the manifests')
        for path, entry in builtin.items():
            f = main_path.parent / path
            if f.stat().st_size != entry['bytes'] or P.sha256(f) != entry['sha256']:
                raise ValueError(f'{path}: builtin size/sha256 mismatch')
        report = P.read_json(app / 'tools/media/builtin-assets-report.json')
        inventory = ''.join(sorted(f'{rel}\0{f.stat().st_size}\0{P.sha256(f)}\n'
                                   for rel, f in actual.items()))
        if (report['releaseVersion'] != version or report['mainManifestSha256'] != P.sha256(main_path)
                or report['bundleInventorySha256'] != hashlib.sha256(inventory.encode()).hexdigest()):
            raise ValueError('media build report integrity mismatch; rebuild/verify the bundle')
        # Verify declared Flutter asset directories, including every lossy image.
        pubspec = (app / 'pubspec.yaml').read_text(encoding='utf-8')
        declared = set(re.findall(r'^    - ([^\s#]+)\s*$', pubspec, re.MULTILINE))
        if any(f'{f.parent.relative_to(app).as_posix()}/' not in declared for f in actual.values()):
            raise ValueError('replacement media directory missing from pubspec assets')
        # Narrow source witnesses: removing/changing the actual mapping must
        # fail this mode instead of silently overlooking absent legacy media.
        def dart(path):
            return re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(encoding='utf-8'), flags=re.DOTALL)
        services = dart(app / 'lib/app/services.dart')
        exercise = dart(app / 'lib/domain/exercise.dart')
        mapping = exercise.split('factory ExerciseMedia.fromPoseHub(', 1)[1].split('factory ExerciseMedia.fromPack(', 1)[0]
        if (not re.search(r"mediaOverride:\s*ExerciseMedia\.fromPoseHub\(\s*p,\s*version:\s*manifest\['version'\]\s+as\s+String,?\s*\)", services)
                or "'assets/training_media/v$version/realistic/dark/${p.id}.mp4'" not in mapping
                or "'assets/training_media/v$version-app/common-lossy/covers/${p.id}.webp'" not in mapping
                or not re.search(r'media:\s*mediaOverride\s*\?\?\s*ExerciseMedia\.fromPack\(p\)', exercise)):
            raise ValueError('App fromPoseHub replacement mapping is not wired')
        replacements = {}
        for pid, pack in packs.items():
            if pack.get('kind') != 'exercise':
                continue
            if f'../v{version}/realistic/dark/{pid}.mp4' not in full:
                raise ValueError(f'{pid}: missing replacement action/video')
            media = pack.get('media') or {}
            light = media.get('light') or {}
            legacy = {media.get('video'), media.get('cover'), light.get('video'), light.get('cover')} - {None}
            if not legacy <= {'demo.mp4', 'cover.jpg', 'demo-light.mp4', 'cover-light.jpg'}:
                raise ValueError(f'{pid}: unrecognized migrated media reference')
            replacements[pid] = legacy
        return replacements
    except (OSError, ValueError, TypeError, KeyError, IndexError) as error:
        r.err('on-demand-media', str(error))
        return {}


def check_files(r, d, p, migrated=()):
    pid = d.name
    listed = set(P.listed_files(p))
    files = p.get('files') or {}
    if set(files) != listed:
        missing, extra = listed - set(files), set(files) - listed
        r.err(pid, f'files map out of date (run build_packs.py): missing {sorted(missing)[:3]} '
                   f'extra {sorted(extra)[:3]}')
    for rel, meta in files.items():
        f = d / rel
        if not f.is_file():
            if rel not in migrated:
                r.err(pid, f'missing file {rel}')
            elif (type(meta.get('bytes')) is not int or meta['bytes'] <= 0
                  or not re.fullmatch(r'[0-9a-f]{64}', str(meta.get('sha256', '')))):
                r.err(pid, f'{rel}: invalid migrated sealing metadata')
        elif f.stat().st_size != meta.get('bytes') or P.sha256(f) != meta.get('sha256'):
            r.err(pid, f'{rel} changed since sealing (size/sha256)')
    for f in d.rglob('*'):
        if f.is_file() and f.name != 'pack.json':
            rel = f.relative_to(d).as_posix()
            if rel not in listed:
                r.err(pid, f'stray file {rel}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=str(P.packs_root(ROOT)))
    ap.add_argument('--decode', action='store_true', help='decode every clip and compare lengths')
    ap.add_argument('--on-demand-media', action='store_true',
                    help='validate this App migration with verified replacement assets; default requires complete packs')
    a = ap.parse_args()
    root = Path(a.root).resolve()
    r = Report()
    dirs = P.pack_dirs(root)
    packs = {d.name: P.read_json(d / 'pack.json') for d in dirs}
    migrated = on_demand_replacements(r, root, packs) if a.on_demand_media else {}
    all_ids = set(packs)
    if P.COMMON_ID not in packs:
        r.err(P.COMMON_ID, 'common pack missing')
    n_lines = 0
    for d in dirs:
        p = packs[d.name]
        check_common_fields(r, d, p)
        if p.get('kind') == 'exercise':
            check_exercise(r, d, p, all_ids)
        lines = check_voice(r, d, p, a.decode)
        n_lines += len(lines) * len((p.get('voice') or {}).get('languages') or [])
        if p.get('kind') == 'common':
            for need in COMMON_NEEDS:
                if need not in lines:
                    r.err(d.name, f'common line {need!r} missing')
            for c in CHIME_NEEDS:
                if c not in (p.get('chimes') or {}):
                    r.err(d.name, f'chime {c!r} missing')
        check_files(r, d, p, migrated.get(d.name, ()))
    idx_path = root / 'index.json'
    if not idx_path.is_file():
        r.err('index.json', 'missing (run build_packs.py)')
    else:
        idx = P.read_json(idx_path)
        if idx.get('format') != P.INDEX_FORMAT or idx.get('formatVersion') != P.FORMAT_VERSION:
            r.err('index.json', 'format/formatVersion')
        listed = {e['id']: e for e in idx.get('packs', [])}
        if set(listed) != all_ids:
            r.err('index.json', f'lists {sorted(set(listed) ^ all_ids)[:5]} differently from folders')
        for pid, e in listed.items():
            if pid in packs:
                if e.get('version') != packs[pid].get('version'):
                    r.err('index.json', f'{pid} version differs')
                if e.get('sha256') != P.sha256(root / pid / 'pack.json'):
                    r.err('index.json', f'{pid} pack.json changed since index was built')
    for e in r.errors:
        print('ERROR', e)
    n_ex = sum(1 for p in packs.values() if p.get('kind') == 'exercise')
    print(f'{n_ex} exercise packs + common, {n_lines} voice clips, {len(r.errors)} errors')
    sys.exit(1 if r.errors else 0)


if __name__ == '__main__':
    main()
