"""Validate fixed-glass experiments without pooling different scenes or states.

Standard library only. Missing/invalid cells remain blank. Device timings must
come from the phone export, never from these synthetic unit-test fixtures.
"""

from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass, field
import json
from pathlib import Path
import sys
from typing import Any

from raster_matrix import (
    ACTUAL_DIMENSIONS, Cell, _number,
    _text, _unique_object, _validate_cell, _window_issues, pair_issues,
    validate_report,
)


CONFIGS = (
    "baseline", "input_static", "suggestions_static", "no_saturation",
    "half_blur", "no_saturation_half_blur", "all_static",
    "baseline_prewarmed", "chat_baseline",
)
CHAT_DEFAULT_CONFIGS = (
    "chat_suggestions_static", "chat_suggestions_static_input_blur_1_2",
)
ALL_CONFIGS = (*CONFIGS, *CHAT_DEFAULT_CONFIGS, "custom_plan", "custom_chat")
ROLES = ("topBar", "bottomBar", "input", "suggestions")
BASE_POLICY = dict.fromkeys(ROLES, True) | {"saturationEnabled": True, "blurScale": 1.0}


def expected_policy(config: str) -> dict[str, Any] | None:
    result = BASE_POLICY.copy()
    if config.startswith("custom_"):
        return None
    if config == "input_static":
        result["input"] = False
    elif config == "suggestions_static" or config in CHAT_DEFAULT_CONFIGS:
        result["suggestions"] = False
    if config == "chat_suggestions_static_input_blur_1_2":
        result["inputBlur"] = 1.2
    elif config == "all_static":
        result.update(dict.fromkeys(ROLES, False))
    if config in ("no_saturation", "no_saturation_half_blur"):
        result["saturationEnabled"] = False
    if config in ("half_blur", "no_saturation_half_blur"):
        result["blurScale"] = .5
    return result


def scenario_for(config: str) -> str:
    return "longChatScroll" if config in ("chat_baseline", *CHAT_DEFAULT_CONFIGS, "custom_chat") else "planCardScroll"


@dataclass
class FixedCell(Cell):
    entry_issues: list[str] = field(default_factory=list)


