#!/usr/bin/env python3
"""Import immutable, unreviewed App-test assets without changing stable media.

Only assets/app_test_pack/<pack-id>/ is written. The generated App index uses
smartfit-app-test-pack-index@1; that is an App format, NOT a proposed HUB schema.
Supported observed HUB schemas: pose-hub-stacked-alpha-delivery@1 and
pose-hub-app-test-catalog@1 (2026-10-25). Planning documents are not deliverables.
The normalized dataclasses below are the adapter boundary.

Consumer contract: internal flavor AND explicit user/build opt-in are required;
prefer the indexed packed-alpha assets, otherwise retain the App's existing
theme-matched stable-media resolver. catalogIds is the full source catalog, not
the old 93-action list; actions contains only media verified/imported so far.
The source catalog is copied verbatim for App library/AI adapters to consume.
alphaPlaybackPoster is App-derived frame zero, never the pose-selected cover:
decode packed H264 to RGB, take upper RGB and lower RGB red channel as alpha.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field, replace
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import subprocess
import tempfile
import time
from typing import Callable

APP_ROOT = Path(__file__).resolve().parents[2]
INDEX_FORMAT = 'smartfit-app-test-pack-index@1'
ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}\Z')
SHA = re.compile(r'[0-9a-f]{64}\Z')


class ImportError(ValueError):
    """Untrusted source or an incompatible existing App import."""


@dataclass(frozen=True)
class FileSpec:
    path: str
    bytes: int
    sha256: str


@dataclass(frozen=True)
class ReadyAction:
    id: str
    packed_video: FileSpec
    alpha_cover: FileSpec
    alpha_thumbnail: FileSpec
    expected_video: dict = field(default_factory=dict)
    qa_report: FileSpec | None = None


@dataclass(frozen=True)
class TestPack:
    """Private normalized boundary; these names are not assumed HUB JSON keys."""
    id: str
    manifest: bytes
    catalog: bytes
    catalog_ids: tuple[str, ...]
    actions: tuple[ReadyAction, ...]
    status: str = 'test-unreviewed'
    reviewed: bool = False
    release_eligible: bool = False
    encoding: dict | None = None
    rejected_actions: dict[str, str] = field(default_factory=dict)


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def _json(data: bytes, label: str) -> dict:
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ImportError(f'Duplicate JSON key in {label}: {key}')
            result[key] = value
        return result
    try:
        value = json.loads(data.decode('utf-8-sig'), object_pairs_hook=unique_pairs)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ImportError(f'Invalid UTF-8 JSON: {label}') from error
    if not isinstance(value, dict):
        raise ImportError(f'JSON object required: {label}')
    return value


def require_test_status(document: dict, label: str) -> None:
    if (document.get('status') != 'test-unreviewed'
            or document.get('reviewed') is not False
            or document.get('releaseEligible') is not False):
        raise ImportError(f'{label} must explicitly be test-unreviewed / reviewed:false / releaseEligible:false')


def relative_file(root: Path, relative: str) -> Path:
    """Reject absolute, drive/UNC, traversal, ADS, symlinks and junction escapes."""
    if (not isinstance(relative, str) or not relative or '\\' in relative
            or ':' in relative or '\x00' in relative
            or PurePosixPath(relative).is_absolute()
            or PureWindowsPath(relative).drive
            or any(p in ('', '.', '..') for p in relative.split('/'))):
        raise ImportError(f'Unsafe relative asset path: {relative!r}')
    root = root.resolve()
    path = root.joinpath(*relative.split('/'))
    current = root
    for part in relative.split('/'):
        current = current / part
        if current.is_symlink():
            raise ImportError(f'Symlink is not a source asset: {relative}')
    if not path.resolve().is_relative_to(root):
        raise ImportError(f'Asset path escapes source: {relative}')
    if not path.is_file():
        raise ImportError(f'Missing source file: {relative}')
    return path


def checked_file(root: Path, spec: FileSpec) -> Path:
    if type(spec.bytes) is not int or spec.bytes <= 0 or not isinstance(spec.sha256, str) or not SHA.fullmatch(spec.sha256):
        raise ImportError(f'Positive bytes and lowercase SHA256 required: {spec.path}')
    path = relative_file(root, spec.path)
    if path.stat().st_size != spec.bytes or digest(path) != spec.sha256:
        raise ImportError(f'Size/SHA256 mismatch: {spec.path}')
    return path


def probe_packed_video(path: Path) -> dict:
    tool = shutil.which('ffprobe')
    if not tool:
        raise ImportError('ffprobe is required to validate the actual packed video')
    try:
        result = subprocess.run([tool, '-v', 'error', '-show_streams', '-of', 'json', str(path)],
                                check=True, capture_output=True, timeout=30)
        streams = json.loads(result.stdout)['streams']
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        raise ImportError(f'Cannot inspect packed video: {path.name}') from error
    videos = [s for s in streams if s.get('codec_type') == 'video']
    if len(videos) != 1:
        raise ImportError(f'Exactly one packed video track required: {path.name}')
    video = videos[0]
    if (video.get('codec_name') != 'h264' or video.get('width') != 720
            or video.get('height') != 1440 or video.get('pix_fmt') != 'yuv420p'):
        raise ImportError(f'Packed video must be H264 720x1440 yuv420p: {path.name}')
    frame_count = video.get('nb_frames')
    if frame_count not in (None, 'N/A'):
        try:
            if int(frame_count) <= 0:
                raise ImportError(f'Packed video has no frames: {path.name}')
        except (TypeError, ValueError) as error:
            if isinstance(error, ImportError):
                raise
            raise ImportError(f'Invalid packed-video frame count: {path.name}') from error
    metadata = {'codec': 'h264', 'width': 720, 'height': 1440, 'pixelFormat': 'yuv420p',
                'colorSpace': video.get('color_space'), 'colorRange': video.get('color_range')}
    try:
        metadata['fps'] = float(Fraction(video['avg_frame_rate']))
        metadata['durationSeconds'] = float(video['duration'])
        if frame_count not in (None, 'N/A'):
            metadata['frames'] = int(frame_count)
    except (KeyError, ValueError, TypeError, ZeroDivisionError) as error:
        raise ImportError(f'Missing video timing metadata: {path.name}') from error
    return metadata


def probe_alpha_webp(path: Path, size: int) -> dict:
    try:
        from PIL import Image
        with Image.open(path) as image:
            if image.format != 'WEBP' or image.mode != 'RGBA' or image.size != (size, size):
                raise ImportError(f'Alpha asset must be RGBA WebP {size}x{size}: {path.name}')
            if getattr(image, 'n_frames', 1) != 1:
                raise ImportError(f'Cover/thumbnail must be a static alpha WebP: {path.name}')
            lo, hi = image.getchannel('A').getextrema()
            if lo == 255 or hi == 0:
                raise ImportError(f'Alpha must contain transparent and visible pixels: {path.name}')
    except (OSError, ValueError) as error:
        if isinstance(error, ImportError):
            raise
        raise ImportError(f'Cannot decode alpha WebP: {path.name}') from error
    return {'format': 'webp', 'width': size, 'height': size, 'alpha': True}


def decode_alpha_frame_zero(path: Path):
    """Decode display frame zero to RGB before reading mask.r, like the shader.

    Reading raw Y would incorrectly retain the video's 16..235 limited range.
    FFmpeg's RGB output applies the codec's range/color conversion first. The
    packed protocol then uses RGB(upper half) + R(lower half), not Y or luma.
    """
    from PIL import Image
    tool = shutil.which('ffmpeg')
    if not tool:
        raise ImportError('ffmpeg is required to derive the actual alpha frame zero')
    try:
        result = subprocess.run([tool, '-v', 'error', '-nostdin', '-threads', '1',
            '-i', str(path), '-map', '0:v:0', '-frames:v', '1', '-threads', '1',
            '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1'],
            check=True, capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        raise ImportError(f'Cannot decode packed frame zero: {path.name}') from error
    if len(result.stdout) != 720 * 1440 * 3:
        raise ImportError(f'Packed frame zero is not RGB 720x1440: {path.name}')
    with Image.frombytes('RGB', (720, 1440), result.stdout) as packed:
        rgba = packed.crop((0, 0, 720, 720)).convert('RGBA')
        with packed.crop((0, 720, 720, 1440)) as mask:
            rgba.putalpha(mask.getchannel('R'))
    return rgba


def _ids(values, label: str) -> set[str]:
    if any(not isinstance(v, str) or not ID.fullmatch(v) for v in values):
        raise ImportError(f'Invalid action/pack ID in {label}')
    if len(values) != len(set(values)):
        raise ImportError(f'Duplicate action ID in {label}')
    return set(values)


def validate_pack(source: Path, pack: TestPack, *, video_probe: Callable = probe_packed_video) -> list[tuple[Path, str, dict]]:
    require_test_status({'status': pack.status, 'reviewed': pack.reviewed,
                         'releaseEligible': pack.release_eligible}, 'Normalized source')
    _ids([pack.id], 'pack')
    catalog_ids = _ids(pack.catalog_ids, 'catalog')
    action_ids = _ids([action.id for action in pack.actions], 'ready batch')
    if not catalog_ids or not action_ids <= catalog_ids:
        raise ImportError('Ready actions must belong to a nonempty full catalog')
    _json(pack.manifest, 'source manifest')
    _json(pack.catalog, 'source catalog')
    files = []
    for action in pack.actions:
        if action.qa_report is not None:
            qa_file = checked_file(source, action.qa_report)
            qa = _json(qa_file.read_bytes(), f'QA report {action.id}')
            if qa.get('passed') is not True:
                raise ImportError(f'Delivered QA did not pass: {action.id}')
        for role, spec, size in [('packedVideo', action.packed_video, None),
                                 ('alphaCover', action.alpha_cover, 720),
                                 ('alphaThumbnail', action.alpha_thumbnail, 240)]:
            path = checked_file(source, spec)
            if path.suffix.lower() != ('.mp4' if size is None else '.webp'):
                raise ImportError(f'Unexpected file extension for {role}: {spec.path}')
            media = video_probe(path) if size is None else probe_alpha_webp(path, size)
            if size is None:
                for key, expected in action.expected_video.items():
                    actual = media.get(key)
                    if isinstance(expected, (int, float)) and type(expected) is not bool:
                        if not isinstance(actual, (int, float)) or abs(actual-expected)>0.001:
                            raise ImportError(f'Actual packed-video {key} differs from delivery: {action.id}')
                    elif actual != expected:
                        raise ImportError(f'Actual packed-video {key} differs from delivery: {action.id}')
            descriptor = {'bytes': spec.bytes, 'sha256': spec.sha256, **media}
            files.append((path, f'{action.id}/{role}', descriptor))
    return files


def _write_immutable(path: Path, data: bytes, root: Path) -> None:
    if not path.resolve().is_relative_to(root.resolve()):
        raise ImportError(f'Output escapes dedicated App-test directory: {path}')
    current = path
    while current != root:
        if current.is_symlink():
            raise ImportError(f'Symlink is not an import destination: {path}')
        current = current.parent
    if path.exists():
        if path.is_symlink() or path.read_bytes() != data:
            raise ImportError(f'Existing immutable import differs: {path}')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation never replaces an existing asset or historical record.
    with path.open('xb') as stream:
        stream.write(data)


def import_pack(source: Path, app: Path, pack: TestPack, *, internal_opt_in: bool = False,
                apply: bool = False, video_probe: Callable = probe_packed_video,
                frame_decoder: Callable = decode_alpha_frame_zero,
                skip_unverified_ready: bool = False) -> dict:
    if not internal_opt_in:
        raise ImportError('Explicit --allow-unreviewed-internal is required; production import is disabled')
    _ids([a.id for a in pack.actions], 'incoming batch')
    files = []
    accepted = []
    rejected = dict(pack.rejected_actions)
    # The CLI imports verified records while the producer keeps adding batches.
    # The strict Python API remains useful for explicit integrity assertions.
    validate_pack(source, replace(pack, actions=()), video_probe=video_probe)
    semantics = read_semantic_sources(source, pack)
    # App-owned temporary staging, never inside the producer's source tree.
    # Keep generated images alive until immutable App objects are copied.
    with tempfile.TemporaryDirectory(prefix='smartfit-alpha-frame-zero-') as staging:
        for action in pack.actions:
            try:
                incoming = validate_pack(source, replace(pack, actions=(action,)), video_probe=video_probe)
                video = checked_file(source, action.packed_video)
                generated = Path(staging) / f'{action.id}.webp'
                with frame_decoder(video) as image:
                    if image.mode != 'RGBA' or image.size != (720, 720):
                        raise ImportError('Frame-zero decoder must return actual RGBA 720x720')
                    image.save(generated, format='WEBP', lossless=True, exact=True, method=6)
                metadata = probe_alpha_webp(generated, 720)
                descriptor = {'bytes': generated.stat().st_size, 'sha256': digest(generated),
                    **metadata, 'sourceSha256': action.packed_video.sha256,
                    'sourceFrame': 0, 'sourceTimeSeconds': 0}
                # The producer may replace a file between hash verification,
                # ffprobe and decode. Commit no descriptor from mixed contents.
                for original, _, original_descriptor in incoming:
                    if original.stat().st_size != original_descriptor['bytes'] or digest(original) != original_descriptor['sha256']:
                        raise ImportError(f'Source changed during validation: {original}')
                files.extend(incoming)
                files.append((generated, f'{action.id}/alphaPlaybackPoster', descriptor))
                accepted.append(action.id)
            except ImportError as error:
                if not skip_unverified_ready:
                    raise
                rejected[action.id] = str(error)
        validation = {'format': 'smartfit-app-test-pack-validation@1', 'id': pack.id,
            'status': 'test-unreviewed', 'reviewed': False, 'releaseEligible': False,
            'manifestSha256': hashlib.sha256(pack.manifest).hexdigest(),
            'catalogSha256': hashlib.sha256(pack.catalog).hexdigest(),
            'sourceRecordCount': len(pack.actions) + len(pack.rejected_actions),
            'validatedRecordIds': sorted(accepted), 'rejectedRecords': dict(sorted(rejected.items())),
            'catalogActionCount': len(pack.catalog_ids),
            'checks': ['source bytes/SHA256', 'actual H264 geometry/pixel format/timing',
                       'RGBA alpha WebP covers/thumbnails', 'delivered QA report hash/pass',
                       'actual RGB-decoded frame zero with lower red alpha'],
            'sourceQueueMayContinue': True, 'originalSourcesModified': False}
        index = _import_validated_files(app, pack, files, apply=apply, validation=validation,
                                        semantics=semantics)
        if apply:
            write_alpha_bounds(app, index)
        return index


def read_semantic_sources(source: Path, pack: TestPack) -> dict[str, bytes]:
    """Bundle the declared training definitions; never guess another directory."""
    manifest = _json(pack.manifest, 'manifest')
    catalog = _json(pack.catalog, 'catalog')
    declared = [value for value in (manifest.get('semanticCatalog'), catalog.get('semanticCatalog'))
                if value is not None]
    if not declared:
        return {}
    if any(value != declared[0] for value in declared):
        raise ImportError('Manifest/catalog semantic descriptors differ')
    descriptor = declared[0]
    if not isinstance(descriptor, dict):
        raise ImportError('Invalid semantic catalog descriptor')
    spec = _descriptor(descriptor)
    data = checked_file(source, spec).read_bytes()
    if len(data) != spec.bytes or hashlib.sha256(data).hexdigest() != spec.sha256:
        raise ImportError('Semantic source changed during validation')
    decoded = _json(data, 'semantic catalog')
    if (decoded.get('format') != 'pose-hub-catalog' or decoded.get('formatVersion') != 1
            or decoded.get('version') != descriptor.get('version')
            or not isinstance(decoded.get('drills'), list)):
        raise ImportError('Semantic catalog format/version mismatch')
    return {spec.path: data}


def write_alpha_bounds(app: Path, index: dict) -> dict:
    """Analyze immutable cover/thumb alpha; do not reframe video posters."""
    from PIL import Image
    assets = {}
    for action in index['actions'].values():
        for role in ('alphaCover', 'alphaThumbnail'):
            descriptor = action[role]
            path = relative_file(app, descriptor['asset'])
            if digest(path) != descriptor['sha256']:
                raise ImportError('Alpha bounds source hash mismatch')
            with Image.open(path) as image:
                bounds = image.convert('RGBA').getchannel('A').getbbox()
                if bounds is None:
                    continue
                assets[descriptor['asset']] = {
                    'sourceSha256': descriptor['sha256'],
                    'width': image.width, 'height': image.height,
                    'bounds': list(bounds),
                }
    result = {'format': 'smartfit-alpha-bounds@1', 'assets': dict(sorted(assets.items()))}
    destination = app / 'assets' / 'app_test_pack' / index['id'] / 'alpha-bounds.json'
    # Derived metadata only; existing media and video frame-zero bytes stay intact.
    data = (json.dumps(result, indent=2) + '\n').encode('utf8')
    temporary = destination.with_suffix('.json.tmp')
    try:
        temporary.write_bytes(data)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return result


def _import_validated_files(app: Path, pack: TestPack,
                            files: list[tuple[Path, str, dict]], *, apply: bool, validation: dict,
                            semantics: dict[str, bytes] | None = None) -> dict:
    base = (app.resolve() / 'assets' / 'app_test_pack').resolve()
    if not base.is_relative_to(app.resolve()):
        raise ImportError('App-test output escapes the workspace')
    target = base / pack.id
    if target.is_symlink() or not target.resolve().is_relative_to(base):
        raise ImportError('App-test output escapes its dedicated directory')
    index_path = target / 'index.json'
    previous = _json(index_path.read_bytes(), 'existing App index') if index_path.exists() else None
    if previous is not None:
        if (previous.get('format') != INDEX_FORMAT or previous.get('id') != pack.id
                or previous.get('internalOnly') is not True):
            raise ImportError('Existing index is not this internal App-test import')
        require_test_status(previous, 'Existing index')
        if not set(previous['catalogIds']) <= set(pack.catalog_ids):
            raise ImportError('New catalog would remove previously imported catalog IDs')
        for action in previous['actions'].values():
            for item in action.values():
                path = relative_file(app, item['asset'])
                if path.stat().st_size != item['bytes'] or digest(path) != item['sha256']:
                    raise ImportError('Existing imported asset is missing/corrupt; refusing to replace it')
    actions = dict(previous['actions']) if previous else {}
    for path, label, descriptor in files:
        action_id, role = label.split('/')
        relative = f'assets/app_test_pack/{pack.id}/objects/{descriptor["sha256"]}{path.suffix.lower()}'
        item = {'asset': relative, **descriptor}
        if action_id in actions and role in actions[action_id] and actions[action_id][role] != item:
            raise ImportError(f'Existing action media changed; use a new pack revision: {action_id}/{role}')
        actions.setdefault(action_id, {})[role] = item
    manifest_hash = hashlib.sha256(pack.manifest).hexdigest()
    catalog_hash = hashlib.sha256(pack.catalog).hexdigest()
    prefix = f'assets/app_test_pack/{pack.id}'
    manifests = sorted(set((previous or {}).get('sourceManifestAssets', [])) |
                       {f'{prefix}/sources/{manifest_hash}.manifest.json'})
    index = {'format': INDEX_FORMAT, 'id': pack.id, 'status': 'test-unreviewed',
             'reviewed': False, 'releaseEligible': False, 'internalOnly': True,
             'fallbackPolicy': 'prefer-packed-alpha; otherwise existing App stable-media resolver',
             'catalogIds': sorted(pack.catalog_ids), 'catalogAsset': f'{prefix}/sources/{catalog_hash}.catalog.json',
             'sourceManifestAssets': manifests, 'actions': dict(sorted(actions.items()))}
    validation = {**validation, 'importedReadyIds': sorted(actions),
                  'importedReadyCount': len(actions),
                  'pendingIds': sorted(set(pack.catalog_ids)-set(actions))}
    validation_bytes = (json.dumps(validation, ensure_ascii=False, indent=2)+'\n').encode('utf8')
    validation_hash = hashlib.sha256(validation_bytes).hexdigest()
    index['validatedMetadataAsset'] = f'{prefix}/validation/{validation_hash}.json'
    index['pendingIds'] = validation['pendingIds']
    index['sourceEncoding'] = pack.encoding
    if semantics:
        index['semanticSources'] = {
            relative: f'{prefix}/sources/{hashlib.sha256(data).hexdigest()}.semantic.json'
            for relative, data in semantics.items()}
    if not apply:
        return index
    # Copy only after validation of the whole incoming batch and existing index.
    for path, _, descriptor in files:
        data = path.read_bytes()
        if len(data) != descriptor['bytes'] or hashlib.sha256(data).hexdigest() != descriptor['sha256']:
            raise ImportError(f'Source changed during validation: {path}')
        _write_immutable(target / 'objects' / (descriptor['sha256'] + path.suffix.lower()), data, target)
    _write_immutable(target / 'sources' / f'{manifest_hash}.manifest.json', pack.manifest, target)
    _write_immutable(target / 'sources' / f'{catalog_hash}.catalog.json', pack.catalog, target)
    for data in (semantics or {}).values():
        _write_immutable(target / 'sources' / f'{hashlib.sha256(data).hexdigest()}.semantic.json', data, target)
    _write_immutable(target / 'validation' / f'{validation_hash}.json', validation_bytes, target)
    data = (json.dumps(index, ensure_ascii=False, indent=2) + '\n').encode('utf8')
    if index_path.exists():
        old = index_path.read_bytes()
        if old == data:
            return index
        _write_immutable(target / 'history' / f'index-{hashlib.sha256(old).hexdigest()}.json', old, target)
    target.mkdir(parents=True, exist_ok=True)
    # Only this dedicated App-test current index is replaceable; old versions
    # and all objects are retained. Stable training_media/packs/pubspec are untouched.
    handle, name = tempfile.mkstemp(prefix='.index-', suffix='.json', dir=target)
    temporary = Path(name)
    try:
        with os.fdopen(handle, 'wb') as stream:
            stream.write(data)
        os.replace(temporary, index_path)
    finally:
        temporary.unlink(missing_ok=True)
    return index


def load_source(source: Path) -> TestPack:
    if not (source / 'manifest.json').is_file():
        raise ImportError('HUB manifest.json is not delivered yet; planning documents cannot be imported')
    manifest_path = relative_file(source, 'manifest.json')
    # Capture a stable pair while HUB appends records. sourceCatalogSha256 differs
    # from delivered catalog.json in the observed contract, so do not guess that
    # field's semantics or treat it as the delivered catalog byte hash.
    last_error = None
    for _ in range(5):
        try:
            manifest_bytes = manifest_path.read_bytes()
            document = _json(manifest_bytes, 'HUB manifest')
            require_test_status(document, 'HUB manifest')
            if document.get('format') != 'pose-hub-stacked-alpha-delivery@1':
                raise ImportError(f'Unsupported HUB deliverable schema {document.get("format")!r}; no field aliases are guessed')
            catalog_path = relative_file(source, 'catalog.json')
            catalog_bytes = catalog_path.read_bytes()
            pack = parse_delivery(manifest_bytes, catalog_bytes)
            if manifest_bytes == manifest_path.read_bytes() and catalog_bytes == catalog_path.read_bytes():
                return pack
            last_error = ImportError('HUB changed manifest/catalog during snapshot capture')
        except ImportError as error:
            last_error = error
        time.sleep(0.05)
    raise ImportError(f'No consistent supported HUB delivery snapshot: {last_error}')


def parse_delivery(manifest_bytes: bytes, catalog_bytes: bytes) -> TestPack:
    """Observed 2026-10-25 HUB delivery@1 + app-test-catalog@1 only."""
    manifest = _json(manifest_bytes, 'HUB manifest')
    catalog = _json(catalog_bytes, 'HUB catalog')
    require_test_status(manifest, 'HUB manifest')
    require_test_status(catalog, 'HUB catalog')
    if manifest.get('format') != 'pose-hub-stacked-alpha-delivery@1' or catalog.get('format') != 'pose-hub-app-test-catalog@1':
        raise ImportError('Unsupported HUB deliverable/catalog schema')
    if manifest.get('id') != catalog.get('id'):
        raise ImportError('HUB manifest and catalog pack IDs differ')
    encoding = manifest.get('encoding', {})
    required_encoding = {'layout': 'top-rgb-bottom-alpha', 'width': 720, 'height': 1440,
                         'rgbAlphaMode': 'straight', 'alphaChannelAfterRgbDecode': 'red',
                         'matrix': 'bt709', 'range': 'limited'}
    if manifest.get('skin') != 'realistic' or any(encoding.get(k) != v for k,v in required_encoding.items()):
        raise ImportError('Unsupported stacked-alpha encoding contract')
    rows, catalog_rows = manifest.get('actions'), catalog.get('actions')
    if not isinstance(rows, list) or not isinstance(catalog_rows, list) or any(not isinstance(r,dict) for r in rows+catalog_rows):
        raise ImportError('HUB actions must be object lists')
    catalog_ids = _ids([row.get('id') for row in catalog_rows], 'HUB catalog')
    ready_ids = _ids([row.get('id') for row in rows], 'HUB ready records')
    by_id = {row['id']: row for row in catalog_rows}
    if not ready_ids <= catalog_ids:
        raise ImportError('Ready record is outside HUB full catalog')
    for document, label in [(manifest,'manifest'),(catalog,'catalog')]:
        if (document.get('totalCount') != len(catalog_ids) or document.get('readyCount') != len(ready_ids)
                or document.get('pendingCount') != len(catalog_ids-ready_ids)
                or set(document.get('pendingIds',[])) != catalog_ids-ready_ids):
            raise ImportError(f'HUB {label} ready/pending counts do not pair consistently')
    for row in catalog_rows:
        if row.get('reviewed') is not False or row.get('releaseEligible') is not False:
            raise ImportError(f'Catalog action is not explicitly test-unreviewed: {row["id"]}')
        ready = row['id'] in ready_ids
        if (row.get('availableForApp') is True) != ready or (row.get('state')=='ready-test-unreviewed') != ready:
            raise ImportError(f'Catalog readiness differs from manifest: {row["id"]}')
    actions, rejected = [], {}
    for row in rows:
        aid = row['id']
        if row.get('reviewed') is not False or row.get('releaseEligible') is not False:
            raise ImportError(f'Ready action is not explicitly unreviewed: {aid}')
        if (row.get('availableForApp') is not True
                or manifest.get('states',{}).get(aid,{}).get('state')!='ready-test-unreviewed'
                or by_id[aid].get('files') != row.get('files')):
            raise ImportError(f'Ready record/catalog/state mismatch: {aid}')
        try:
            media = row.get('files', {})
            specs = []
            for role, width, height in [('video',720,1440),('cover',720,720),('thumbnail',240,240)]:
                descriptor = media.get(role)
                if not isinstance(descriptor,dict) or descriptor.get('width')!=width or descriptor.get('height')!=height:
                    raise ImportError(f'Missing delivered {role} geometry: {aid}')
                if role=='video' and (descriptor.get('codec')!='h264' or descriptor.get('pixelFormat')!='yuv420p'):
                    raise ImportError(f'Unsupported delivered video metadata: {aid}')
                if role!='video' and descriptor.get('alpha') is not True:
                    raise ImportError(f'Alpha is not declared for {aid}/{role}')
                specs.append(_descriptor(descriptor))
            qa = row.get('qa',{})
            if qa.get('metrics',{}).get('passed') is not True:
                raise ImportError(f'Delivered QA is not complete/passed: {aid}')
            expected = {'fps': row.get('fps'), 'frames': row.get('frames'),
                        'durationSeconds': row.get('durationSeconds'), 'colorSpace':'bt709','colorRange':'tv'}
            if any(type(expected[k]) not in (int,float) or expected[k]<=0 for k in ['fps','frames','durationSeconds']):
                raise ImportError(f'Missing delivered video timing: {aid}')
            actions.append(ReadyAction(aid,*specs,expected_video=expected,qa_report=_descriptor(qa['report'])))
        except (ImportError, KeyError, TypeError) as error:
            rejected[aid] = str(error)
    return TestPack(manifest['id'],manifest_bytes,catalog_bytes,tuple(sorted(catalog_ids)),tuple(actions),
                    encoding=encoding,rejected_actions=rejected)


def _descriptor(value: dict) -> FileSpec:
    if not isinstance(value,dict):
        raise ImportError('Expected delivered file descriptor object')
    try:
        return FileSpec(value['path'],value['bytes'],value['sha256'])
    except KeyError as error:
        raise ImportError('Missing path/bytes/sha256 in delivered file descriptor') from error


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--app-root', type=Path, default=APP_ROOT)
    parser.add_argument('--allow-unreviewed-internal', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args(argv)
    try:
        pack = load_source(args.source)
        index = import_pack(args.source, args.app_root, pack,
                            internal_opt_in=args.allow_unreviewed_internal, apply=args.apply,
                            skip_unverified_ready=True)
    except ImportError as error:
        parser.exit(2, f'App-test import stopped: {error}\n')
    print(json.dumps({'id': index['id'], 'catalogActions': len(index['catalogIds']),
                      'readyActions': len(index['actions']), 'applied': args.apply}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
