"""Compare exported SmartFit frame reports; never acts as a performance gate.

Usage: python tools/performance/compare_reports.py before.json after.json [-o out.md]
Only the Python standard library is needed. No sample measurements are bundled.
"""

from __future__ import annotations

import argparse
import html
import json
import math
from pathlib import Path
import sys
from typing import Any


SCENARIOS = (
    ("actionListScroll", "动作库快速滑动"),
    ("filterSwitch", "筛选切换"),
    ("actionDetail", "动作详情进出"),
    ("longChatScroll", "长聊天记录滑动"),
    ("planExpand", "计划卡展开"),
    ("trainingActionSwitch", "训练页切换动作"),
    ("mediaDownloadScroll", "素材下载与校验中滑动（下载总窗口）"),
)
THREADS = (("uiBuild", "UI build"), ("raster", "Raster"))
DURATIONS = (
    ("averageMs", "平均 ms"),
    ("p90Ms", "P90 ms"),
    ("p99Ms", "P99 ms"),
    ("worstMs", "最差 ms"),
)
REQUIRED_CONDITIONS = (
    "deviceModel", "deviceManufacturer", "systemVersion", "deviceApiLevel",
    "platform", "isEmulator", "buildMode", "flavor", "renderer",
    "metadataStatus", "theme", "starfield", "glassQuality",
    "appBaseCommit", "sdkRef",
)
DISPLAY_METADATA = (
    "appVersion", "appBuild", "appBuildNumber", "appSource", "appBaseCommit", "sdkRef",
    "measurementKind", "buildMode", "flavor", "deviceModel",
    "deviceManufacturer", "systemVersion", "deviceApiLevel", "platform",
    "isEmulator", "metadataStatus", "renderer", "refreshRateSource",
    "appearance", "theme", "starfield", "glassQuality",
)
UNKNOWN = {"", "unknown", "unavailable", "unverified", "unspecified", "n/a"}


def _integer(value: Any, context: str) -> int:
    if type(value) is not int or value < 0:
        raise ValueError(f"{context}: expected a non-negative integer")
    return value


def _number(value: Any, context: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError(f"{context}: expected a finite non-negative number")
    return value


def _validate_group(group: Any, context: str) -> None:
    if not isinstance(group, dict):
        raise ValueError(f"{context}: expected a statistics object")
    count = _integer(group.get("frameCount"), f"{context}.frameCount")
    over = []
    for key, _ in THREADS:
        thread = group.get(key)
        if not isinstance(thread, dict):
            raise ValueError(f"{context}.{key}: expected thread statistics")
        for metric, _ in DURATIONS:
            value = thread.get(metric)
            if count:
                _number(value, f"{context}.{key}.{metric}")
            elif value is not None:
                raise ValueError(f"{context}.{key}.{metric}: empty group must use null")
        if count:
            if not (thread["p90Ms"] <= thread["p99Ms"] <= thread["worstMs"]):
                raise ValueError(f"{context}.{key}: percentiles exceed the observed worst")
            if thread["averageMs"] > thread["worstMs"]:
                raise ValueError(f"{context}.{key}: average exceeds the observed worst")
        over.append(_integer(thread.get("overBudgetFrames"),
                             f"{context}.{key}.overBudgetFrames"))
        if over[-1] > count:
            raise ValueError(f"{context}.{key}: over-budget count exceeds frameCount")
    union = _integer(group.get("eitherThreadOverBudgetFrames"),
                     f"{context}.eitherThreadOverBudgetFrames")
    if not max(over) <= union <= min(count, sum(over)):
        raise ValueError(f"{context}: inconsistent either-thread union")
    rates = group.get("refreshRatesHz")
    if not isinstance(rates, list):
        raise ValueError(f"{context}.refreshRatesHz: expected a list")
    for rate in rates:
        if not 10 <= _number(rate, f"{context}.refreshRatesHz") <= 1000:
            raise ValueError(f"{context}.refreshRatesHz: expected rates between 10 and 1000")
    if len(set(rates)) != len(rates):
        raise ValueError(f"{context}.refreshRatesHz: duplicate rates")
    if type(group.get("refreshRatesTruncated", False)) is not bool:
        raise ValueError(f"{context}.refreshRatesTruncated: expected a boolean")


def validate_report(report: Any) -> dict[str, Any]:
    if not isinstance(report, dict):
        raise ValueError("report: expected a JSON object")
    if type(report.get("schema")) is not int or report["schema"] != 1:
        raise ValueError("report: only schema=1 is supported")
    if report.get("reportType") != "frame_performance":
        raise ValueError("report: expected reportType=frame_performance")
    if report.get("app") != "smartfit":
        raise ValueError("report: expected app=smartfit")
    if not isinstance(report.get("metadata"), dict):
        raise ValueError("report.metadata: expected an object")
    if not isinstance(report.get("scenarios"), dict):
        raise ValueError("report.scenarios: expected an object")
    _validate_group(report.get("total"), "total")
    for name, group in report["scenarios"].items():
        _validate_group(group, f"scenarios.{name}")
    count = _integer(report.get("recordedFrameCount"), "recordedFrameCount")
    if count != report["total"]["frameCount"]:
        raise ValueError("recordedFrameCount differs from total.frameCount")
    if sum(g["frameCount"] for g in report["scenarios"].values()) > count:
        raise ValueError("scenario frame counts exceed total; schema permits one scenario per frame")
    for key in ("unattributedFrameCount", "ignoredBeforeSessionFrameCount",
                "ignoredInactiveFrameCount", "invalidTimingFrameCount",
                "unavailableFrameKeyBoundaryCount", "conditionChangesDuringCapture"):
        if key in report:
            _integer(report[key], key)
    return report


def load_report(path: Path) -> dict[str, Any]:
    # utf-8-sig also accepts exports copied through Windows editors with a BOM.
    try:
        report = json.loads(path.read_text(encoding="utf-8-sig"))
        return validate_report(report)
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"{path.name}: {error}") from error


