# Internal icon candidates

The reviewed 1024 × 1024 sources are stored in `assets/brand/source/`:

- A: `smartfit-icon-v3.png`, full body.
- B: `smartfit-icon-v4-crop.png`, supplied crop. Its lower legs are already cut by the source image edge.

Regenerate both candidates with Python and Pillow. No pub dependency is added.

```powershell
python tools/branding/build_icons.py
python tools/branding/build_icons.py --check
python -m unittest discover -s tools/branding -p 'test_*.py'
python tools/branding/build_icons.py --check --preview .buildlog/branding/icon-mask-preview.png
```

The generator verifies the source SHA-256 values and a snapshot of the original
production icon files before writing. Its output manifest records every generated
file's size and SHA-256. It never writes `android/app/src/main/res` or the original
iOS `AppIcon.appiconset`. Generation and verification also reject unexpected
files inside the two owned candidate Android resource directories and the two
candidate iOS appiconsets. They report stale files for inspection and delete
nothing; unrelated tooling and production directories are not scanned.

## Android selection

Only the `internal` source set receives the selected resource directory. The
`production` source set and the existing application IDs remain unchanged.
Omitting the parameter retains the original launcher icon.

```powershell
flutter build apk --release --no-pub --flavor internal --build-number 21 --target-platform android-arm64 --split-per-abi --dart-define=SMARTFIT_ICON_VARIANT=A --dart-define=SMARTFIT_BUILD_SOURCE=<committed-source-sha>
flutter build apk --release --no-pub --flavor internal --build-number 21 --target-platform android-arm64 --split-per-abi --dart-define=SMARTFIT_ICON_VARIANT=B --dart-define=SMARTFIT_BUILD_SOURCE=<committed-source-sha>
```

Direct Gradle invocations can use `-PsmartfitIconVariant=A` or `B`.
Supplying both parameter forms is allowed only when their
values agree; conflicting values fail instead of silently overriding a choice.
The Gradle property can also be supplied through Gradle's standard environment
mechanism, which is subject to the same conflict check. Both candidates keep
`com.ugk.smartfit.internal` and the same version
code, **2021** for these split arm64 APKs. They can cover-install each other and
the existing +21 sampling build without a version downgrade. The original
sampling APK is a separate, unchanged artifact.

The wrapper builds both choices serially and copies each APK before the next
build, so one build's output cannot overwrite the other candidate:

```powershell
./tools/branding/build_icon_candidates.ps1 -AppKeyFile '<local app-key file>'
```

Optional arguments include `-Variants A` (or B), `-MediaPrimaryUrl`,
`-MediaSecondaryUrl`, and `-OutputDirectory`. By default it produces
`SmartFit-0.1.0+21-internal-iconA.apk` and
`SmartFit-0.1.0+21-internal-iconB.apk` in `.buildlog/brand-review/install/`.
The wrapper adds the existing internal media and Worker key parameters without
printing their values.

These are **release** internal packages for launcher icon and brand color review.
The branch is rebased onto the approved performance main, including the +21
static suggestion-strip defaults, internal recorder, and release/JNI corrections.
The wrapper checks committed runtime files, matching diagnostic build identities,
the approved SDK lock, actual source SHA, and the storage JNI gate for each APK.
It records a hash-bound receipt next to each package. It does not change the
production icon. The two candidates have identical theme tokens and runtime
behavior; they differ only in launcher artwork.

Each candidate contains legacy 48/72/96/144/192 px icons and adaptive
108/162/216/324/432 px foreground/background layers. The complete square artwork
is centered at **46 dp** inside the 108 dp layer. Its 65.05 dp diagonal fits
inside Android's 66 dp safe circle, including every corner. This deliberately
retains margin around the illustration. The gradient background samples the
source's mint/teal corner colors and anchors its gradient to the foreground
edges; this reduces the seam that a separate full-width gradient would produce.
The full opaque foreground is retained without cropping, rounding, or masking.

Android defines the 108 dp layers and 66 dp safe area in the
[official adaptive icon guide](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
The diagnostic preview simulates circular and rounded-square launcher masks;
actual launcher caching and animation still need the requested phone A/B check.

## iOS selection

`AppIconA.appiconset` and `AppIconB.appiconset` duplicate every existing iPhone,
iPad, and 1024 px marketing slot with opaque RGB images. The original production
AppIcon remains unchanged. No existing scheme includes the new override files.

This repository currently has no separate iOS internal scheme or provisioning
identity. `IconA.internal.xcconfig` and `IconB.internal.xcconfig` contain only
`ASSETCATALOG_COMPILER_APPICON_NAME`; they do not alter signing or bundle IDs.
On macOS, a caller with an appropriately provisioned internal build can select
one explicitly with `xcodebuild -xcconfig Flutter/IconA.internal.xcconfig` (or B).
No iOS build or signing verification was performed on this Windows host.
