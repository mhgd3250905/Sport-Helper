# Liquid glass — plan (phase 1: spec + two-screen prototype)

> Integration review (2026-10-21, App `0.1.0+9`): chat and plan-card glass
> now retain main's CoachAgent and validated-card flow. The training screen
> uses `ugk_trainer.TrainerPlayer`; only its App background gains the colour
> field. The local-player glass controls and player screenshots below describe
> the earlier prototype, not the integrated player. See [PR #4 review](pr4-local-review.md)
> for the tested source, fixes, screenshots and remaining device checks.

Branch `feat/liquid-glass` on top of `feat/aesthetic-v2` (PR #3). Package
`liquid_glass_widgets` **1.14.0** (pinned exactly). The iOS 26/27 rule holds
everywhere: **glass is only the navigation and control layer; content stays
opaque.** v2 tokens, motion, light mode, haptics, semantics and the PR #3
fixes are unchanged. Glass never nests inside glass.

## 1. App-level setup (done)
`main()`: `await LiquidGlassWidgets.initialize()` → `runApp(LiquidGlassWidgets.wrap(brightnessResolver: Theme.maybeBrightnessOf, adaptiveQuality: true, adaptiveConfig: GlassAdaptiveScopeConfig(initialQuality: <stored>, onQualityChanged: <store>)))`.
The settled tier persists in `AppStore.glassQuality` (same prefs JSON, silent write).
`MaterialApp.builder` wraps `Material(type: transparency)` around `SfPaletteScope`.
`cupertino_icons` added. All glass goes through `lib/ui/theme/glass.dart`
(`SfGlassSurface`, `SfGlassField`, `showSfGlassToast`), so material and quality are in one place.

## 2. Surface inventory
| Page | Glass (material · quality) | Opaque |
|---|---|---|
| Chat home ✅ | input bar (ios27 · **premium**, adaptive cap); discovery chips (ios27 · standard) | bubbles, greeting, plan card, time marks |
| Workout player ✅ | close disc, block/progress capsule, 不舒服 pill (only glass over the video), 下一个 peek, prev/pause/next capsule — all ios27 · **standard**, inside one `GlassBackdropGroup` | video, name, ring counter, subtitles, pause disc (solid accent) |
| Toasts ✅ | `GlassToast` capsule (ios27 · standard) above the input, ignores taps, v2 motion; replaces the SnackBar app-wide | — |
| Drawer (phase 2) | drawer panel as one glass sheet; rows as plain tiles inside | saved-plan rows' thumbnails |
| Sheets / dialogs (phase 2) | `GlassModalSheet` (不舒服, voice), `GlassDialog` (close-training confirm) | sheet content |
| Settings (phase 2) | `GlassSwitch(useOwnLayer)`, `GlassSegmentedControl` (外观), pickers | section text, about rows |
| Plan / custom / library (phase 2) | floating back + start buttons, filter chips | plan lists, library grid, cards |
| Done view (phase 2) | finish button only | stats panels, celebration |

Material: `LiquidGlassSettings.ios27Dark` / `ios27Light`, picked from the
palette in effect (follows the app's dark/light/system choice).

## 3. Background strategy
Flat colour makes glass invisible. `SfGlassField` paints 2–3 very large,
low-alpha radial pools from existing tokens (jade accent + the sky's cool
light) weighted to the bottom where the bars float; the player uses a quieter
0.6× version. Gradients only — no blur filter, no ticker, own repaint boundary.
The star dust and sky gradient stay underneath.

## 4. Performance budget
- Chat home: ≤ 6 glass surfaces (input + ≤ 4–5 chips); one premium (input).
- Player: 5 surfaces, all ≤ standard, one group; exactly **one** over the
  video. `GlassAdaptiveScope` caps lower on weak devices (minimal = blur only).
- No glass in scrolling lists; no glass under the countdown ring.
- Device check: `GlassPerformanceMonitor` (debug) on a mid-range Android;
  target 60 fps during the countdown with the video playing.

## 5. Risks
- 1.14.0 is hours old: API churn / shader bugs → pinned; one wrapper to patch.
- Android GLES vs Vulkan differences in the premium path; the adaptive scope is the safety net.
- Premium glass over the WebView video (platform view) is not used — 不舒服 is standard and small.
- Light mode: white glass on paper can wash out; the colour field and the premium rim carry it — verify on device.

## 6. Tests and screenshots
The test renderer cannot run the glass shaders, so `test/flutter_test_config.dart`
and `test_screens/flutter_test_config.dart` set `SfGlass.qualityOverride = GlassQuality.minimal`
(BackdropFilter + tint). Screenshots therefore show frosted glass without
refraction, rim light or rim shade; on device premium/standard look markedly
glassier. `docs/screenshots/liquid-glass/compare.jpg`.

## 7. Phase-2 rollout (est.)
1. Drawer as glass sheet + close-training `GlassDialog` + 不舒服/voice `GlassModalSheet` — 0.5 d
2. Settings: `GlassSwitch`, `GlassSegmentedControl` 外观, pickers — 0.5 d
3. Plan page / custom form / library: floating back & start, filter chips — 0.5 d
4. Done view finish button, remaining SfCircleButton chrome — 0.25 d
5. On-device pass (dark/light, mid-range Android), perf monitor, tune field alphas — 0.5 d
6. Tests for new surfaces + screenshots + PR — 0.25 d
Total ≈ 2.5 days of agent work.
