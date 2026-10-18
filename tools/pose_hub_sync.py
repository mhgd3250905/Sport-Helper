#!/usr/bin/env python3
# copied from 3D-Pose-Hub media/tools/sync.py @ ee9d7ea71c599037c00d0f0e4a1b7e70a65538e8
"""Pose-Hub media sync for App repositories (single file, Python 3.9+ standard library only).

Reads the frozen manifest of ONE pinned media version and downloads only the requested drill ids into a
target folder, verifying size and sha256 of every file. Files that already match are left untouched.
Nothing is ever deleted. Copy this file into an App repo (e.g. tools/pose_hub_sync.py) or run it from a
Pose-Hub checkout.

Usage with a lock file (recommended, committed in the App repo):
    python tools/pose_hub_sync.py --lock pose-hub.lock.json
    python tools/pose_hub_sync.py --lock pose-hub.lock.json --check      # verify only, exit 1 on drift

Ad-hoc:
    python sync.py --version 0.1.0 --ids h-frog,s-9090 --variant dark --dest assets/videos --name "{id}.mp4"

Lock file:
    {
      "poseHub": {"repo": "mhgd3250905/3D-Pose-Hub", "version": "0.1.0"},
      "manifest": "tools/pose-hub-manifest.json",      # frozen local copy, relative to lock folder
      "targets": [
        {"variant": "dark", "role": "video", "width": 1080, "dest": "assets/hip/videos", "name": "{id}.mp4",
         "ids": ["h-frog", "s-9090"]}
      ]
    }
Relative `dest` paths resolve against the lock file's folder. `name` fields: {id} {id_lower} {tag} {variant}
{role} {width} {ext} {file}. Items with a tag (e.g. self-test stills a/b/c/front/back) are all fetched for
an id unless the target lists "tags"; their `name` must then contain {tag}. `--source-dir` reads from a local mirror of the bucket (a folder containing v<version>/...)
instead of HTTP, e.g. for offline builds or tests. `--from-dir` reads an extracted release ZIP whose
root contains each manifest item's `file` path directly (no v<version>/ prefix or manifest inside).
Use a separate --manifest or lock "manifest" (local paths are relative to the lock folder); a Pose-Hub
checkout can default to its media/manifest.json. Neither local mode requires baseUrl.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
from pathlib import Path, PureWindowsPath

SCHEMA = 'pose-hub/media-manifest@1'


def _sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def _open(location, source_dir=None):
    if source_dir:
        return open(Path(source_dir) / location, 'rb')
    if location.startswith(('http://', 'https://')):
        req = urllib.request.Request(location, headers={'User-Agent': 'pose-hub-sync/1'})
        return urllib.request.urlopen(req, timeout=120)
    return open(location, 'rb')


def load_manifest(version, manifest=None, base_url=None, source_dir=None, from_dir=None):
    if from_dir and not manifest:
        media_dir = Path(__file__).resolve().parent.parent
        default_manifest = media_dir / 'manifest.json'
        if media_dir.name != 'media' or not default_manifest.is_file():
            raise SystemExit('--from-dir needs a separate --manifest or lock "manifest" path/URL; '
                             'the extracted media archive does not contain a manifest')
        manifest = str(default_manifest)
    if manifest and not source_dir:
        loc = manifest
    elif source_dir:
        loc = manifest or f'v{version}/manifest.json'
    else:
        if not base_url:
            raise SystemExit('no manifest location: pass --manifest or --base-url / POSE_HUB_MEDIA_BASE_URL')
        loc = f'{base_url.rstrip("/")}/v{version}/manifest.json'
    with _open(loc, source_dir if source_dir and not os.path.isabs(str(loc)) else None) as r:
        data = json.loads(r.read().decode('utf-8'))
    if data.get('schema') != SCHEMA:
        raise SystemExit(f'{loc}: not a Pose-Hub media manifest')
    if 'release' in data:                      # frozen per-version snapshot (v<version>/manifest.json)
        if data.get('version') != version:
            raise SystemExit(f'{loc} is for version {data.get("version")}, expected {version}')
        rel = data['release']
    else:                                      # full media/manifest.json from the Pose-Hub repo
        rel = data.get('releases', {}).get(version)
        if rel is None:
            raise SystemExit(f'version {version} not found in {loc}')
    return rel


def _within(root, relative, label):
    """Archive item paths and generated names must stay inside their selected roots."""
    p = Path(relative)
    if not relative or '\\' in relative or p.root or PureWindowsPath(relative).drive or '..' in p.parts:
        raise SystemExit(f'{label}: unsafe path {relative!r}; expected a relative path inside the root')
    result = (root / p).resolve()
    try:
        result.relative_to(root.resolve())
    except ValueError:
        raise SystemExit(f'{label}: path escapes root: {relative!r}') from None
    return result


def pick(rel, item_id, variant, role, width, tags=None):
    c = [i for i in rel['items'] if i['id'] == item_id and i['variant'] == variant and i.get('role', 'video') == role]
    if width:
        c = [i for i in c if int(i.get('width') or 0) == int(width)]
    if tags:
        c = [i for i in c if i.get('tag') in tags]
    per_tag = {}
    for i in c:
        per_tag.setdefault(i.get('tag') or '', []).append(i)
    for tag, group in per_tag.items():
        if len(group) > 1:
            raise SystemExit(f'{item_id}{"/" + tag if tag else ""}: {len(group)} {variant}/{role} items '
                             f'(widths {", ".join(str(i.get("width")) for i in group)}); set "width"')
    return [g[0] for _, g in sorted(per_tag.items())]


def fetch(it, out, version, base_url, source_dir, from_dir=None):
    if from_dir:
        src = str(_within(Path(from_dir), it['file'], 'archive item'))
        if not Path(src).is_file():
            raise SystemExit(f'{it["id"]}: archive file not found: {src}; extract the ZIP so item.file paths '
                             'are directly under --from-dir (no v<version>/ prefix)')
    else:
        src = f'v{version}/{it["file"]}' if source_dir else f'{base_url.rstrip("/")}/v{version}/{it["file"]}'
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out.parent, prefix='.pose-hub-', suffix='.part')
    try:
        h = hashlib.sha256(); n = 0
        with os.fdopen(fd, 'wb') as w, _open(src, source_dir) as r:
            for b in iter(lambda: r.read(1 << 20), b''):
                w.write(b); h.update(b); n += len(b)
        if n != it['bytes'] or h.hexdigest() != it['sha256']:
            raise SystemExit(f'{it["id"]}: downloaded {n} bytes sha256 {h.hexdigest()} but manifest says '
                             f'{it["bytes"]} bytes {it["sha256"]}; nothing written')
        os.replace(tmp, out)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def run_target(rel, version, t, base_dir, base_url, source_dir, check, dry, log, from_dir=None):
    variant = t.get('variant', 'dark'); role = t.get('role', 'video'); width = t.get('width')
    dest = Path(t['dest']); dest = dest if dest.is_absolute() else base_dir / dest
    name = t.get('name', '{file}')
    stats = {'ok': 0, 'downloaded': 0, 'drift': 0}; missing = []; done = []
    for item_id in t['ids']:
        found = pick(rel, item_id, variant, role, width, t.get('tags'))
        if not found:
            missing.append(item_id); continue
        if any(i.get('tag') for i in found) and '{tag}' not in name:
            raise SystemExit(f'{item_id}: {variant}/{role} has tagged items; the target "name" needs {{tag}}')
        for it in found:
            if it.get('storage') not in ('archive', 'r2') or it.get('kind', 'file') != 'file':
                raise SystemExit(f'{item_id}: {variant}/{role} is a local-only master and is not published media')
            output_name = name.format(id=it['id'], id_lower=it['id'].lower(), tag=it.get('tag') or '', variant=variant,
                                      role=role, width=it.get('width'), ext=Path(it['file']).suffix, file=it['file'])
            if from_dir:
                _within(Path(from_dir), it['file'], 'archive item')
                out = _within(dest, output_name, 'target name')
            else:
                out = dest / output_name
            done.append({'id': it['id'], 'tag': it.get('tag'), 'file': it['file'], 'sha256': it['sha256'], 'path': str(out)})
            if out.is_file() and out.stat().st_size == it['bytes'] and _sha(out) == it['sha256']:
                stats['ok'] += 1; continue
            if check:
                stats['drift'] += 1; log(f'  DRIFT {out} (missing or sha256 differs from v{version}/{it["file"]})'); continue
            if dry:
                log(f'  would fetch v{version}/{it["file"]} -> {out}'); continue
            fetch(it, out, version, base_url, source_dir, from_dir); stats['downloaded'] += 1; log(f'  fetched {out}')
    if missing:
        raise SystemExit(f'version {version} has no {variant}/{role}{"/" + str(width) if width else ""} media for: '
                         + ', '.join(missing))
    return stats, done


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--lock', help='pose-hub.lock.json')
    ap.add_argument('--version'); ap.add_argument('--ids', help='comma-separated ids'); ap.add_argument('--ids-file')
    ap.add_argument('--variant', default='dark'); ap.add_argument('--role', default='video'); ap.add_argument('--width', type=int)
    ap.add_argument('--dest'); ap.add_argument('--name', default='{file}')
    ap.add_argument('--manifest'); ap.add_argument('--base-url')
    local = ap.add_mutually_exclusive_group()
    local.add_argument('--source-dir', help='legacy bucket mirror containing v<version>/...')
    local.add_argument('--from-dir', help='extracted media ZIP root containing item.file paths directly; no baseUrl needed')
    ap.add_argument('--allow-draft', action='store_true', help='accept an unpublished release (testing only)')
    ap.add_argument('--receipt', help='write a JSON receipt of what is in place')
    ap.add_argument('--check', action='store_true', help='verify only; exit 1 if anything is missing or differs')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args(argv)
    if a.lock:
        lock_path = Path(a.lock); lock = json.loads(lock_path.read_text(encoding='utf-8')); base_dir = lock_path.resolve().parent
        version = lock['poseHub']['version']; targets = lock['targets']
        base_url = a.base_url or lock.get('baseUrl') or os.environ.get('POSE_HUB_MEDIA_BASE_URL')
        manifest = a.manifest or lock.get('manifest')
    else:
        if not (a.version and a.dest and (a.ids or a.ids_file)):
            ap.error('without --lock, --version, --dest and --ids/--ids-file are required')
        ids = [x.strip() for x in (a.ids.split(',') if a.ids else Path(a.ids_file).read_text(encoding='utf-8').split())
               if x.strip() and not x.startswith('#')]
        version = a.version; base_dir = Path.cwd(); manifest = a.manifest
        base_url = a.base_url or os.environ.get('POSE_HUB_MEDIA_BASE_URL')
        targets = [{'variant': a.variant, 'role': a.role, 'width': a.width, 'dest': a.dest, 'name': a.name, 'ids': ids}]
    if a.from_dir:
        archive_root = Path(a.from_dir)
        if not archive_root.is_dir():
            ap.error(f'--from-dir is not an existing directory: {a.from_dir}; extract the ZIP first '
                     '(cloud-drive share links are not file download URLs)')
    if manifest and not a.source_dir and not str(manifest).startswith(('http://', 'https://')):
        manifest = str(base_dir / manifest)
    if not a.source_dir and not a.from_dir and not base_url and not a.check:
        ap.error('set baseUrl in the lock file, --base-url, or POSE_HUB_MEDIA_BASE_URL '
                 '(or use --from-dir / --source-dir for local media)')
    rel = load_manifest(version, manifest, base_url, a.source_dir, a.from_dir)
    if rel.get('status') != 'published' and not a.allow_draft:
        raise SystemExit(f'version {version} is not published (status {rel.get("status")}); apps only use published versions')
    total = {'ok': 0, 'downloaded': 0, 'drift': 0}; receipt = []
    for t in targets:
        s, done = run_target(rel, version, t, base_dir, base_url or '', a.source_dir, a.check, a.dry_run, print, a.from_dir)
        for k in total:
            total[k] += s[k]
        receipt += done
    print(f'pose-hub media v{version}: {total["ok"]} up to date, {total["downloaded"]} downloaded'
          + (f', {total["drift"]} drifted' if a.check else ''))
    if a.receipt and not a.check and not a.dry_run:
        Path(a.receipt).write_text(json.dumps({'version': version, 'items': receipt}, ensure_ascii=False, indent=2) + '\n',
                                   encoding='utf-8', newline='\n')
    return 1 if total['drift'] else 0


if __name__ == '__main__':
    sys.exit(main())
