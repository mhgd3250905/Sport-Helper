# SmartFit icon review candidates

The 2026-10-24 request supersedes the earlier cropped B choice: return to the
original full-body artwork and make it slightly larger with complete feet.
**A2 is the user-selected default.** After the physical-device icon check on
2026-10-24, the user explicitly approved A2 and merging/pushing the icon/brand
branch to main. This selects the production icon resources; it does not itself
publish a new production binary.

| Parameter | Source in design/brand-source | Composition |
| --- | --- | --- |
| A | smartfit-icon-v3.png | Original full body |
| B | smartfit-icon-v4-crop.png | Original supplied crop; lower legs cut by source |
| A2 | smartfit-icon-v3-fullbody-zoom.png | Modest full-body enlargement, complete shoes |

Original A/B sources, generated candidates, previews, and delivered APKs remain.
The exact built-in image_gen edit prompt, reference hash, generated hash and
uniform size normalization for A2 are in `fullbody-zoom-provenance.json`.
All three pipeline sources are 1024x1024 opaque RGB, full bleed without rounding.
The original 1254x1254 A2 tool output is retained byte-for-byte under
`archive/smartfit-icon-v3-fullbody-zoom-generated-1254.png`, outside bundled App
assets. Keep the original sources and archive when preparing future variants.

## Generate and verify

Python and Pillow are used by the existing deterministic launcher pipeline:

```powershell
python tools/branding/build_icons.py
python tools/branding/build_icons.py --check
python -m unittest discover -s tools/branding
python tools/branding/build_icons.py --check --preview .buildlog/branding/icon-mask-preview.png
```

The generator checks source hashes and all 38 protected local default files,
then requires the defaults to match the A2 output independently of that snapshot.
It writes only candidate files and the generated manifest, never default
production assets. It verifies candidate directory inventory, reports unexpected
files and deletes nothing. There are 118 generated files for the three choices.

Android uses 108dp layers, an independently extended mint/teal gradient, and a
46dp whole-image foreground whose 65.05dp diagonal fits the 66dp safe circle.
No subject or source corner is clipped by the safe-circle boundary. Standard
legacy sizes are 48/72/96/144/192px, and layer sizes are 108/162/216/324/432px.
A2 enlarges the illustration within its source canvas without increasing the
adaptive layer beyond the safe area. The A/B/A2 circle/rounded preview is
`docs/screenshots/icon-fullbody-zoom/icon-mask-preview.png`.

## Android selection and packages

`--dart-define=SMARTFIT_ICON_VARIANT=A|B|A2` adds only the selected internal
resource directory. Direct Gradle builds can use `-PsmartfitIconVariant=A2`.
Matching property/define choices are accepted; conflicting choices fail.
Omitting the choice uses the prepared A2 default from main/res. Production
does not read the internal candidate source sets.

```powershell
./tools/branding/build_icon_candidates.ps1 -AppKeyFile '<local key file>' -Variants A2 -OutputDirectory .buildlog/icon-a2/install
```

The wrapper defaults to A2/build22; A and B remain explicit options. It builds internal
arm64 release packages serially, injects the committed source SHA, retains the
internal media parameters, and never prints the key or full command. It checks
matching App/report build identity, the approved SDK lock and clean runtime
before/after each build, runs the final DEX/JNI gate, and writes hash-bound receipts.

`SmartFit-0.1.0+22-internal-iconA2.apk` uses the same
`com.ugk.smartfit.internal`, versionCode2022 with the same signer as the current +21 A/B
packages so it can upgrade the current App without a data reset. Use a new
output directory to retain historical packages and receipts. Source SHA in the
exported report distinguishes builds with the same versionCode. The branch
retains all approved main performance defaults; this icon edit changes no Dart
theme token, SDK or rendering logic and is not a new timing measurement.

## iOS

AppIconA, AppIconB and AppIconA2 appiconsets cover every existing iPhone/iPad
and 1024px marketing slot with opaque images. The local default AppIcon contains
A2 in all19 existing slots, with the original slot file and three Xcode build
configurations retained. Explicit IconA/B/A2.internal.xcconfig overrides select
only the appiconset; they change no bundle ID, scheme, signing or provisioning.
No existing scheme imports these overrides. macOS compilation/signing remains
unverified on this Windows host.

The A2 review uses build22 to exercise a normal Android version upgrade after
same-version replacements retained the old MIUI icon. Historical A/B build21
packages are preserved; installing an older build over build22 may be rejected
as a downgrade. No App data or launcher data is cleared to change icons.
Both build21 and build22 still showed the old cached B icon before the user
rebooted. After that reboot, the system App-info icon matched A2 with complete
shoes and robot; the installed build22 hash was unchanged.
