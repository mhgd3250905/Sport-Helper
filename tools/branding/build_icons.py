#!/usr/bin/env python3
"""Generate opt-in internal launcher icons without touching production assets.

Requires Pillow. Run from any directory:
  python tools/branding/build_icons.py
  python tools/branding/build_icons.py --check

Android uses a 108 dp layer with a 66 dp safe circle. The complete square
source is only 46 dp wide: even its corners fit inside that circle. No subject
segmentation, rounding, cropping, or artwork regeneration is performed.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
VARIANTS = {
    "A": ("smartfit-icon-v3.png", "5489859ef71dd279453f46e15d0d1632eabf7f5cbdc7e677d591c34f14f8637c"),
    "B": ("smartfit-icon-v4-crop.png", "a89d37b544942fe852b96e38b0faaaf66ac0d926d70037c227d0a102236d65f8"),
}
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
LAYER_DP = 108
SAFE_DIAMETER_DP = 66
FOREGROUND_DP = 46
OWNED_RESOURCE_ROOTS = (
    "android/app/src/internal/iconVariants/A/res",
    "android/app/src/internal/iconVariants/B/res",
    "ios/Runner/Assets.xcassets/AppIconA.appiconset",
    "ios/Runner/Assets.xcassets/AppIconB.appiconset",
)
ADAPTIVE_XML = b'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def png_bytes(image: Image.Image) -> bytes:
    output = io.BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()


def read_source(root: Path, variant: str) -> tuple[Image.Image, bytes]:
    filename, digest = VARIANTS[variant]
    content = (root / "assets/brand/source" / filename).read_bytes()
    if sha256(content) != digest:
        raise ValueError(f"Icon {variant}: source hash differs from the reviewed artwork")
    image = Image.open(io.BytesIO(content))
    image.load()
    if image.size != (1024, 1024):
        raise ValueError(f"Icon {variant}: expected a 1024 x 1024 source")
    if image.mode not in ("RGB", "RGBA") or (
        image.mode == "RGBA" and image.getextrema()[3] != (255, 255)
    ):
        raise ValueError(f"Icon {variant}: expected opaque, full-bleed source artwork")
    return image.convert("RGB"), content


def foreground(source: Image.Image, scale: float) -> Image.Image:
    size = round(LAYER_DP * scale)
    content_size = round(FOREGROUND_DP * scale)
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    resized = source.resize((content_size, content_size), Image.Resampling.LANCZOS)
    offset = (size - content_size) // 2
    image.paste(resized, (offset, offset))
    return image


def gradient(source: Image.Image, scale: float) -> Image.Image:
    """Extend a mint/teal gradient sampled at the artwork's four corners.

    Anchor its endpoints at the foreground square, then clamp outside. A
    full-layer gradient would have a different slope and create a conspicuous
    square around the supplied, opaque artwork. No source pixels are removed.
    """
    size = round(LAYER_DP * scale)
    content_size = round(FOREGROUND_DP * scale)
    offset = (size - content_size) // 2
    last = source.width - 1
    corners = [source.getpixel(point) for point in ((0, 0), (last, 0), (0, last), (last, last))]
    image = Image.new("RGB", (size, size))
    column_values = []
    for x in range(size):
        tx = min(1, max(0, (x - offset) / (content_size - 1)))
        column_values.append((
            tuple(a + (b - a) * tx for a, b in zip(corners[0], corners[1])),
            tuple(a + (b - a) * tx for a, b in zip(corners[2], corners[3])),
        ))
    pixels = bytearray()
    for y in range(size):
        ty = min(1, max(0, (y - offset) / (content_size - 1)))
        for top, bottom in column_values:
            pixels.extend(round(a + (b - a) * ty) for a, b in zip(top, bottom))
    image.frombytes(bytes(pixels))
    return image


def protected_assets(root: Path) -> dict[str, str]:
    """Verify the selected production AppIcon and Android launcher snapshot."""
    records = json.loads((root / "tools/branding/production-icons.sha256.json").read_text("utf-8"))
    for path, expected in records.items():
        if sha256((root / path).read_bytes()) != expected:
            raise ValueError(f"Production icon changed: {path}")
    return records


def selected_production_assets(generated: dict[str, bytes]) -> dict[str, bytes]:
    """Map the reviewed B output to default paths, without writing production."""
    mappings = {
        "android/app/src/internal/iconVariants/B/res/": "android/app/src/main/res/",
        "ios/Runner/Assets.xcassets/AppIconB.appiconset/":
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/",
    }
    return {
        destination + path.removeprefix(source): content
        for source, destination in mappings.items()
        for path, content in generated.items()
        if path.startswith(source)
    }


def verify_selected_production(
    root: Path, generated: dict[str, bytes], protected: dict[str, str]
) -> dict:
    """Reject a changed selection or rebaselined assets that no longer match B."""
    selection = json.loads(
        (root / "tools/branding/production-icon-selection.json").read_text("utf-8")
    )
    if (selection.get("schemaVersion") != 1 or selection.get("variant") != "B"
            or selection.get("source") != f"assets/brand/source/{VARIANTS['B'][0]}"
            or selection.get("sourceSha256") != VARIANTS["B"][1]):
        raise ValueError("Production selection differs from the user-selected B artwork")
    expected = selected_production_assets(generated)
    if set(protected) != set(expected):
        raise ValueError("Production icon snapshot inventory differs from selected B")
    for path, content in expected.items():
        actual = (root / path).read_bytes()
        # Keep the existing Xcode slot file's formatting; its structure is fixed.
        matches = (json.loads(actual) == json.loads(content)
                   if path.endswith("/Contents.json") else actual == content)
        if not matches:
            raise ValueError(f"Selected production B differs: {path}")
    return selection


def verify_owned_inventory(root: Path, generated: dict[str, bytes]) -> None:
    """Reject stale resources without deleting or changing any existing file."""
    unexpected = []
    for directory in OWNED_RESOURCE_ROOTS:
        expected = {path for path in generated if path.startswith(directory + "/")}
        actual = {path.relative_to(root).as_posix()
                  for path in (root / directory).rglob("*") if path.is_file()}
        unexpected.extend(sorted(actual - expected))
    if unexpected:
        raise ValueError(
            "Unexpected candidate icon files; inspect and move/remove them explicitly. "
            "No files were deleted:\n" + "\n".join(unexpected)
        )


def build_assets(root: Path = ROOT) -> dict[str, bytes]:
    protected = protected_assets(root)
    template = json.loads(
        (root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text("utf-8")
    )
    generated: dict[str, bytes] = {}
    variants = {}
    for variant in VARIANTS:
        source, source_bytes = read_source(root, variant)
        android = f"android/app/src/internal/iconVariants/{variant}/res"
        for density, scale in DENSITIES.items():
            legacy_size = round(48 * scale)
            legacy = png_bytes(source.resize((legacy_size, legacy_size), Image.Resampling.LANCZOS))
            generated[f"{android}/mipmap-{density}/ic_launcher.png"] = legacy
            generated[f"{android}/mipmap-{density}/ic_launcher_round.png"] = legacy
            generated[f"{android}/mipmap-{density}/ic_launcher_foreground.png"] = png_bytes(
                foreground(source, scale)
            )
            generated[f"{android}/mipmap-{density}/ic_launcher_background.png"] = png_bytes(
                gradient(source, scale)
            )
        generated[f"{android}/mipmap-anydpi-v26/ic_launcher.xml"] = ADAPTIVE_XML
        generated[f"{android}/mipmap-anydpi-v26/ic_launcher_round.xml"] = ADAPTIVE_XML
        ios = f"ios/Runner/Assets.xcassets/AppIcon{variant}.appiconset"
        for slot in template["images"]:
            point_size = float(slot["size"].split("x")[0])
            scale = int(slot["scale"].rstrip("x"))
            pixels = round(point_size * scale)
            generated[f"{ios}/{slot['filename']}"] = png_bytes(
                source.resize((pixels, pixels), Image.Resampling.LANCZOS)
            )
        generated[f"{ios}/Contents.json"] = json_bytes(template)
        generated[f"ios/Flutter/Icon{variant}.internal.xcconfig"] = (
            "// Opt-in icon override only. Not included by any existing scheme.\n"
            "// Select explicitly with xcodebuild -xcconfig Flutter/Icon"
            f"{variant}.internal.xcconfig on an appropriately provisioned internal build.\n"
            "// Bundle identifier and signing remain the caller's responsibility.\n"
            f"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon{variant}\n"
        ).encode("utf-8")
        variants[variant] = {
            "source": f"assets/brand/source/{VARIANTS[variant][0]}",
            "sourceSize": [1024, 1024],
            "sourceMode": "RGB",
            "sourceSha256": sha256(source_bytes),
            "androidResourceDirectory": android,
            "iosAppIconSet": f"AppIcon{variant}",
            "androidGradientCorners": [
                "#" + "".join(f"{channel:02X}" for channel in source.getpixel(point))
                for point in ((0, 0), (1023, 0), (0, 1023), (1023, 1023))
            ],
        }
    selection = verify_selected_production(root, generated, protected)
    manifest = {
        "schemaVersion": 1,
        "generator": "tools/branding/build_icons.py",
        "productionDefaultVariant": selection["variant"],
        "productionDefaultSourceSha256": selection["sourceSha256"],
        "productionDefaultsProtected": True,
        "protectedProductionAssets": protected,
        "android": {
            "layerDp": LAYER_DP,
            "safeCircleDiameterDp": SAFE_DIAMETER_DP,
            "wholeSourceSquareDp": FOREGROUND_DP,
            "wholeSourceDiagonalDp": round(math.sqrt(2) * FOREGROUND_DP, 6),
            "maximumCornerRadiusDp": round(math.sqrt(2) * FOREGROUND_DP / 2, 6),
            "backgroundGradient": "bilinear source-corner mint/teal gradient, clamped outside foreground",
            "source": "https://developer.android.com/develop/ui/compose/system/icon_design_adaptive",
        },
        "variants": variants,
        "generatedFiles": {
            path: {"bytes": len(content), "sha256": sha256(content)}
            for path, content in sorted(generated.items())
        },
    }
    generated["tools/branding/icon-assets.json"] = json_bytes(manifest)
    verify_owned_inventory(root, generated)
    return generated


def mask_preview(root: Path, path: Path) -> None:
    canvas = Image.new("RGB", (1500, 1060), "#F1F5F5")
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("arial.ttf", 24)
    except OSError:
        font = ImageFont.load_default(size=24)
    columns = ("Source: full image", "Android: circle mask", "Android: rounded mask")
    for column, label in enumerate(columns):
        draw.text((28 + column * 500, 15), label, fill="#173D3B", font=font)
    for row, variant in enumerate(VARIANTS):
        source, _ = read_source(root, variant)
        y = 70 + row * 500
        draw.text((28, y), f"{variant}: {'full body' if variant == 'A' else 'user crop'}", fill="#173D3B", font=font)
        canvas.paste(source.resize((432, 432), Image.Resampling.LANCZOS), (28, y + 38))
        composed = gradient(source, 6).convert("RGBA")
        composed.alpha_composite(foreground(source, 6))
        viewport = composed.crop((108, 108, 540, 540)).convert("RGB")
        for column, circle in ((1, True), (2, False)):
            mask = Image.new("L", (432, 432), 0)
            mask_draw = ImageDraw.Draw(mask)
            if circle:
                mask_draw.ellipse((0, 0, 431, 431), fill=255)
            else:
                mask_draw.rounded_rectangle((0, 0, 431, 431), radius=96, fill=255)
            canvas.paste(viewport, (28 + column * 500, y + 38), mask)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes(canvas))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify generated bytes; write nothing")
    parser.add_argument("--preview", type=Path, help="Also render a diagnostic mask preview")
    args = parser.parse_args()
    generated = build_assets()
    if args.check:
        stale = [path for path, content in generated.items()
                 if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != content]
        if stale:
            raise SystemExit("Generated icon files differ:\n" + "\n".join(stale))
        print(f"Verified {len(generated)} generated files and protected production icons.")
    else:
        for path, content in generated.items():
            destination = ROOT / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        print(f"Generated {len(generated)} candidate files; selected production B is unchanged.")
    if args.preview:
        mask_preview(ROOT, args.preview.resolve())
        print(f"Mask preview: {args.preview.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