def _validate_fixed(raw: Any, key: str, metadata: dict[str, Any]) -> FixedCell:
    config, scenario = key.split("__")
    # Reuse all schema-2 thread/window/device checks. Only the legacy global
    # matrix's identifier check is adapted; actual conditions remain untouched.
    candidate = copy.deepcopy(raw) if isinstance(raw, dict) else {}
    groups = candidate.get("conditions", [])
    condition = groups[0].get("condition", {}) if len(groups) == 1 and isinstance(groups[0], dict) else {}
    legacy_variant = "glass_on_stars_" + ("on" if condition.get("starfield") is True else "off")
    candidate["id"] = f"{legacy_variant}__{scenario}"
    candidate["variant"] = legacy_variant
    checked = _validate_cell(candidate, candidate["id"], metadata)
    cell = FixedCell(raw if isinstance(raw, dict) else {}, metadata, checked.issues)
    if not isinstance(raw, dict):
        return cell
    for name, expected in (("id", key), ("variant", config), ("scenario", scenario),
                           ("fixedGlassConfigurationId", config)):
        if raw.get(name) != expected:
            cell.issues.append(f"{name} 与配置标识不一致")
    if scenario != scenario_for(config):
        cell.issues.append("配置与固定场景不匹配")
    actual = cell.condition
    fixed = actual.get("fixedGlass")
    if not isinstance(fixed, dict):
        cell.issues.append("缺少每帧实际 fixedGlass 条件")
        return cell
    plan = scenario == "planCardScroll"
    if fixed.get("configurationId") != config or fixed.get("context") != ("plan" if plan else "chat"):
        cell.issues.append("实际配置或计划/聊天作用域不匹配")
    policy = fixed.get("policy")
    expected = expected_policy(config)
    policy_keys = set(BASE_POLICY) | ({"inputBlur"} if isinstance(policy, dict) and "inputBlur" in policy else set())
    if not isinstance(policy, dict) or set(policy) != policy_keys:
        cell.issues.append("玻璃策略字段不完整")
        return cell
    if any(type(policy.get(role)) is not bool for role in (*ROLES, "saturationEnabled")) or policy.get("blurScale") not in (1, .5):
        cell.issues.append("玻璃策略字段无效")
    if "inputBlur" in policy and (not _number(policy["inputBlur"]) or policy["inputBlur"] != 1.2):
        cell.issues.append("输入框模糊对照必须为 1.2")
    if expected is not None and policy != expected:
        cell.issues.append("实际玻璃策略与实验预设不同")
    if not plan and config not in CHAT_DEFAULT_CONFIGS and policy != BASE_POLICY:
        cell.issues.append("聊天受到计划实验策略影响")
    if config == "chat_suggestions_static_input_blur_1_2" and actual.get("theme") != "light":
        cell.issues.append("输入框模糊对照仅适用于浅色聊天")
    if actual.get("glassEnabled") is not True or actual.get("scrollCardGlassEnabled") is not False:
        cell.issues.append("需要全局玻璃开、列表卡片静态")
    present = fixed.get("presentRoles")
    if present != ["input", "suggestions"]:
        cell.issues.append("实际角色清单与当前承载页不一致")
    expected_states = {role: policy[role] if role in ("input", "suggestions") else None for role in ROLES}
    if fixed.get("roleStates") != expected_states:
        cell.issues.append("实际角色状态不匹配，缺席角色必须为 null")
    base_blur, base_sat = fixed.get("baseBlur"), fixed.get("baseSaturation")
    if not _number(base_blur) or not _number(base_sat) or base_blur <= 0 or base_sat <= 0:
        cell.issues.append("实际基础模糊/饱和度未记录")
    else:
        materials = fixed.get("roleMaterials", {})
        for role in ROLES:
            expected_material = None if expected_states[role] is None else {
                "trueGlass": expected_states[role],
                "blur": (policy.get("inputBlur", base_blur * policy["blurScale"])
                         if role == "input" else base_blur * policy["blurScale"]) if expected_states[role] else 0.0,
                "saturation": (base_sat if policy["saturationEnabled"] else 1.0) if expected_states[role] else 1.0,
            }
            if not isinstance(materials, dict) or materials.get(role, "missing") != expected_material:
                cell.issues.append(f"{role} 实际材质与策略不匹配")
    enabled, status = fixed.get("prewarmEnabled"), fixed.get("prewarmStatus")
    expected_enabled = config == "baseline_prewarmed"
    if type(enabled) is not bool or (not config.startswith("custom_") and enabled != expected_enabled):
        cell.issues.append("预热开关与配置不匹配")
    if enabled:
        if status not in ("succeeded", "unsupported", "failed") or not _number(fixed.get("prewarmDurationMs")):
            cell.issues.append("预热没有完成的实际尝试记录")
        if config == "baseline_prewarmed" and status != "succeeded":
            cell.issues.append("预热未成功，不可用于预热收益对照")
        if status == "succeeded" and any(not _number(fixed.get(k)) or fixed[k] <= 0 for k in
                                         ("prewarmLogicalWidth", "prewarmLogicalHeight", "prewarmPixelRatio")):
            cell.issues.append("实际预热绘制尺寸或像素比缺失")
    elif status != "disabled":
        cell.issues.append("未预热格的状态必须为 disabled")
    entry = raw.get("entryFirst2Seconds")
    cell.entry_issues.extend(_window_issues(entry, "entryFirst2Seconds"))
    if isinstance(entry, dict) and not entry.get("frameCount"):
        cell.entry_issues.append("没有目标页首次进入帧")
    if raw.get("entryCaptureSource") != "route_push_before_target_build":
        cell.entry_issues.append("首次进入记录未在推送目标页前申请")
    if raw.get("entryTargetPage") not in raw.get("pages", []):
        cell.entry_issues.append("首次进入目标页与滚动页不同")
    if raw.get("entryConditionGroupCount") != 1 or raw.get("entryConditionGroupsOverflow") is not False:
        cell.entry_issues.append("进入窗口实际条件不唯一或溢出")
    if raw.get("entryEarlierOutOfOrderFrameCount") != 0:
        cell.entry_issues.append("进入窗口帧顺序异常")
    if raw.get("entryWindowComplete") is not True:
        cell.entry_issues.append("进入窗口未完整观察至 2 秒")
    if raw.get("entryLifecycleInterrupted") is not False:
        cell.entry_issues.append("进入窗口曾切后台或状态未知")
    if raw.get("entryOutOfOrderTimings") is not False:
        cell.entry_issues.append("进入窗口时序异常或未知")
    if type(raw.get("targetPreviouslyEntered")) is not bool or type(raw.get("entryOrdinal")) is not int or raw["entryOrdinal"] < 1:
        cell.entry_issues.append("未记录目标页历史访问状态")
    entry_condition = raw.get("entryCondition")
    if not isinstance(entry_condition, dict) or entry_condition.get("fixedGlass") != fixed:
        cell.entry_issues.append("首次进入玻璃/预热条件与该格不一致")
    if isinstance(entry_condition, dict):
        for name in ("renderer", "rendererBackend", "refreshRateHz", "theme", *ACTUAL_DIMENSIONS):
            if entry_condition.get(name) != actual.get(name):
                cell.entry_issues.append(f"首次进入 {name} 条件不同")
    return cell