def _text(value: Any) -> str:
    if value is None:
        return "未记录"
    if isinstance(value, bool):
        value = "true" if value else "false"
    return html.escape(str(value)).replace("|", "&#124;").replace("\r", " ").replace("\n", " ")


def _known(value: Any) -> bool:
    return value is not None and not (
        isinstance(value, str) and value.strip().lower() in UNKNOWN
    )


def _rates(group: dict[str, Any] | None) -> tuple[float, ...]:
    return tuple(sorted(group.get("refreshRatesHz", []))) if group else ()


def condition_issues(before: dict[str, Any], after: dict[str, Any],
                     before_group: dict[str, Any] | None = None,
                     after_group: dict[str, Any] | None = None) -> list[str]:
    issues = []
    for key in REQUIRED_CONDITIONS:
        left, right = before["metadata"].get(key), after["metadata"].get(key)
        if not _known(left) or not _known(right):
            issues.append(f"{key} 缺失或未知")
        elif left != right:
            issues.append(f"{key} 不同（{_text(left)} → {_text(right)}）")
    for label, report in (("基线", before), ("修改后", after)):
        metadata = report["metadata"]
        if metadata.get("metadataStatus") != "available":
            issues.append(f"{label}设备元信息不可用")
        if metadata.get("buildMode") not in ("profile", "release"):
            issues.append(f"{label}不是 profile/release 构建")
        if metadata.get("refreshRateSource") not in ("flutter_display", "android_display"):
            issues.append(f"{label}刷新率来源未确认是 flutter_display/android_display")
        if "conditionChangesDuringCapture" not in report:
            issues.append(f"{label}未记录采集期间条件变更次数")
        elif report["conditionChangesDuringCapture"]:
            issues.append(f"{label}采集期间条件变化 {report['conditionChangesDuringCapture']} 次，"
                          "最终条件相同也不适合直接归因")
    left = before["total"] if before_group is None else before_group
    right = after["total"] if after_group is None else after_group
    if not _rates(left) or not _rates(right):
        issues.append("刷新率未记录")
    elif _rates(left) != _rates(right):
        issues.append(f"refreshRatesHz 不同（{_text(list(_rates(left)))} → {_text(list(_rates(right)))}）")
    if left.get("refreshRatesTruncated") or right.get("refreshRatesTruncated"):
        issues.append("刷新率集合被截断")
    if len(_rates(left)) > 1 or len(_rates(right)) > 1:
        issues.append("含多档刷新率，缺少各档样本分布")
    return issues


