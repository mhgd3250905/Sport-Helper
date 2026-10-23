"""Unit fixtures are synthetic; no output is a measured performance report."""

import copy
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from compare_reports import condition_issues, load_report, main, render_comparison, validate_report


def group(count=100, average=8.0, over=10, union=15, rates=None):
    thread = {"averageMs": average if count else None,
              "p90Ms": 12.0 if count else None,
              "p99Ms": 20.0 if count else None,
              "worstMs": 24.0 if count else None,
              "overBudgetFrames": over if count else 0}
    return {"frameCount": count, "uiBuild": dict(thread), "raster": dict(thread),
            "eitherThreadOverBudgetFrames": union if count else 0,
            "estimatedMissedVsyncs": union if count else 0,
            "refreshRatesHz": ([60.0] if count else []) if rates is None else rates,
            "refreshRatesTruncated": False}


def report():
    return {"schema": 1, "reportType": "frame_performance", "app": "smartfit",
            "metadata": {"appVersion": "unit-fixture-before", "appBuild": "15",
                         "appSource": "fixture-source", "appBaseCommit": "fixture-base",
                         "sdkRef": "fixture-sdk", "measurementKind": "baseline",
                         "deviceModel": "fixture-device", "deviceManufacturer": "fixture-maker",
                         "systemVersion": "16", "deviceApiLevel": 36,
                         "platform": "android", "isEmulator": False, "buildMode": "profile",
                         "flavor": "internal", "renderer": "impeller",
                         "metadataStatus": "available", "refreshRateSource": "flutter_display",
                         "theme": "dark", "appearance": "system", "starfield": True,
                         "glassQuality": "standard"},
            "recordedFrameCount": 100, "unattributedFrameCount": 0,
            "conditionChangesDuringCapture": 0,
            "total": group(), "scenarios": {"actionListScroll": group()}}