def load_report(path: Path) -> dict[str, Any]:
    report = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=_unique_object)
    validate_report(report)
    if report.get("metadata", {}).get("measurementKind") != "raster_controls_v4":
        raise ValueError("fixed-glass experiments require raster_controls_v4")
    if not isinstance(report.get("fixedGlassCases"), dict):
        raise ValueError("fixedGlassCases must be a JSON object")
    allowed = {f"{config}__{scenario_for(config)}" for config in ALL_CONFIGS}
    if set(report["fixedGlassCases"]) - allowed:
        raise ValueError("unsupported fixed-glass cell identifiers")
    return report


def build_matrix(report: dict[str, Any]) -> dict[str, FixedCell]:
    validate_report(report)
    if report.get("metadata", {}).get("measurementKind") != "raster_controls_v4":
        raise ValueError("fixed-glass experiments require raster_controls_v4")
    allowed = {f"{config}__{scenario_for(config)}" for config in ALL_CONFIGS}
    if not isinstance(report.get("fixedGlassCases"), dict) or set(report["fixedGlassCases"]) - allowed:
        raise ValueError("unsupported fixed-glass cells")
    return {key: _validate_fixed(raw, key, report.get("metadata", {}))
            for key, raw in report["fixedGlassCases"].items()}


def comparison_issues(left: FixedCell | None, right: FixedCell | None) -> list[str]:
    # Legacy glass/star comparisons forbid policy changes; those are the
    # deliberate independent variables in this separate experiment matrix.
    issues = [issue for issue in pair_issues(left, right)
              if not issue.startswith("actual.fixedGlass.")]
    if left is None or right is None or left.issues or right.issues:
        return issues
    if left.condition.get("starfield") != right.condition.get("starfield"):
        issues.append("星尘不同，拒绝把它混入玻璃对照")
    left_fixed, right_fixed = left.condition["fixedGlass"], right.condition["fixedGlass"]
    for key in ("context", "presentRoles", "baseBlur", "baseSaturation"):
        if left_fixed.get(key) != right_fixed.get(key):
            issues.append(f"fixedGlass.{key} 不同")
    # Prewarming is the sole variable only for the dedicated warm/cold pair.
    is_prewarm_pair = {left.case["variant"], right.case["variant"]} == {"baseline", "baseline_prewarmed"}
    if not is_prewarm_pair:
        for key in ("prewarmEnabled", "prewarmStatus"):
            if left_fixed.get(key) != right_fixed.get(key):
                issues.append(f"fixedGlass.{key} 不同")
    elif right_fixed.get("prewarmStatus") != "succeeded" and left_fixed.get("prewarmStatus") != "succeeded":
        issues.append("没有实际预热成功记录")
    return issues


def _metric(cell: FixedCell | None, window: str, metric: str) -> str:
    if cell is None or cell.issues or (window == "entryFirst2Seconds" and cell.entry_issues):
        return "—"
    value = cell.case.get(window, {}).get("raster", {}).get(metric)
    if not _number(value):
        return "—"
    return f"{value:.3%}" if metric == "overBudgetRatio" else f"{value:.3f}"


