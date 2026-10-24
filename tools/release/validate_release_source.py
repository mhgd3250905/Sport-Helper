"""Protect the accepted runtime while allowing only the authorized publication fixes."""
import subprocess
import plistlib
from pathlib import Path

from prepare_production_media import check

ROOT = Path(__file__).resolve().parents[2]
BASELINE = 'f5332bfe3746ecbf69d3f5e48c71ba5c90812499'
ALLOWED = {
    'lib/app/build_info.dart',
    'lib/ui/about_page.dart',
    'lib/ui/legal_policy_page.dart',
    'assets/training_media/v0.3.0-app/app-manifest.json',
    'assets/packs/index.json',
    'assets/packs/s-figure4/pack.json',
    'assets/packs/w-dead-bug/pack.json',
    'assets/voice_lc32/v1/manifest.json',
    'ios/Runner/Info.plist',
    *[f'assets/{base}/s-figure4/{lang}/{name}.m4a'
      for base, lang in [('packs', 'voice/zh'), ('voice_lc32/v1', 'zh')]
      for name in ['cue1', 'cue2', 'side_switch', 'rest']],
}


def validate_ios_info():
    original = subprocess.run(
        ['git', 'show', f'{BASELINE}:ios/Runner/Info.plist'],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout
    expected = plistlib.loads(original)
    expected['CFBundleDisplayName'] = 'SmartFit'
    expected.pop('UISupportedInterfaceOrientations~ipad', None)
    expected['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
    expected['UIBackgroundModes'] = ['audio']
    actual = plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes())
    if actual != expected:
        raise ValueError('Unexpected iOS Info.plist changes beyond the iPhone release configuration')


def validate():
    validate_ios_info()
    paths = subprocess.run(
        ['git', 'diff', '--name-only', BASELINE, '--', 'lib', 'assets',
         'android/app/src/main/AndroidManifest.xml',
         'android/app/src/main/res/values/strings.xml', 'ios/Runner/Info.plist'],
        cwd=ROOT, text=True, capture_output=True, check=True,
    ).stdout.splitlines()
    unexpected = set(paths) - ALLOWED
    if unexpected:
        raise ValueError(f'Unexpected accepted-runtime changes: {sorted(unexpected)}')
    return check()


if __name__ == '__main__':
    print(validate())
