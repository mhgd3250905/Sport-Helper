"""Portable launcher for the same frozen Dart capture driver on two checkouts.

Run this script from the +51 checkout; --checkout selects base or new sources.
It writes only capture tooling, missing verified fixture images, explicit evidence,
and the chosen PNG output. It never changes tracked application source or Git refs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(checkout, *args):
    return subprocess.check_output(['git', *args], cwd=checkout).decode().strip()

def copy_identical_or_new(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert sha(source) == sha(target), f'Preserve differing existing file: {target}'
    else:
        with source.open('rb') as incoming, target.open('xb') as outgoing:
            shutil.copyfileobj(incoming, outgoing)

def inputs_identity(checkout):
    paths = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=checkout,
    ).decode().split('\0')
    rows = {path: sha(checkout / path) for path in paths if path and
            (path.startswith(('lib/', 'android/', 'assets/', 'test/')) or
             path in ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'))
            and (checkout / path).is_file()}
    encoded = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode()
    return hashlib.sha256(encoded).hexdigest(), rows

def provision_images(checkout):
    manifest_path = ROOT / 'media-inputs.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    index = checkout / 'assets/posehub/images-index.json'
    assert sha(index) == manifest['sourceBundledIndexSha256'], 'Capture index differs from approved input.'
    for row in manifest['images']:
        source = (ROOT / row['fixture']).resolve(strict=True)
        target = (checkout / row['asset']).resolve()
        assert source.is_relative_to(ROOT.resolve())
        assert target.is_relative_to((checkout / 'assets/posehub/images').resolve())
        assert source.stat().st_size == row['bytes'] and sha(source) == row['sha256']
        copy_identical_or_new(source, target)
    return sha(manifest_path)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--variant', choices=['base', 'new'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--flutter', default='flutter')
    parser.add_argument('--pub-cache', type=Path)
    parser.add_argument('--pub-hosted-url', default='https://pub.dev')
    parser.add_argument('--adapter', type=Path)
    parser.add_argument('--inputs', type=Path, default=ROOT / 'inputs.json')
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    assert Path(git(checkout, 'rev-parse', '--show-toplevel')).resolve() == checkout
    head = git(checkout, 'rev-parse', 'HEAD')
    if args.variant == 'base':
        assert head == '13c0bb4cc24982be50bbb2471fc83ace6f64e40b', 'Base commit must remain fixed.'
    evidence, output = args.evidence.resolve(), args.output.resolve()
    assert not evidence.exists(), 'Use a fresh evidence directory; keep prior receipts.'
    assert not output.exists(), 'Use a fresh PNG directory; preserve prior frames.'
    assert not evidence.is_relative_to(output) and not output.is_relative_to(evidence)
    evidence.mkdir(parents=True)
    driver = ROOT / 'capture_test.dart'
    adapter = args.adapter or (ROOT / ('capture_adapter_base.dart.template'
        if args.variant == 'base' else 'capture_adapter.dart'))
    assert driver.exists() and adapter.exists() and args.inputs.exists()
    tools = checkout / 'tools/ui_kit_frames'
    copy_identical_or_new(driver, tools / 'capture_test.dart')
    copy_identical_or_new(adapter, tools / 'capture_adapter.dart')
    image_manifest_sha = provision_images(checkout)
    source_sha, source_files = inputs_identity(checkout)
    env = dict(os.environ, PUB_HOSTED_URL=args.pub_hosted_url)
    if args.pub_cache:
        env['PUB_CACHE'] = str(args.pub_cache.resolve())
    command_prefix = [args.flutter]
    flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    with (evidence / 'strict-lock.log').open('x', encoding='utf-8', newline='\n') as log:
        result = subprocess.run([*command_prefix, 'pub', 'get', '--offline', '--enforce-lockfile'],
                                cwd=checkout, env=env, stdout=log, stderr=subprocess.STDOUT, **flags)
    assert result.returncode == 0, 'Prepare the pinned dependency cache, then rerun in a fresh evidence directory.'
    assert inputs_identity(checkout) == (source_sha, source_files), 'Strict resolution changed source/lock.'
    config = {'variant': args.variant, 'source': head,
              'inputs': args.inputs.resolve().as_posix(), 'output': output.as_posix(),
              'mediaCache': (evidence / 'image-cache').as_posix(),
              'publicInputsSha256': source_sha, 'driverSha256': sha(driver),
              'adapterSha256': sha(adapter), 'mediaFixtureManifestSha256': image_manifest_sha,
              'focusImplementation': 'SDK' if 'sdk.PlanFocusLabel(' in adapter.read_text(encoding='utf-8') else 'host-local'}
    config_file = evidence / 'config.json'
    with config_file.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(config, stream, indent=2)
        stream.write('\n')
    command = [*command_prefix, 'test', '--no-pub', '--flavor', 'internal', '--concurrency=1',
        '--reporter', 'expanded', '--dart-define=SMARTFIT_ALPHA_CARDS=true',
        '--dart-define=SMARTFIT_POSEHUB_PACK=true', '--dart-define=UGK_INTERNAL_MEDIA_PREVIEW=true',
        f'--dart-define=SMARTFIT_UI_KIT_CAPTURE_CONFIG={config_file.as_posix()}',
        'tools/ui_kit_frames/capture_test.dart']
    with (evidence / 'capture.log').open('x', encoding='utf-8', newline='\n') as log:
        result = subprocess.run(command, cwd=checkout, env=env, stdout=log,
                                stderr=subprocess.STDOUT, **flags)
    assert git(checkout, 'rev-parse', 'HEAD') == head, 'HEAD changed while capturing.'
    assert inputs_identity(checkout) == (source_sha, source_files), 'Compiled source changed while capturing.'
    with (evidence / 'run.json').open('x', encoding='utf-8', newline='\n') as stream:
        json.dump({'configuration': config, 'publicInputs': source_files,
                   'command': command, 'exitCode': result.returncode,
                   'logSha256': sha(evidence / 'capture.log')}, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'source': head, 'variant': args.variant, 'exitCode': result.returncode,
                      'driverSha256': sha(driver), 'output': str(output)}))
    raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()