def _cell(group: dict[str, Any] | None, key: str, metric: str) -> str:
    if not group or not group["frameCount"]:
        return "未采集"
    value = group[key][metric]
    if metric == "overBudgetFrames":
        return f"{value}（{value / group['frameCount']:.2%}）"
    return f"{value:.3f}"


def _change(left: float, right: float) -> str:
    if left == 0:
        return "0.0%（均为 0）" if right == 0 else "不适用（基线为 0）"
    return f"{(right - left) / left:+.1%}"


def _metric_change(before: dict[str, Any] | None, after: dict[str, Any] | None,
                   key: str, metric: str) -> str:
    if not before or not after or not before["frameCount"] or not after["frameCount"]:
        return "不适用（缺样本）"
    left, right = before[key][metric], after[key][metric]
    if metric == "overBudgetFrames":
        # Raw counts depend on the sampling length; compare their rates too.
        pp = (right / after["frameCount"] - left / before["frameCount"]) * 100
        return f"计数 {_change(left, right)}；占比 {pp:+.2f} 个百分点"
    return _change(left, right)


def _group_section(before: dict[str, Any], after: dict[str, Any], key: str,
                   title: str) -> list[str]:
    left, right = before["scenarios"].get(key), after["scenarios"].get(key)
    lines = [f"### {title}", "", f"场景标识：`{key}`。", ""]
    for label, group in (("基线", left), ("修改后", right)):
        if not group:
            lines.append(f"{label}：未采集（缺少场景）。")
        elif not group["frameCount"]:
            lines.append(f"{label}：未采集（场景存在，frameCount=0，无帧样本）。")
    if left and right and left["frameCount"] and right["frameCount"]:
        issues = condition_issues(before, after, left, right)
        lines.append("可比性：" + ("不可直接比较；" + "；".join(issues) + "。"
                     if issues else "已记录的关键条件一致；仍仅作诊断比较。"))
    else:
        lines.append("可比性：不可直接比较；缺少两侧有效样本。")
    lines.extend(["", "| 线程 | 指标 | 基线 | 修改后 | 相对变化（诊断） |",
                  "| --- | --- | --- | --- | --- |"])
    for thread_key, thread_name in THREADS:
        for metric, metric_name in (*DURATIONS, ("overBudgetFrames", "超预算帧数 / 占比")):
            lines.append(f"| {thread_name} | {metric_name} | {_cell(left, thread_key, metric)} | "
                         f"{_cell(right, thread_key, metric)} | "
                         f"{_metric_change(left, right, thread_key, metric)} |")
    lines.extend(["", "| 共同帧样本 | 基线 | 修改后 | 变化 |", "| --- | --- | --- | --- |"])
    counts = ["未采集" if not g or not g["frameCount"] else str(g["frameCount"])
              for g in (left, right)]
    count_delta = (_change(left["frameCount"], right["frameCount"])
                   if left and right and left["frameCount"] and right["frameCount"]
                   else "不适用（缺样本）")
    lines.append(f"| frameCount | {counts[0]} | {counts[1]} | {count_delta} |")
    unions = []
    for group in (left, right):
        if not group or not group["frameCount"]:
            unions.append("未采集")
        else:
            union = group["eitherThreadOverBudgetFrames"]
            unions.append(f"{union}（{union / group['frameCount']:.2%}）")
    union_delta = "不适用（缺样本）"
    if left and right and left["frameCount"] and right["frameCount"]:
        a, b = left["eitherThreadOverBudgetFrames"], right["eitherThreadOverBudgetFrames"]
        pp = (b / right["frameCount"] - a / left["frameCount"]) * 100
        union_delta = f"计数 {_change(a, b)}；占比 {pp:+.2f} 个百分点"
    lines.append(f"| 任一线程超预算 union | {unions[0]} | {unions[1]} | {union_delta} |")
    lines.extend(["", "刷新率 Hz：基线 " + _text(list(_rates(left)) or None)
                  + "；修改后 " + _text(list(_rates(right)) or None) + "。", ""])
    return lines


