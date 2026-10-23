"""Render the schema-2 Raster control matrix without pooling measurements.

Usage: python tools/performance/raster_matrix.py report.json [part2.json] [-o matrix.md]
Multiple files must contain disjoint cells from the same capture session/source.
Schema-1 baseline reports are deliberately unsupported. Standard library only.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import html
import json
import math
from pathlib import Path
import sys
from typing import Any


VARIANTS = (
    "glass_on_stars_on", "glass_on_stars_off",
    "glass_off_stars_on", "glass_off_stars_off",
)
SCENARIOS = ("longChatScroll", "planCardScroll")
WINDOWS = ("allFrames", "warmupFirst2Seconds", "steadyState", "firstPageEntryFirst2Seconds")
METRICS = ("averageMs", "p90Ms", "p99Ms", "worstMs", "overBudgetRatio")
IDENTITY_KEYS = (
    "deviceModel", "deviceManufacturer", "systemVersion", "deviceApiLevel",
    "platform", "isEmulator", "appVersion", "appBuild", "appBuildNumber",
    "appSource", "appBaseCommit", "sdkRef", "buildMode", "flavor",
    "measurementKind", "metadataStatus", "theme", "appearance", "refreshRateSource",
    "renderer", "rendererBackend", "rendererVerified",
)
DIMENSION_KEYS = (
    "physicalWidth", "physicalHeight", "logicalWidth", "logicalHeight",
    "viewportWidth", "viewportHeight", "devicePixelRatio", "textScaleFactor",
)
ACTUAL_DIMENSIONS = ("viewportWidth", "viewportHeight", "devicePixelRatio", "textScale")
UNKNOWN = {"", "unknown", "unavailable", "unverified", "unspecified", "n/a", "working_tree"}
PAIRS = (
    ("关闭星尘（玻璃开）", VARIANTS[0], VARIANTS[1]),
    ("关闭星尘（玻璃关）", VARIANTS[2], VARIANTS[3]),
    ("关闭玻璃（星尘开）", VARIANTS[0], VARIANTS[2]),
    ("关闭玻璃（星尘关）", VARIANTS[1], VARIANTS[3]),
)


def _known(value: Any) -> bool:
    return type(value) in (str, int, float, bool) and not (
        isinstance(value, str) and value.strip().lower() in UNKNOWN
    ) and (type(value) not in (int, float) or math.isfinite(value))


def _number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def _integer(value: Any) -> bool:
    return type(value) is int and value >= 0


def _text(value: Any) -> str:
    return html.escape(str(value)).replace("|", "&#124;").replace("\r", " ").replace("\n", " ")


def _unique_object(items: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_report(report: Any) -> dict[str, Any]:
    if not isinstance(report, dict) or type(report.get("schema")) is not int or report["schema"] != 2:
        raise ValueError("only schema=2 is supported; schema-1 baselines cannot fill matrix cells")
    if report.get("reportType") != "frame_performance" or report.get("app") != "smartfit":
        raise ValueError("expected a SmartFit frame_performance report")
    if not isinstance(report.get("metadata"), dict) or not isinstance(report.get("cases"), dict):
        raise ValueError("metadata and cases must be JSON objects")
    if "pageEntries" in report and not isinstance(report["pageEntries"], dict):
        raise ValueError("pageEntries must be a JSON object")
    try:
        started = datetime.fromisoformat(report.get("startedAt", "").replace("Z", "+00:00"))
        if started.tzinfo is None:
            raise ValueError("timezone required")
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("startedAt must be an ISO timestamp with timezone") from error
    expected = {f"{variant}__{scenario}" for variant in VARIANTS for scenario in SCENARIOS}
    if set(report["cases"]) - expected:
        raise ValueError("cases contains unsupported cell identifiers")
    return report


def load_report(path: Path) -> dict[str, Any]:
    try:
        return validate_report(json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=_unique_object))
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"{path.name}: {error}") from error


def _metadata_issues(metadata: dict[str, Any]) -> list[str]:
    issues = [f"metadata.{key} 缺失或未知" for key in IDENTITY_KEYS if not _known(metadata.get(key))]
    if metadata.get("metadataStatus") != "available":
        issues.append("设备元数据不可用")
    if metadata.get("buildMode") not in ("profile", "release"):
        issues.append("需要 profile/release 构建")
    if metadata.get("flavor") != "internal":
        issues.append("需要 internal 内测包")
    if metadata.get("rendererVerified") is not True:
        issues.append("实际 renderer 未验证")
    if str(metadata.get("renderer", "")).lower() not in ("impeller", "skia"):
        issues.append("实际 renderer 未知")
    if not _known(metadata.get("rendererSource")):
        issues.append("实际 renderer 缺少证据来源")
    if metadata.get("refreshRateSource") not in ("android_display", "flutter_display"):
        issues.append("刷新率来源未确认")
    if type(metadata.get("isEmulator")) is not bool:
        issues.append("isEmulator 未确认")
    for key in DIMENSION_KEYS:
        if key in metadata and (not _number(metadata[key]) or metadata[key] <= 0):
            issues.append(f"metadata.{key} 无效")
    return issues


def _window_issues(window: Any, name: str) -> list[str]:
    if not isinstance(window, dict) or not _integer(window.get("frameCount")):
        return [f"{name}.frameCount 缺失或无效"]
    issues = []
    count = window["frameCount"]
    raster = window.get("raster")
    if not isinstance(raster, dict):
        return [f"{name}.raster 缺失"]
    for metric in METRICS:
        value = raster.get(metric)
        if count and not _number(value):
            issues.append(f"{name}.raster.{metric} 缺失或无效")
        elif not count and value is not None:
            issues.append(f"{name} 无帧时 {metric} 必须为 null")
    over = raster.get("overBudgetFrames")
    if not _integer(over) or over > count:
        issues.append(f"{name}.raster.overBudgetFrames 无效")
    ratio = raster.get("overBudgetRatio")
    if count and _number(ratio) and (ratio > 1 or (_integer(over) and not math.isclose(ratio, over / count, abs_tol=1e-9))):
        issues.append(f"{name} 超预算比例与计数不一致")
    if count and all(_number(raster.get(key)) for key in METRICS):
        if not raster["p90Ms"] <= raster["p99Ms"] <= raster["worstMs"] or raster["averageMs"] > raster["worstMs"]:
            issues.append(f"{name} 耗时分布不一致")
    rates = window.get("refreshRatesHz")
    if not isinstance(rates, list) or (count and (len(rates) != 1 or not _number(rates[0]) or not 10 <= rates[0] <= 1000)):
        issues.append(f"{name} 缺少单一有效刷新率")
    elif not count and rates:
        issues.append(f"{name} 无帧时刷新率集合必须为空")
    if window.get("refreshRatesTruncated") is not False:
        issues.append(f"{name} 刷新率截断状态不可信")
    return issues


@dataclass
class Cell:
    case: dict[str, Any]
    metadata: dict[str, Any]
    issues: list[str]

    @property
    def condition(self) -> dict[str, Any]:
        groups = self.case.get("conditions")
        value = groups[0].get("condition", {}) if isinstance(groups, list) and len(groups) == 1 and isinstance(groups[0], dict) else {}
        return value if isinstance(value, dict) else {}


@dataclass
class Matrix:
    started_at: str
    metadata: dict[str, Any]
    cells: dict[str, Cell]
    page_entries: dict[str, Any]


def _validate_cell(raw: Any, key: str, metadata: dict[str, Any]) -> Cell:
    issues = _metadata_issues(metadata)
    if not isinstance(raw, dict):
        return Cell({}, metadata, issues + ["case 不是对象"])
    variant, scenario = key.split("__")
    for field, expected in (("id", key), ("variant", variant), ("scenario", scenario)):
        if raw.get(field) != expected:
            issues.append(f"{field} 与格子标识不一致")
    if raw.get("comparisonReady") is not True or raw.get("comparisonIssues") != []:
        issues.append("记录器未确认本格有效")
    if isinstance(raw.get("comparisonIssues"), list):
        issues.extend(f"recorder: {item}" for item in raw["comparisonIssues"])
    if raw.get("completed") is not True:
        issues.append("本格未完成")
    duration = raw.get("observedDurationSeconds")
    if not _number(duration) or duration < 30:
        issues.append("观测帧跨度不足 30 秒")
    if not _known(raw.get("fixtureId")):
        issues.append("fixtureId 缺失或未知")
    count = raw.get("messageCount")
    if not _integer(count) or (scenario == "longChatScroll" and count < 60):
        issues.append("消息数无效或长聊天少于 60 条")
    if raw.get("overflowConditionFrameCount") != 0:
        issues.append("实际条件组溢出或未记录")
    pages = raw.get("pages")
    if not isinstance(pages, list) or len(pages) != 1 or not _known(pages[0]):
        issues.append("本格缺少单一页面")
    for window in WINDOWS:
        issues.extend(_window_issues(raw.get(window), window))
    if all(isinstance(raw.get(w), dict) and _integer(raw[w].get("frameCount")) for w in WINDOWS):
        if raw["allFrames"]["frameCount"] != raw["warmupFirst2Seconds"]["frameCount"] + raw["steadyState"]["frameCount"]:
            issues.append("前 2 秒与稳态帧数之和不等于总帧数")
        if raw["steadyState"]["frameCount"] == 0:
            issues.append("没有稳态帧")
        if raw["firstPageEntryFirst2Seconds"]["frameCount"] > raw["allFrames"]["frameCount"]:
            issues.append("首次进入窗口帧数超过总帧数")
    cell = Cell(raw, metadata, issues)
    condition = cell.condition
    if not condition:
        issues.append("需要恰好一组实际渲染条件")
        return cell
    for key_name in ("glassQuality", "glassPhase", "renderer", "rendererBackend", "theme"):
        if not _known(condition.get(key_name)):
            issues.append(f"actual.{key_name} 缺失或未知")
    if condition.get("glassEnabled") is not variant.startswith("glass_on_") or condition.get("starfield") is not variant.endswith("_stars_on"):
        issues.append("实际开关与档位不一致")
    if type(condition.get("glassFrost")) is not bool:
        issues.append("actual.glassFrost 未确认")
    card_glass = condition.get("scrollCardGlassEnabled")
    if metadata.get("measurementKind") in ("raster_controls_v3", "raster_controls_v4") or "scrollCardGlassEnabled" in condition:
        if type(card_glass) is not bool:
            issues.append("actual.scrollCardGlassEnabled 未确认")
        elif card_glass and condition.get("glassEnabled") is not True:
            issues.append("列表卡片真玻璃要求全局玻璃开启")
    for key_name in ACTUAL_DIMENSIONS:
        value = condition.get(key_name)
        if not _number(value) or value <= 0:
            issues.append(f"actual.{key_name} 未记录或无效；采样需保持相同尺寸/缩放")
    if condition.get("theme") != metadata.get("theme"):
        issues.append("每帧实际主题与报告元数据不同")
    if str(condition.get("renderer", "")).lower() != str(metadata.get("renderer", "")).lower():
        issues.append("每帧 renderer 与设备证据不同")
    if condition.get("rendererBackend") != metadata.get("rendererBackend"):
        issues.append("每帧 rendererBackend 与设备证据不同")
    hz = condition.get("refreshRateHz")
    budget = condition.get("adaptiveTargetFrameMs")
    if not _number(hz) or not 10 <= hz <= 1000:
        issues.append("actual.refreshRateHz 无效")
    else:
        if not _number(budget) or abs(budget - 1000 / hz) > 0.05:
            issues.append("自适应预算与刷新率不一致")
        for window in WINDOWS:
            group = raw.get(window)
            if isinstance(group, dict) and group.get("frameCount") and group.get("refreshRatesHz") != [hz]:
                issues.append(f"{window} 刷新率与实际条件不同")
    condition_group = raw["conditions"][0]
    if any(condition_group.get(window) != raw.get(window) for window in WINDOWS):
        issues.append("单组条件统计与本格统计不一致")
    return cell


def build_matrix(reports: list[dict[str, Any]]) -> Matrix:
    if not reports:
        raise ValueError("at least one report is required")
    reports = [validate_report(report) for report in reports]
    first = reports[0]
    cells: dict[str, Cell] = {}
    page_entries: dict[str, Any] = {}
    for report in reports:
        if report["startedAt"] != first["startedAt"]:
            raise ValueError("refusing to merge different startedAt sessions")
        if report is not first:
            for key in (*IDENTITY_KEYS, *DIMENSION_KEYS):
                left, right = first["metadata"].get(key), report["metadata"].get(key)
                if key in IDENTITY_KEYS and (not _known(left) or not _known(right)):
                    raise ValueError(f"refusing to merge unknown metadata.{key}")
                if left != right:
                    raise ValueError(f"refusing to merge different metadata.{key}")
        for key, raw in report["cases"].items():
            if key in cells:
                raise ValueError(f"duplicate matrix cell: {key}; explicit resampling/export is required")
            cells[key] = _validate_cell(raw, key, report["metadata"])
        for page, entry in report.get("pageEntries", {}).items():
            if page in page_entries and page_entries[page] != entry:
                raise ValueError(f"conflicting global page entry: {page}; refusing to pool snapshots")
            page_entries[page] = entry
    return Matrix(first["startedAt"], first["metadata"], cells, page_entries)


def pair_issues(left: Cell | None, right: Cell | None) -> list[str]:
    if left is None or right is None:
        return ["缺格"]
    if left.issues or right.issues:
        return ["含无效格"]
    issues = []
    if left.case["scenario"] != right.case["scenario"]:
        issues.append("场景不同，拒绝比较")
    for key in (*IDENTITY_KEYS, *DIMENSION_KEYS):
        if left.metadata.get(key) != right.metadata.get(key):
            issues.append(f"metadata.{key} 不同")
    for key in ("fixtureId", "messageCount", "pages"):
        if left.case.get(key) != right.case.get(key):
            issues.append(f"{key} 不同")
    for key in ("renderer", "rendererBackend", "refreshRateHz", "adaptiveTargetFrameMs", "theme", *ACTUAL_DIMENSIONS):
        if left.condition.get(key) != right.condition.get(key):
            issues.append(f"actual.{key} 不同")
    # Older v2 captures did not expose this independent switch. Keep their
    # original within-matrix comparisons readable, but never silently treat a
    # new static card as the old glass card (or compare mixed card modes).
    if ("scrollCardGlassEnabled" in left.condition) != ("scrollCardGlassEnabled" in right.condition):
        issues.append("列表卡片渲染条件的记录版本不同")
    elif left.condition.get("scrollCardGlassEnabled") != right.condition.get("scrollCardGlassEnabled"):
        issues.append("actual.scrollCardGlassEnabled 不同；需同一卡片模式对照")
    if left.condition["glassEnabled"] and right.condition["glassEnabled"]:
        for key in ("glassQuality", "glassPhase", "glassFrost"):
            if left.condition.get(key) != right.condition.get(key):
                issues.append(f"actual.{key} 不同")
    left_fixed, right_fixed = left.condition.get("fixedGlass"), right.condition.get("fixedGlass")
    if (left_fixed is None) != (right_fixed is None):
        issues.append("固定玻璃作用域记录不同")
    elif isinstance(left_fixed, dict) and isinstance(right_fixed, dict):
        for key in ("context", "policy", "presentRoles", "baseBlur", "baseSaturation",
                    "prewarmEnabled", "prewarmStatus", "prewarmLogicalWidth",
                    "prewarmLogicalHeight", "prewarmPixelRatio"):
            if left_fixed.get(key) != right_fixed.get(key):
                issues.append(f"actual.fixedGlass.{key} 不同")
    return issues


def _value(cell: Cell | None, window: str, metric: str) -> str:
    if cell is None or cell.issues:
        return "—"
    group = cell.case[window]
    if not group["frameCount"]:
        return "—"
    value = group["raster"][metric]
    return f"{value:.2%}" if metric == "overBudgetRatio" else f"{value:.3f}"


def render_matrix(matrix: Matrix) -> str:
    valid = sum(not cell.issues for cell in matrix.cells.values())
    lines = ["# SmartFit Raster 同场景对照", "", f"采集轮次：`{_text(matrix.started_at)}`；有效格 {valid}/8。", ""]
    lines.append("；".join(f"{key}={_text(matrix.metadata.get(key))}" for key in (
        "deviceManufacturer", "deviceModel", "systemVersion", "appVersion", "appBuild",
        "appSource", "renderer", "rendererBackend", "theme")) + "。")
    lines.extend(["", "只比较同一固定场景的单开关差值；不合并帧、均值或百分位。缺格和无效格用 —，不当成 0。",
                  "前 2 秒与首次进入页面窗口可重叠；尖峰本身不能确认着色器编译。超预算比例是引擎 Raster 耗时超过帧预算的比例，并非屏幕实际掉帧率。"])
    if not matrix.cells or any(any(not _number(cell.condition.get(key)) for key in ACTUAL_DIMENSIONS) for cell in matrix.cells.values()):
        lines.append("尺寸未记录或不完整：对应格不参与差值；需要开哥保持相同竖屏/窗口尺寸、字体大小、显示缩放及方向并重新采样。")
    else:
        lines.append("每格已记录实际窗口尺寸、像素比和文字缩放；差值逐格核对。采样必须保持相同方向与系统外观。")
    lines.append("主题同时核对每帧实际条件和报告元数据；采样中应保持主题不变。")
    if matrix.metadata.get("measurementKind") in ("raster_controls_v3", "raster_controls_v4"):
        lines.append("glass_on/off 表示全局玻璃开关；列表卡片独立记录 scrollCardGlassEnabled，默认静态仿玻璃。不同实际卡片模式不用于本表的单开关差值。")
    else:
        lines.append("旧版报告未独立记录列表卡片模式：卡片沿用当时的全局玻璃路径，不能当成新版默认静态仿玻璃。")
    if matrix.metadata.get("isEmulator") is True:
        lines.append("本次为模拟器数据，只能作相对比较，绝对值不代表真机。")
    lines.extend(["", "## 稳态 Raster（首次 case 帧 +2 秒之后）", "",
                  "| 档位 | 固定场景 | 平均 ms | P90 ms | P99 ms | 超预算比例 | 有效性 |",
                  "| --- | --- | ---: | ---: | ---: | ---: | --- |"])
    for variant in VARIANTS:
        for scenario in SCENARIOS:
            cell = matrix.cells.get(f"{variant}__{scenario}")
            status = "缺格" if cell is None else ("有效" if not cell.issues else "无效：" + "；".join(cell.issues))
            values = " | ".join(_value(cell, "steadyState", key) for key in ("averageMs", "p90Ms", "p99Ms", "overBudgetRatio"))
            lines.append(f"| {variant} | {scenario} | {values} | {_text(status)} |")
    lines.extend(["", "## 每格实际列表卡片模式", "",
                  "| 档位 | 固定场景 | 实际卡片模式 |",
                  "| --- | --- | --- |"])
    for variant in VARIANTS:
        for scenario in SCENARIOS:
            cell = matrix.cells.get(f"{variant}__{scenario}")
            mode = "缺格"
            if cell is not None:
                actual = cell.condition.get("scrollCardGlassEnabled")
                if type(actual) is bool:
                    mode = "真玻璃" if actual else "静态仿玻璃"
                elif cell.metadata.get("measurementKind") == "raster_controls_v2" and "scrollCardGlassEnabled" not in cell.condition:
                    mode = "旧版：沿用全局玻璃（未独立记录）"
                else:
                    mode = "未知；不可对照"
            lines.append(f"| {variant} | {scenario} | {mode} |")
    lines.extend(["", "## 前 2 秒与最差帧（Raster）", "",
                  "| 档位 | 固定场景 | 前 2 秒平均 ms | 前 2 秒最差 ms | 本格与首次进页 2 秒交集最差 ms | 稳态最差 ms | 全段最差 ms |",
                  "| --- | --- | ---: | ---: | ---: | ---: | ---: |"])
    for variant in VARIANTS:
        for scenario in SCENARIOS:
            cell = matrix.cells.get(f"{variant}__{scenario}")
            columns = (("warmupFirst2Seconds", "averageMs"), ("warmupFirst2Seconds", "worstMs"),
                       ("firstPageEntryFirst2Seconds", "worstMs"), ("steadyState", "worstMs"), ("allFrames", "worstMs"))
            values = " | ".join(_value(cell, window, metric) for window, metric in columns)
            lines.append(f"| {variant} | {scenario} | {values} |")
    lines.extend(["", "## 全局首次进页前 2 秒（包含 beginCase 之前）", "",
                  "这组样本按本轮首次进入页面统计，不绑定某个档位，不参与四档差值；可与 case 初始窗口重叠。",
                  "", "| 页面 | 帧数 | Raster 平均 ms | P90 ms | P99 ms | 最差 ms | 超预算比例 | 有效性 |",
                  "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"])
    pages = {page for cell in matrix.cells.values()
             for page in (cell.case.get("pages", []) if isinstance(cell.case.get("pages", []), list) else [])
             if isinstance(page, str)}
    for page in sorted(pages):
        entry = matrix.page_entries.get(page)
        group = entry.get("first2Seconds") if isinstance(entry, dict) else None
        issues = _window_issues(group, "first2Seconds")
        if not isinstance(entry, dict) or not _integer(entry.get("firstVsyncStartUs")) or entry.get("earlierOutOfOrderFrameCount") != 0:
            issues.append("首进时间未记录或含乱序帧")
        if issues or not group.get("frameCount", 0):
            values = "— | — | — | — | — | —"
            status = "缺失/无效：" + "；".join(issues) if issues else "没有首进样本"
        else:
            raster = group["raster"]
            values = f"{group['frameCount']} | " + " | ".join(f"{raster[key]:.3f}" for key in ("averageMs", "p90Ms", "p99Ms", "worstMs"))
            values += f" | {raster['overBudgetRatio']:.2%}"
            status = "有效；仅作首进观察"
        lines.append(f"| {_text(page)} | {values} | {_text(status)} |")
    if not pages:
        lines.append("| — | — | — | — | — | — | — | 未记录可关联页面 |")
    lines.extend(["", "## 仅同场景、单开关差值（关闭后减关闭前）", "",
                  "| 固定场景 | 对照 | 平均 Δms | P90 Δms | P99 Δms | 超预算 Δ百分点 | 可比性 |",
                  "| --- | --- | ---: | ---: | ---: | ---: | --- |"])
    for scenario in SCENARIOS:
        for title, left_variant, right_variant in PAIRS:
            left = matrix.cells.get(f"{left_variant}__{scenario}")
            right = matrix.cells.get(f"{right_variant}__{scenario}")
            issues = pair_issues(left, right)
            if issues:
                values = "— | — | — | —"
                status = "拒绝比较：" + "；".join(issues)
            else:
                before = left.case["steadyState"]["raster"]
                after = right.case["steadyState"]["raster"]
                values = " | ".join(f"{after[key] - before[key]:+.3f}" for key in ("averageMs", "p90Ms", "p99Ms"))
                values += f" | {(after['overBudgetRatio'] - before['overBudgetRatio']) * 100:+.2f}"
                status = "已记录条件一致；仍需重复采样确认"
            lines.append(f"| {scenario} | {title} | {values} | {_text(status)} |")
    lines.extend(["", "差值仅描述本轮同场景观测；本工具不推断根因，也不把单次波动或初始尖峰归为着色器编译。",
                  "P90/P99 沿用导出报告的直方图上界估计；平均与最差帧沿用报告精确值。", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    # Windows text streams otherwise translate generated Markdown to CRLF.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(newline="\n")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path, nargs="+")
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args(argv)
    try:
        output = render_matrix(build_matrix([load_report(path) for path in args.reports]))
        if args.output:
            args.output.write_text(output, encoding="utf-8", newline="\n")
        else:
            sys.stdout.write(output)
    except (OSError, ValueError) as error:
        print(f"raster_matrix: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
