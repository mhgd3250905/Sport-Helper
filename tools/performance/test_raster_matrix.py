"""Synthetic schema-2 unit fixtures; these numbers are not device measurements."""

import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from raster_matrix import (
    SCENARIOS, VARIANTS, WINDOWS, build_matrix, load_report, main,
    pair_issues, render_matrix,
)


def window(count=100, average=8.0, worst=24.0, over=10, hz=120.0):
    raster = {
        "averageMs": average if count else None,
        "p90Ms": 12.0 if count else None,
        "p99Ms": 20.0 if count else None,
        "worstMs": worst if count else None,
        "overBudgetFrames": over if count else 0,
        "overBudgetRatio": over / count if count else None,
    }
    return {"frameCount": count, "raster": raster, "uiBuild": copy.deepcopy(raster),
            "refreshRatesHz": [hz] if count else [], "refreshRatesTruncated": False}


def cell(variant, scenario, average=8.0):
    key = f"{variant}__{scenario}"
    condition = {
        "glassEnabled": variant.startswith("glass_on_"),
        "starfield": variant.endswith("_stars_on"),
        "glassQuality": "standard", "glassPhase": "steady", "glassFrost": True,
        "renderer": "Impeller", "rendererBackend": "vulkan", "refreshRateHz": 120.0,
        "frameBudgetMs": 1000 / 120, "adaptiveTargetFrameMs": 1000 / 120,
        "theme": "dark", "viewportWidth": 390.0, "viewportHeight": 844.0,
        "devicePixelRatio": 3.0, "textScale": 1.0,
    }
    result = {
        "id": key, "variant": variant, "scenario": scenario,
        "fixtureId": "chat_72_v1" if scenario == "longChatScroll" else "plans_72_v1",
        "messageCount": 72, "completed": True, "observedDurationSeconds": 30.5,
        "pages": ["chat_home"], "comparisonReady": True, "comparisonIssues": [],
        "overflowConditionFrameCount": 0,
        "allFrames": window(110, average=average, over=11),
        "warmupFirst2Seconds": window(10, average=average, over=1),
        "steadyState": window(100, average=average),
        "firstPageEntryFirst2Seconds": window(0),
    }
    result["conditions"] = [{"condition": condition, **{key: copy.deepcopy(result[key]) for key in WINDOWS}}]
    return result


def report():
    return {
        "schema": 2, "reportType": "frame_performance", "app": "smartfit",
        "startedAt": "2026-10-23T07:00:00.000000Z", "exportedAt": "2026-10-23T07:10:00Z",
        "metadata": {
            "deviceModel": "unit-device", "deviceManufacturer": "unit-maker", "systemVersion": "16",
            "deviceApiLevel": 36, "platform": "android", "isEmulator": False,
            "appVersion": "unit-0.1.0", "appBuild": "17", "appBuildNumber": 17,
            "appSource": "unit-source-17", "appBaseCommit": "unit-base", "sdkRef": "unit-sdk",
            "buildMode": "release", "flavor": "internal", "measurementKind": "raster_controls_v2",
            "metadataStatus": "available", "theme": "dark", "appearance": "system",
            "refreshRateSource": "android_display", "renderer": "impeller", "rendererBackend": "vulkan",
            "rendererVerified": True, "rendererSource": "android_engine_startup_log_own_pid",
        },
        "cases": {f"{variant}__{scenario}": cell(variant, scenario, average=8.0 - index)
                  for index, variant in enumerate(VARIANTS) for scenario in SCENARIOS},
        "pageEntries": {"chat_home": {"firstVsyncStartUs": 1000000,
                                      "first2Seconds": window(100, worst=90),
                                      "earlierOutOfOrderFrameCount": 0}},
    }


def update_condition(report_value, key, **changes):
    report_value["cases"][key]["conditions"][0]["condition"].update(changes)


def sync_windows(value):
    for key in WINDOWS:
        value["conditions"][0][key] = copy.deepcopy(value[key])