def render_comparison(before: dict[str, Any], after: dict[str, Any]) -> str:
    validate_report(before)
    validate_report(after)
    issues = condition_issues(before, after)
    lines = ["# SmartFit 帧报告对比", "",
             "这是导出报告的诊断比较，不自动判定性能通过，不替代开哥验收或真机 DevTools。",
             "appVersion、appBuild、appSource 可以不同；appBaseCommit 与 sdkRef 必须一致。",
             "", "## 测量条件", "",
             "全局条件：" + ("不可直接比较；" + "；".join(issues) + "。"
                         if issues else "已记录的关键条件一致；各场景仍需有效样本。"),
             "", "| 条件 | 基线 | 修改后 |", "| --- | --- | --- |"]
    for key in DISPLAY_METADATA:
        lines.append(f"| `{key}` | {_text(before['metadata'].get(key))} | "
                     f"{_text(after['metadata'].get(key))} |")
    lines.extend(["", "## 数据限制", "",
                  "P90/P99 来自记录器的对数直方图上界估计（误差不超过耗时的 6.25% 或 1 微秒）；平均与最差值精确。",
                  "超预算指单线程耗时大于该帧刷新周期；union 对任一线程超预算的同一帧只计一次。UI 与 Raster 不相加。",
                  "百分比为（修改后 − 基线）/ 基线；负值只描述数值下降。计数受采样时长影响，需同时看占比和 frameCount。",
                  "没有每帧原始样本，不计算显著性、置信区间或自动门禁；FrameTiming 也不覆盖全部 WebView/视频显示帧。", ""])
    for label, report in (("基线", before), ("修改后", after)):
        count = report["recordedFrameCount"]
        lines.append(f"- {label}：recordedFrameCount={count}；"
                     f"unattributedFrameCount={report.get('unattributedFrameCount', '未记录')}。")
        if not count:
            lines.append(f"  {label}无帧样本；不能得出任何性能改善结论。")
        if report.get("unattributedFrameCount", 0):
            lines.append(f"  {label}存在未归因帧，已排除在耗时与超预算统计之外；场景覆盖可能不完整。")
        if report.get("conditionChangesDuringCapture", 0):
            lines.append(f"  conditionChangesDuringCapture={report['conditionChangesDuringCapture']}；"
                         "请固定主题、星尘、玻璃质量及刷新率后重置并重新采集。")
        if "unattributedFrameCount" not in report:
            lines.append(f"  {label}未记录未归因帧计数，无法确认归因覆盖。")
        if report["metadata"].get("isEmulator") is True:
            lines.append(f"  {label}来自模拟器：仅用于相同环境下的相对诊断，绝对值不代表真机。")
        for key in ("invalidTimingFrameCount", "ignoredBeforeSessionFrameCount",
                    "ignoredInactiveFrameCount", "unavailableFrameKeyBoundaryCount"):
            if report.get(key, 0):
                lines.append(f"  {key}={report[key]}；请结合采集生命周期解释排除窗口。")
    lines.extend(["", "## 七个场景", ""])
    for key, title in SCENARIOS:
        lines.extend(_group_section(before, after, key, title))
    lines.extend(["下载总窗口可能包含校验；SDK 未公开独立校验 phase，不能从这个窗口单独归因 SHA-256。",
                  "`mediaVerifyScroll` 不自动补数，也不与下载场景合并均值或百分位。", ""])
    if "mediaVerifyScroll" in before["scenarios"] or "mediaVerifyScroll" in after["scenarios"]:
        lines.extend(_group_section(before, after, "mediaVerifyScroll", "附加：独立校验标记（需核对人工采样边界）"))
    known = {key for key, _ in SCENARIOS} | {"mediaVerifyScroll"}
    extras = (set(before["scenarios"]) | set(after["scenarios"])) - known
    if extras:
        lines.append("额外场景未纳入七场景对比：" + "、".join(_text(k) for k in sorted(extras)) + "。")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path, help="baseline exported JSON")
    parser.add_argument("after", type=Path, help="candidate exported JSON")
    parser.add_argument("-o", "--output", type=Path, help="write UTF-8 Markdown (default: stdout)")
    args = parser.parse_args(argv)
    try:
        if args.output and args.output.resolve() in (args.before.resolve(), args.after.resolve()):
            raise ValueError("output must not overwrite either input report")
        markdown = render_comparison(load_report(args.before), load_report(args.after))
        if args.output:
            args.output.write_text(markdown, encoding="utf-8")
        else:
            if hasattr(sys.stdout, "reconfigure"):
                sys.stdout.reconfigure(encoding="utf-8")
            sys.stdout.write(markdown)
    except (OSError, ValueError) as error:
        print(f"compare_reports: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
