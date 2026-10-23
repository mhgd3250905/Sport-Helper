"""Synthetic validation fixtures only; no values are phone measurements."""

import copy
import json
from pathlib import Path
import tempfile
import unittest

from fixed_glass_matrix import (
    CONFIGS, ROLES, build_matrix, comparison_issues, expected_policy,
    load_report, render_matrix, scenario_for,
)
from test_raster_matrix import cell, report, window


def fixed_report():
    result = report()
    result["metadata"]["measurementKind"] = "raster_controls_v4"
    result["metadata"]["appBuild"] = "19"
    result["fixedGlassCases"] = {}
    for index, config in enumerate(CONFIGS):
        scenario = scenario_for(config)
        raw = cell("glass_on_stars_on", scenario, average=8.0-index/2)
        raw.update(id=f"{config}__{scenario}", variant=config,
                   fixedGlassConfigurationId=config,
                   pages=["performance_chat" if scenario == "longChatScroll" else "performance_plan_cards"])
        actual = raw["conditions"][0]["condition"]
        actual["scrollCardGlassEnabled"] = False
        policy = expected_policy(config)
        states = {role: policy[role] if role in ("input", "suggestions") else None for role in ROLES}
        warm = config == "baseline_prewarmed"
        actual["fixedGlass"] = {
            "context": "chat" if scenario == "longChatScroll" else "plan",
            "configurationId": config, "policy": policy,
            "presentRoles": ["input", "suggestions"], "roleStates": states,
            "baseBlur": 1.2, "baseSaturation": 1.15,
            "roleMaterials": {role: None if states[role] is None else {
                "trueGlass": states[role],
                "blur": 1.2*policy["blurScale"] if states[role] else 0.0,
                "saturation": (1.15 if policy["saturationEnabled"] else 1.0) if states[role] else 1.0,
            } for role in ROLES},
            "prewarmEnabled": warm, "prewarmStatus": "succeeded" if warm else "disabled",
            "prewarmDurationMs": 12.0 if warm else None,
            "prewarmLogicalWidth": 390.0 if warm else None,
            "prewarmLogicalHeight": 480.0 if warm else None,
            "prewarmPixelRatio": 3.0 if warm else None,
        }
        raw.update(entryCaptureSource="route_push_before_target_build",
                   entryTargetPage=raw["pages"][0], entryFirst2Seconds=window(10),
                   entryFirstVsyncStartUs=1000000,
                   entryCondition=copy.deepcopy(actual),
                   entryConditionGroupCount=1, entryConditionGroupsOverflow=False,
                   entryWindowComplete=True, entryLifecycleInterrupted=False,
                   entryOutOfOrderTimings=False,
                   entryEarlierOutOfOrderFrameCount=0,
                   targetPreviouslyEntered=index > 0, entryOrdinal=index+1)
        result["fixedGlassCases"][raw["id"]] = raw
    return result


