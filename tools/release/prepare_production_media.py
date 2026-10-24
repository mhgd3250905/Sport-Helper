"""Apply/check the owner's App-specific publication roster without bypassing SDK gates."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = 'assets/training_media/v0.3.0-app/app-manifest.json'
AUTHORIZATION = ROOT / 'docs/store/1.0.0/production-media-authorization.json'


def expected_manifest():
    approval = json.loads(AUTHORIZATION.read_text(encoding='utf-8'))
    original = subprocess.run(
        ['git', 'show', f"{approval['baselineCommit']}:{MANIFEST}"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout
    if hashlib.sha256(original).hexdigest() != approval['baselineManifestSha256']:
        raise ValueError('Publication roster baseline manifest changed')
    expected = json.loads(original)
    approved = approval['actionIds']
    if len(approved) != 93 or len(set(approved)) != 93:
        raise ValueError('The accepted complete App roster must contain exactly 93 actions')
    index = json.loads((ROOT / 'assets/packs/index.json').read_text(encoding='utf-8'))
    actual = {p['id'] for p in index['packs'] if p['kind'] == 'exercise'}
    if set(approved) != actual:
        raise ValueError('Publication roster must match every accepted App exercise')
    source_ids = {a['id'] for a in expected['actions']}
    if not actual <= source_ids:
        raise ValueError('An approved exercise is absent from the media source')
    for action in expected['actions']:
        action['releaseEligible'] = action['id'] in actual
    return expected


def check():
    expected = expected_manifest()
    actual = json.loads((ROOT / MANIFEST).read_text(encoding='utf-8'))
    if actual != expected:
        raise ValueError('Production manifest does not match the authorized roster; run with --apply')
    return {'eligibleAppActions': 93, 'otherActionsStillPending': len(actual['actions']) - 93}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply:
        (ROOT / MANIFEST).write_bytes(
            (json.dumps(expected_manifest(), ensure_ascii=False, separators=(',', ':')) + '\n').encode('utf-8')
        )
    print(json.dumps(check()))