class RasterMatrixTests(unittest.TestCase):
    def test_full_matrix_has_eight_rows_and_fixed_within_scene_pairs(self):
        matrix = build_matrix([report()])
        self.assertTrue(all(not value.issues for value in matrix.cells.values()))
        output = render_matrix(matrix)
        steady = output.split("## 稳态 Raster", 1)[1].split("## 每格实际列表卡片模式", 1)[0]
        self.assertEqual(steady.count("| glass_"), 8)
        differences = output.split("## 仅同场景", 1)[1]
        self.assertEqual(differences.count("| longChatScroll |"), 4)
        self.assertEqual(differences.count("| planCardScroll |"), 4)
        self.assertIn("有效格 8/8", output)
        self.assertIn("| longChatScroll | 关闭星尘（玻璃开） | -1.000 | +0.000 | +0.000 | +0.00 |", output)
        self.assertIn("每格已记录实际窗口尺寸", output)
        self.assertIn("不能确认着色器编译", output)

    def test_new_static_card_report_requires_explicit_actual_mode(self):
        value = report()
        value["metadata"]["measurementKind"] = "raster_controls_v3"
        for item in value["cases"].values():
            item["conditions"][0]["condition"]["scrollCardGlassEnabled"] = False
        matrix = build_matrix([value])
        self.assertTrue(all(not cell.issues for cell in matrix.cells.values()))
        self.assertIn("默认静态仿玻璃", render_matrix(matrix))
        for scenario in SCENARIOS:
            for left, right in ((VARIANTS[0], VARIANTS[1]), (VARIANTS[0], VARIANTS[2])):
                self.assertEqual(pair_issues(matrix.cells[f"{left}__{scenario}"],
                                             matrix.cells[f"{right}__{scenario}"]), [])
        first_key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
        value["cases"][first_key]["conditions"][0]["condition"].pop("scrollCardGlassEnabled")
        self.assertIn("actual.scrollCardGlassEnabled 未确认", build_matrix([value]).cells[first_key].issues)

    def test_new_different_card_modes_are_not_compared(self):
        value = report()
        value["metadata"]["measurementKind"] = "raster_controls_v3"
        for item in value["cases"].values():
            item["conditions"][0]["condition"]["scrollCardGlassEnabled"] = False
        first_key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
        update_condition(value, first_key, scrollCardGlassEnabled=True)
        matrix = build_matrix([value])
        first = matrix.cells[first_key]
        self.assertFalse(first.issues)
        for other in (VARIANTS[1], VARIANTS[2]):
            self.assertIn("actual.scrollCardGlassEnabled 不同；需同一卡片模式对照", pair_issues(
                first, matrix.cells[f"{other}__{SCENARIOS[0]}"]))

    def test_legacy_card_report_stays_readable_but_cannot_mix_with_new_mode(self):
        old = report()
        matrix = build_matrix([old])
        self.assertTrue(all(not cell.issues for cell in matrix.cells.values()))
        self.assertIn("旧版：沿用全局玻璃（未独立记录）", render_matrix(matrix))
        first_key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
        second_key = f"{VARIANTS[1]}__{SCENARIOS[0]}"
        update_condition(old, second_key, scrollCardGlassEnabled=False)
        matrix = build_matrix([old])
        self.assertIn("列表卡片渲染条件的记录版本不同", pair_issues(matrix.cells[first_key], matrix.cells[second_key]))

    def test_actual_card_glass_cannot_be_on_with_global_glass_off(self):
        value = report()
        key = f"{VARIANTS[2]}__{SCENARIOS[0]}"
        update_condition(value, key, scrollCardGlassEnabled=True)
        self.assertIn("列表卡片真玻璃要求全局玻璃开启", build_matrix([value]).cells[key].issues)

    def test_missing_cell_is_dash_and_never_fabricated_zero(self):
        value = report()
        key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
        del value["cases"][key]
        output = render_matrix(build_matrix([value]))
        self.assertIn(f"| {VARIANTS[0]} | {SCENARIOS[0]} | — | — | — | — | 缺格 |", output)
        self.assertIn("拒绝比较：缺格", output)
        self.assertIn("有效格 7/8", output)

    def test_incomplete_and_short_or_mixed_samples_are_invalid(self):
        for changes in (
            {"completed": False}, {"observedDurationSeconds": 29.99},
            {"comparisonReady": False, "comparisonIssues": ["incomplete"]},
            {"messageCount": 12}, {"overflowConditionFrameCount": 1}, {"conditions": []},
            {"pages": ["chat_home", "settings"]},
        ):
            with self.subTest(changes=changes):
                value = report()
                key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
                value["cases"][key].update(changes)
                matrix = build_matrix([value])
                self.assertTrue(matrix.cells[key].issues)
                self.assertIn(f"| {VARIANTS[0]} | {SCENARIOS[0]} | — | — | — | — | 无效", render_matrix(matrix))

    def test_declared_ready_cannot_hide_invalid_numeric_or_missing_windows(self):
        key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
        for field, bad in (("averageMs", float("nan")), ("p90Ms", None),
                           ("worstMs", 1), ("overBudgetRatio", 0.8), ("overBudgetFrames", 101)):
            with self.subTest(field=field):
                value = report()
                value["cases"][key]["steadyState"]["raster"][field] = bad
                self.assertTrue(build_matrix([value]).cells[key].issues)
        value = report()
        del value["cases"][key]["warmupFirst2Seconds"]
        self.assertTrue(build_matrix([value]).cells[key].issues)

    def test_empty_first_entry_window_remains_dash_without_invalidating_steady(self):
        output = render_matrix(build_matrix([report()]))
        self.assertIn("| 8.000 | 24.000 | — | 24.000 | 24.000 |", output)
        self.assertIn("有效格 8/8", output)

    def test_warmup_and_first_entry_statistics_are_separate_from_steady(self):
        value = report()
        item = value["cases"][f"{VARIANTS[0]}__{SCENARIOS[0]}"]
        item["warmupFirst2Seconds"]["raster"].update(averageMs=14, worstMs=80)
        item["firstPageEntryFirst2Seconds"] = window(10, average=16, worst=90, over=1)
        item["allFrames"]["raster"]["worstMs"] = 90
        sync_windows(item)
        output = render_matrix(build_matrix([value]))
        self.assertIn("| 14.000 | 80.000 | 90.000 | 24.000 | 90.000 |", output)
        self.assertIn("| 8.000 | 12.000 | 20.000 | 10.00% | 有效 |", output)

    def test_only_same_scene_can_be_compared(self):
        matrix = build_matrix([report()])
        left = matrix.cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"]
        right = matrix.cells[f"{VARIANTS[1]}__{SCENARIOS[1]}"]
        self.assertIn("场景不同，拒绝比较", pair_issues(left, right))

    def test_glass_on_star_comparison_requires_same_actual_glass(self):
        for key, changed in (("glassQuality", "minimal"), ("glassPhase", "scrolling"), ("glassFrost", False)):
            with self.subTest(key=key):
                value = report()
                update_condition(value, f"{VARIANTS[1]}__{SCENARIOS[0]}", **{key: changed})
                matrix = build_matrix([value])
                left = matrix.cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"]
                right = matrix.cells[f"{VARIANTS[1]}__{SCENARIOS[0]}"]
                self.assertFalse(right.issues)
                self.assertIn(f"actual.{key} 不同", pair_issues(left, right))

    def test_glass_off_star_comparison_does_not_require_disabled_glass_quality(self):
        value = report()
        update_condition(value, f"{VARIANTS[3]}__{SCENARIOS[0]}", glassQuality="minimal")
        matrix = build_matrix([value])
        self.assertEqual(pair_issues(matrix.cells[f"{VARIANTS[2]}__{SCENARIOS[0]}"],
                                     matrix.cells[f"{VARIANTS[3]}__{SCENARIOS[0]}"]), [])

    def test_fixture_message_count_and_refresh_cannot_change_between_pairs(self):
        for field, changed in (("fixtureId", "other_fixture"), ("messageCount", 73), ("pages", ["other_page"])):
            with self.subTest(field=field):
                value = report()
                value["cases"][f"{VARIANTS[1]}__{SCENARIOS[0]}"][field] = changed
                matrix = build_matrix([value])
                self.assertIn(f"{field} 不同", pair_issues(matrix.cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"],
                                                        matrix.cells[f"{VARIANTS[1]}__{SCENARIOS[0]}"]))
        value = report()
        item = value["cases"][f"{VARIANTS[1]}__{SCENARIOS[0]}"]
        item["conditions"][0]["condition"].update(refreshRateHz=60, adaptiveTargetFrameMs=1000 / 60)
        for key in WINDOWS:
            if item[key]["frameCount"]:
                item[key]["refreshRatesHz"] = [60]
        sync_windows(item)
        matrix = build_matrix([value])
        self.assertIn("actual.refreshRateHz 不同", pair_issues(matrix.cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"],
                                                            matrix.cells[f"{VARIANTS[1]}__{SCENARIOS[0]}"]))

    def test_renderer_actual_switch_or_budget_mismatch_invalidates_cell(self):
        for changes in ({"renderer": "Skia"}, {"rendererBackend": "opengles"},
                        {"glassEnabled": False}, {"starfield": False},
                        {"adaptiveTargetFrameMs": 16.0}, {"glassQuality": "unknown"}):
            with self.subTest(changes=changes):
                value = report()
                key = f"{VARIANTS[0]}__{SCENARIOS[0]}"
                update_condition(value, key, **changes)
                self.assertTrue(build_matrix([value]).cells[key].issues)

    def test_unknown_renderer_or_generic_source_invalidates_all_cells(self):
        for changes in ({"rendererVerified": False}, {"renderer": "unverified"},
                        {"rendererSource": "unknown"}, {"appSource": "working_tree"},
                        {"metadataStatus": "unavailable"}, {"buildMode": "debug"}):
            with self.subTest(changes=changes):
                value = report()
                value["metadata"].update(changes)
                self.assertTrue(all(cell.issues for cell in build_matrix([value]).cells.values()))

    def test_disjoint_files_from_same_session_may_merge_without_averaging(self):
        left, right = report(), report()
        keys = list(left["cases"])
        left["cases"] = {key: left["cases"][key] for key in keys[:4]}
        right["cases"] = {key: right["cases"][key] for key in keys[4:]}
        right["exportedAt"] = "2026-10-23T07:20:00Z"
        right["metadata"]["rendererSource"] += "_cached"
        matrix = build_matrix([left, right])
        self.assertEqual(len(matrix.cells), 8)
        self.assertIn("有效格 8/8", render_matrix(matrix))

    def test_duplicate_cells_and_cross_session_inputs_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate matrix cell"):
            build_matrix([report(), report()])
        left, right = report(), report()
        right["cases"] = {}
        right["startedAt"] = "2026-10-23T08:00:00Z"
        with self.assertRaisesRegex(ValueError, "startedAt"):
            build_matrix([left, right])

    def test_cross_device_renderer_backend_theme_source_or_size_merge_is_rejected(self):
        for key, changed in (("deviceModel", "other"), ("systemVersion", "17"),
                             ("renderer", "skia"), ("rendererBackend", "opengles"),
                             ("theme", "light"), ("appSource", "other-build"),
                             ("sdkRef", "other-sdk"), ("viewportWidth", 400)):
            with self.subTest(key=key):
                left, right = report(), report()
                right["cases"] = {}
                right["metadata"][key] = changed
                with self.assertRaisesRegex(ValueError, f"metadata.{key}"):
                    build_matrix([left, right])

    def test_dimensions_when_present_are_checked_for_pairs(self):
        left, right = report(), report()
        left["metadata"].update(viewportWidth=390, viewportHeight=844)
        right["metadata"].update(viewportWidth=400, viewportHeight=844)
        first = build_matrix([left]).cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"]
        second = build_matrix([right]).cells[f"{VARIANTS[1]}__{SCENARIOS[0]}"]
        self.assertIn("metadata.viewportWidth 不同", pair_issues(first, second))

    def test_actual_theme_and_dimensions_are_strong_pair_conditions(self):
        for key, changed in (("viewportWidth", 400), ("viewportHeight", 850),
                             ("devicePixelRatio", 2.5), ("textScale", 1.2)):
            with self.subTest(key=key):
                value = report()
                second_key = f"{VARIANTS[1]}__{SCENARIOS[0]}"
                update_condition(value, second_key, **{key: changed})
                matrix = build_matrix([value])
                self.assertIn(f"actual.{key} 不同", pair_issues(
                    matrix.cells[f"{VARIANTS[0]}__{SCENARIOS[0]}"], matrix.cells[second_key]))
        value = report()
        second_key = f"{VARIANTS[1]}__{SCENARIOS[0]}"
        update_condition(value, second_key, theme="light")
        self.assertIn("每帧实际主题与报告元数据不同", build_matrix([value]).cells[second_key].issues)

    def test_missing_actual_dimensions_refuses_comparison_and_explains_resampling(self):
        value = report()
        second_key = f"{VARIANTS[1]}__{SCENARIOS[0]}"
        value["cases"][second_key]["conditions"][0]["condition"].pop("viewportWidth")
        matrix = build_matrix([value])
        self.assertTrue(matrix.cells[second_key].issues)
        output = render_matrix(matrix)
        self.assertIn("尺寸未记录或不完整", output)
        self.assertIn("拒绝比较：含无效格", output)

    def test_global_first_entry_keeps_pre_case_spike_separate(self):
        output = render_matrix(build_matrix([report()]))
        global_section = output.split("## 全局首次进页", 1)[1].split("## 仅同场景", 1)[0]
        self.assertIn("| chat_home | 100 | 8.000 | 12.000 | 20.000 | 90.000 | 10.00% |", global_section)
        self.assertIn("不绑定某个档位", global_section)
        self.assertIn("| 8.000 | 24.000 | — | 24.000 | 24.000 |", output)

    def test_conflicting_page_entry_snapshots_cannot_be_pooled(self):
        left, right = report(), report()
        right["cases"] = {}
        right["pageEntries"]["chat_home"]["first2Seconds"]["raster"]["worstMs"] = 91
        with self.assertRaisesRegex(ValueError, "conflicting global page entry"):
            build_matrix([left, right])

    def test_schema_one_unsupported_cells_or_missing_session_are_rejected(self):
        for mutation in (lambda r: r.update(schema=1), lambda r: r.update(schema=True),
                         lambda r: r.pop("startedAt"),
                         lambda r: r["cases"].update(other_scene={})):
            with self.subTest(mutation=mutation):
                value = report()
                mutation(value)
                with self.assertRaises(ValueError):
                    build_matrix([value])

    def test_cli_writes_lf_and_rejects_schema_one_without_output(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "source.json", Path(directory) / "matrix.md"
            source.write_text(json.dumps(report()), encoding="utf-8")
            self.assertEqual(main([str(source), "-o", str(output)]), 0)
            self.assertNotIn(b"\r", output.read_bytes())
            self.assertIn("有效格 8/8", output.read_text(encoding="utf-8"))
            value = report()
            value["schema"] = 1
            source.write_text(json.dumps(value), encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()) as captured:
                self.assertEqual(main([str(source)]), 2)
            self.assertIn("schema=2", captured.getvalue())

    def test_duplicate_json_keys_are_not_silently_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.json"
            source.write_text('{"schema":2,"schema":1}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                load_report(source)


if __name__ == "__main__":
    unittest.main()