class FixedGlassMatrixTests(unittest.TestCase):
    def chat_default_report(self, blur_override=False):
        value = fixed_report()
        value["metadata"].update(theme="light", appearance="light")
        config = "chat_suggestions_static_input_blur_1_2" if blur_override else "chat_suggestions_static"
        raw = copy.deepcopy(value["fixedGlassCases"]["chat_baseline__longChatScroll"])
        raw.update(id=f"{config}__longChatScroll", variant=config, fixedGlassConfigurationId=config)
        actual = raw["conditions"][0]["condition"]
        actual["theme"] = "light"
        fixed = actual["fixedGlass"]
        fixed.update(configurationId=config, policy=expected_policy(config), baseBlur=1.5)
        fixed["roleStates"]["suggestions"] = False
        fixed["roleMaterials"]["suggestions"] = {"trueGlass": False, "blur": 0.0, "saturation": 1.0}
        fixed["roleMaterials"]["input"]["blur"] = 1.2 if blur_override else 1.5
        raw["entryCondition"] = copy.deepcopy(actual)
        value["fixedGlassCases"] = {raw["id"]: raw}
        return value, raw

    def test_chat_default_is_valid_without_changing_input_or_legacy_chat(self):
        value, raw = self.chat_default_report()
        measured = build_matrix(value)[raw["id"]]
        self.assertEqual(measured.issues, [])
        self.assertEqual(measured.entry_issues, [])
        self.assertIn("| chat_suggestions_static | longChatScroll |", render_matrix(value, {raw["id"]: measured}))
        fixed = raw["conditions"][0]["condition"]["fixedGlass"]
        fixed["policy"]["suggestions"] = True
        self.assertIn("实际玻璃策略与实验预设不同", build_matrix(value)[raw["id"]].issues)

    def test_input_only_absolute_blur_control_requires_correct_light_material(self):
        value, raw = self.chat_default_report(blur_override=True)
        measured = build_matrix(value)[raw["id"]]
        self.assertEqual(measured.issues, [])
        self.assertEqual(measured.entry_issues, [])
        fixed = raw["conditions"][0]["condition"]["fixedGlass"]
        fixed["roleMaterials"]["input"]["blur"] = 1.5
        self.assertIn("input 实际材质与策略不匹配", build_matrix(value)[raw["id"]].issues)
        fixed["roleMaterials"]["input"]["blur"] = 1.2
        raw["conditions"][0]["condition"]["theme"] = "dark"
        self.assertIn("输入框模糊对照仅适用于浅色聊天", build_matrix(value)[raw["id"]].issues)

    def test_nine_real_cells_include_na_roles_and_entry_provenance(self):
        value = fixed_report()
        matrix = build_matrix(value)
        self.assertTrue(all(not c.issues and not c.entry_issues for c in matrix.values()))
        output = render_matrix(value, matrix)
        self.assertIn("标准格有效 9/9", output)
        self.assertIn("顶栏：N/A；底栏：N/A", output)
        self.assertIn("不证明所有驱动着色器已编译", output)
        self.assertIn("不能当作冷/暖因果证据", output)
        self.assertIn("base", output)
        for config in CONFIGS[1:-1]:
            self.assertEqual(comparison_issues(matrix["baseline__planCardScroll"],
                matrix[f"{config}__planCardScroll"]), [])

    def test_missing_cells_are_not_zero_and_missing_roles_cannot_be_cases(self):
        value = fixed_report()
        del value["fixedGlassCases"]["input_static__planCardScroll"]
        output = render_matrix(value, build_matrix(value))
        self.assertIn("| input_static | planCardScroll | — | — | — | 待采样 |", output)
        value["fixedGlassCases"]["top_bar_static__planCardScroll"] = {}
        with self.assertRaisesRegex(ValueError, "unsupported"):
            build_matrix(value)

    def test_actual_material_must_match_requested_policy(self):
        value = fixed_report()
        state = value["fixedGlassCases"]["half_blur__planCardScroll"]["conditions"][0]["condition"]["fixedGlass"]
        state["roleMaterials"]["input"]["blur"] = 1.2
        cell_value = build_matrix(value)["half_blur__planCardScroll"]
        self.assertIn("input 实际材质与策略不匹配", cell_value.issues)
        state["roleStates"]["topBar"] = True
        self.assertIn("实际角色状态不匹配，缺席角色必须为 null",
                      build_matrix(value)["half_blur__planCardScroll"].issues)

    def test_no_cross_scene_starfield_or_geometry_comparisons(self):
        value = fixed_report()
        matrix = build_matrix(value)
        self.assertIn("场景不同，拒绝比较", comparison_issues(
            matrix["baseline__planCardScroll"], matrix["chat_baseline__longChatScroll"]))
        actual = value["fixedGlassCases"]["half_blur__planCardScroll"]["conditions"][0]["condition"]
        actual["starfield"] = False
        actual["viewportWidth"] = 400
        matrix = build_matrix(value)
        issues = comparison_issues(matrix["baseline__planCardScroll"], matrix["half_blur__planCardScroll"])
        self.assertIn("星尘不同，拒绝把它混入玻璃对照", issues)
        self.assertIn("actual.viewportWidth 不同", issues)

    def test_failed_prewarm_never_counts_as_successful_warm_cell(self):
        value = fixed_report()
        actual = value["fixedGlassCases"]["baseline_prewarmed__planCardScroll"]["conditions"][0]["condition"]["fixedGlass"]
        actual["prewarmStatus"] = "failed"
        matrix = build_matrix(value)
        self.assertIn("预热未成功，不可用于预热收益对照",
                      matrix["baseline_prewarmed__planCardScroll"].issues)
        self.assertEqual(comparison_issues(matrix["baseline__planCardScroll"],
                                          matrix["baseline_prewarmed__planCardScroll"]), ["含无效格"])

    def test_entry_mixing_is_reported_separately_from_valid_steady_frames(self):
        value = fixed_report()
        raw = value["fixedGlassCases"]["baseline__planCardScroll"]
        raw["entryConditionGroupCount"] = 2
        matrix = build_matrix(value)
        self.assertFalse(matrix[raw["id"]].issues)
        self.assertIn("进入窗口实际条件不唯一或溢出", matrix[raw["id"]].entry_issues)
        output = render_matrix(value, matrix)
        self.assertIn("| baseline | — | disabled | — | False | 1 |", output)

    def test_loader_requires_v4_and_rejects_duplicate_json(self):
        value = fixed_report()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            self.assertEqual(load_report(path), value)
            value["metadata"]["measurementKind"] = "raster_controls_v3"
            path.write_text(json.dumps(value), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "raster_controls_v4"):
                load_report(path)
            path.write_text('{"schema":2,"schema":2}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                load_report(path)


if __name__ == "__main__":
    unittest.main()