def render_matrix(report: dict[str, Any], cells: dict[str, FixedCell]) -> str:
    valid = sum(not cells[f"{c}__{scenario_for(c)}"].issues for c in CONFIGS if f"{c}__{scenario_for(c)}" in cells)
    displayed_configs = (*CONFIGS, *(c for c in ALL_CONFIGS if c not in CONFIGS and f"{c}__{scenario_for(c)}" in cells))
    meta = report.get("metadata", {})
    lines = ["# SmartFit 固定玻璃拆分实验", "", f"轮次 `{_text(report.get('startedAt'))}`；标准格有效 {valid}/9。", "",
             "；".join(f"{k}={_text(meta.get(k))}" for k in ("deviceModel", "systemVersion", "appSource", "theme", "renderer", "rendererBackend")), "",
             "只做同场景、同设备/刷新率/主题/星尘/列表卡片模式比较；不合并帧或百分位。缺格和无效格为 —，不作 0。",
             "顶栏：N/A；底栏：N/A。当前承载页实际固定玻璃只有输入框和建议条，不能生成不存在元素的假对照。",
             "预热 succeeded 仅表示完成了离屏绘制尝试，不证明所有驱动着色器已编译。", "",
             "| 配置 | 场景 | Raster 平均 ms | P99 ms | 超预算比例 | 有效性 |",
             "| --- | --- | ---: | ---: | ---: | --- |"]
    for config in displayed_configs:
        cell = cells.get(f"{config}__{scenario_for(config)}")
        status = "待采样" if cell is None else ("有效" if not cell.issues else "无效：" + "；".join(cell.issues))
        values = " | ".join(_metric(cell, "steadyState", m) for m in ("averageMs", "p99Ms", "overBudgetRatio"))
        lines.append(f"| {config} | {scenario_for(config)} | {values} | {_text(status)} |")
    lines.extend(["", "## 仅计划卡同场景对照 baseline", "", "| 配置 | 平均变化 ms | P99 变化 ms | 超预算变化百分点 | 可比性 |", "| --- | ---: | ---: | ---: | --- |"])
    baseline = cells.get("baseline__planCardScroll")
    for config in CONFIGS[1:-1]:
        cell = cells.get(f"{config}__planCardScroll")
        issues = comparison_issues(baseline, cell)
        if issues:
            lines.append(f"| {config} | — | — | — | {_text('；'.join(issues))} |")
        else:
            left = baseline.case["steadyState"]["raster"]
            right = cell.case["steadyState"]["raster"]
            lines.append(f"| {config} | {right['averageMs']-left['averageMs']:+.3f} | {right['p99Ms']-left['p99Ms']:+.3f} | {(right['overBudgetRatio']-left['overBudgetRatio'])*100:+.3f} | 可比 |")
    lines.extend(["", "## 每配置进入目标页前 2 秒（独立于滚动稳态）", "",
                  "同一轮后跑的预热格已经受前面页面访问影响，不能当作冷/暖因果证据。冷/暖首次进入需分别重启 App 后首先跑 baseline / baseline_prewarmed，各自导出；本工具不跨启动合并帧或百分位。报告重置不会清除进程内页面访问历史。", "",
                  "本进程首次进入目标页也不保证 GPU 全冷：前页可能已经绘制共享组件，报告没有 Timeline 着色器编译事件。", "",
                  "| 配置 | 最差 Raster ms | 预热实际状态 | 预热绘制尺寸@像素比 | 本进程此前进过目标页 | entry 序号 | entry 有效性 |", "| --- | ---: | --- | --- | --- | ---: | --- |"])
    for config in displayed_configs:
        cell = cells.get(f"{config}__{scenario_for(config)}")
        fixed = cell.condition.get("fixedGlass", {}) if cell else {}
        status = "待采样" if cell is None else ("有效" if not cell.entry_issues else "；".join(cell.entry_issues))
        prior = "—" if cell is None else cell.case.get("targetPreviouslyEntered", "—")
        ordinal = "—" if cell is None else cell.case.get("entryOrdinal", "—")
        geometry = "—" if fixed.get("prewarmLogicalWidth") is None else (
            f"{fixed.get('prewarmLogicalWidth')}×{fixed.get('prewarmLogicalHeight')}@{fixed.get('prewarmPixelRatio')}")
        lines.append(f"| {config} | {_metric(cell, 'entryFirst2Seconds', 'worstMs')} | {_text(fixed.get('prewarmStatus', '—'))} | {_text(geometry)} | {_text(prior)} | {_text(ordinal)} | {_text(status)} |")
    lines.extend(["", "## 每格实际材质", "", "| 配置 | 输入框 | 建议条 | 模糊 sigma | 饱和度 |", "| --- | --- | --- | ---: | ---: |"])
    for config in displayed_configs:
        cell = cells.get(f"{config}__{scenario_for(config)}")
        fixed = cell.condition.get("fixedGlass", {}) if cell and not cell.issues else {}
        states = fixed.get("roleStates", {})
        materials = fixed.get("roleMaterials", {})
        real = next((m for m in materials.values() if isinstance(m, dict) and m.get("trueGlass")), {})
        mode = lambda role: "—" if role not in states else ("真玻璃" if states[role] else "静态仿玻璃")
        lines.append(f"| {config} | {mode('input')} | {mode('suggestions')} | {_text(real.get('blur', '—'))} | {_text(real.get('saturation', '—'))} |")
    lines.extend(["", "绝对性能目标只以真机数据判断。P99 是直方图上界估计；超预算比例表示引擎 Raster 耗时超过 1000/Hz 的比例，并非屏幕实际掉帧率。",
                  "最终默认配置仍待本表实测结果确认；进入尖峰单独记录，不阻断稳态方案选择。", ""])
    attempts = report.get("fixedGlassEntries", {})
    if isinstance(attempts, dict):
        incomplete = [config for config, attempt in attempts.items()
                      if isinstance(attempt, dict) and attempt.get("scriptStarted") is not True]
        if incomplete:
            lines.extend(["未进入滚动采样的 entry 尝试（不借用上一次成绩）：" + "、".join(map(_text, incomplete)) + "。", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args(argv)
    try:
        report = load_report(args.report)
        result = render_matrix(report, build_matrix(report))
        if args.output:
            args.output.write_text(result, encoding="utf-8", newline="\n")
        else:
            print(result)
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"fixed-glass report rejected: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