class ComparisonTests(unittest.TestCase):
    def test_versions_and_source_may_differ_but_base_and_sdk_must_match(self):
        left, right = report(), report()
        right["metadata"].update(appVersion="unit-fixture-after", appBuild="16",
                                 appSource="fixture-candidate", measurementKind="candidate")
        self.assertEqual(condition_issues(left, right), [])
        right["metadata"]["sdkRef"] = "changed-sdk"
        self.assertTrue(any("sdkRef 不同" in item for item in condition_issues(left, right)))
        right["metadata"]["appBaseCommit"] = "changed-base"
        self.assertTrue(any("appBaseCommit 不同" in item for item in condition_issues(left, right)))

    def test_device_render_and_visual_changes_are_not_directly_comparable(self):
        for key, changed in (("deviceModel", "other"), ("systemVersion", "17"),
                             ("buildMode", "release"), ("renderer", "skia"),
                             ("theme", "light"), ("starfield", False),
                             ("glassQuality", "minimal"), ("isEmulator", True)):
            with self.subTest(key=key):
                left, right = report(), report()
                right["metadata"][key] = changed
                output = render_comparison(left, right)
                self.assertIn("不可直接比较", output)
                self.assertIn(f"{key} 不同", output)

    def test_missing_and_unknown_conditions_are_not_assumed_equal(self):
        left, right = report(), report()
        for item in (left, right):
            del item["metadata"]["sdkRef"]
            item["metadata"]["renderer"] = "unknown"
        output = render_comparison(left, right)
        self.assertIn("sdkRef 缺失或未知", output)
        self.assertIn("renderer 缺失或未知", output)

    def test_refresh_rates_compare_as_sets_and_reject_mixed_distribution(self):
        left, right = report(), report()
        right["total"]["refreshRatesHz"] = [120]
        self.assertTrue(any("refreshRatesHz 不同" in item for item in condition_issues(left, right)))
        for item in (left, right):
            item["total"]["refreshRatesHz"] = [120, 60]
        issues = condition_issues(left, right)
        self.assertFalse(any("refreshRatesHz 不同" in item for item in issues))
        self.assertTrue(any("多档刷新率" in item for item in issues))
        right["metadata"]["refreshRateSource"] = "assumed"
        self.assertTrue(any("刷新率来源" in item for item in condition_issues(left, right)))

    def test_both_display_sources_are_supported(self):
        left, right = report(), report()
        right["metadata"]["refreshRateSource"] = "android_display"
        self.assertEqual(condition_issues(left, right), [])

    def test_matching_final_conditions_cannot_hide_capture_changes(self):
        left, right = report(), report()
        right["conditionChangesDuringCapture"] = 2
        output = render_comparison(left, right)
        self.assertIn("修改后采集期间条件变化 2 次", output)
        self.assertIn("最终条件相同也不适合直接归因", output)
        self.assertIn("conditionChangesDuringCapture=2", output)
        with self.assertRaises(ValueError):
            validate_report({**left, "conditionChangesDuringCapture": -1})

    def test_unverified_renderer_does_not_count_as_same_backend(self):
        left, right = report(), report()
        for item in (left, right):
            item["metadata"]["renderer"] = "unverified"
        self.assertTrue(any("renderer 缺失或未知" in item for item in condition_issues(left, right)))
        self.assertIn("全局条件：不可直接比较", render_comparison(left, right))

    def test_missing_scenes_have_no_fabricated_zero_statistics(self):
        output = render_comparison(report(), report())
        section = output.split("### 筛选切换", 1)[1].split("###", 1)[0]
        self.assertIn("基线：未采集（缺少场景）", section)
        self.assertIn("| UI build | 平均 ms | 未采集 | 未采集 |", section)
        self.assertIn("| 任一线程超预算 union | 未采集 | 未采集 |", section)
        self.assertNotIn("0.000", section)
        self.assertEqual(output.count("### "), 7)

    def test_empty_and_unattributed_samples_warn_and_never_show_improvement(self):
        left, right = report(), report()
        left.update(recordedFrameCount=0, total=group(0), unattributedFrameCount=12)
        left["scenarios"]["actionListScroll"] = group(0)
        output = render_comparison(left, right)
        self.assertIn("基线无帧样本", output)
        self.assertIn("存在未归因帧", output)
        self.assertIn("frameCount=0，无帧样本", output)
        self.assertIn("| UI build | 平均 ms | 未采集 | 8.000 | 不适用（缺样本） |", output)

    def test_duration_changes_and_union_use_correct_denominators(self):
        left, right = report(), report()
        right.update(recordedFrameCount=200, total=group(200, average=6, over=10, union=15))
        right["scenarios"]["actionListScroll"] = group(200, average=6, over=10, union=15)
        output = render_comparison(left, right)
        self.assertIn("| UI build | 平均 ms | 8.000 | 6.000 | -25.0% |", output)
        self.assertIn("| UI build | 超预算帧数 / 占比 | 10（10.00%） | 10（5.00%） |", output)
        self.assertIn("计数 +0.0%；占比 -5.00 个百分点", output)
        self.assertIn("| 任一线程超预算 union | 15（15.00%） | 15（7.50%） |", output)
        self.assertIn("占比 -7.50 个百分点", output)
        self.assertIn("| frameCount | 100 | 200 | +100.0% |", output)

    def test_zero_baseline_change_never_divides_by_zero(self):
        left, right = report(), report()
        left["scenarios"]["actionListScroll"] = group(over=0, union=0)
        output = render_comparison(left, right)
        self.assertIn("不适用（基线为 0）", output)

    def test_verify_is_optional_and_never_aggregates_percentiles(self):
        left, right = report(), report()
        for item in (left, right):
            item["scenarios"] = {"mediaDownloadScroll": group(50, over=5, union=8),
                                 "mediaVerifyScroll": group(50, average=4, over=0, union=0)}
        output = render_comparison(left, right)
        self.assertIn("### 附加：独立校验标记", output)
        self.assertIn("不自动补数", output)
        self.assertIn("不与下载场景合并均值或百分位", output)
        self.assertNotIn("6.000", output)

    def test_emulator_is_labelled_as_relative_only(self):
        left, right = report(), report()
        left["metadata"]["isEmulator"] = right["metadata"]["isEmulator"] = True
        output = render_comparison(left, right)
        self.assertIn("绝对值不代表真机", output)
        self.assertEqual(condition_issues(left, right), [])

    def test_invalid_schema_nan_counts_and_union_are_rejected(self):
        for mutation in (
            lambda r: r.update(schema=True),
            lambda r: r.update(reportType="runtime_log"),
            lambda r: r["total"]["uiBuild"].update(averageMs=float("nan")),
            lambda r: r["total"].update(frameCount=-1),
            lambda r: r["total"].update(eitherThreadOverBudgetFrames=25),
            lambda r: r["total"]["uiBuild"].update(overBudgetFrames=101),
            lambda r: r.update(recordedFrameCount=101),
            lambda r: r["scenarios"].update(filterSwitch=group()),
        ):
            with self.subTest(mutation=mutation):
                value = report()
                mutation(value)
                with self.assertRaises(ValueError):
                    validate_report(value)

    def test_cli_writes_utf8_markdown_and_preserves_source_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before, after, output = root / "before.json", root / "after.json", root / "out.md"
            before.write_text(json.dumps(report()), encoding="utf-8-sig")
            after.write_text(json.dumps(report()), encoding="utf-8")
            original = before.read_bytes()
            self.assertEqual(load_report(before)["schema"], 1)
            self.assertEqual(main([str(before), str(after), "-o", str(output)]), 0)
            self.assertIn("# SmartFit 帧报告对比", output.read_text(encoding="utf-8"))
            self.assertEqual(before.read_bytes(), original)
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(main([str(before), str(after), "-o", str(before)]), 2)
            self.assertIn("must not overwrite", errors.getvalue())
            self.assertEqual(before.read_bytes(), original)

    def test_bad_json_is_a_clear_cli_error_without_creating_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bad, good, out = root / "bad.json", root / "good.json", root / "out.md"
            bad.write_text("{not-json", encoding="utf-8")
            good.write_text(json.dumps(report()), encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                self.assertEqual(main([str(bad), str(good), "-o", str(out)]), 2)
            self.assertIn("bad.json", errors.getvalue())
            self.assertFalse(out.exists())

    def test_metadata_cannot_break_markdown_table_or_inject_html(self):
        value = copy.deepcopy(report())
        value["metadata"]["appVersion"] = "<script>|fake\nrow"
        output = render_comparison(value, report())
        self.assertIn("&lt;script&gt;&#124;fake row", output)
        self.assertNotIn("<script>", output)


if __name__ == "__main__":
    unittest.main()
