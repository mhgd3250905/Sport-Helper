#!/usr/bin/env python3
"""Read-only per-clip size audit and bitrate budget; never transcodes assets.

Requires ffprobe on PATH. All MB values use 1,000,000 bytes and kbps use
1,000 bits/s. Container overhead is measured as file bytes minus packet bytes.
The future-size budgets are sensitivity calculations, not encoded output sizes.
"""

import argparse
import csv
import hashlib
import json
import math
import statistics
import subprocess
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ENTRIES = (
    "format=format_name,duration,size,bit_rate:"
    "stream=codec_name,profile,codec_tag_string,channels,channel_layout,"
    "sample_rate,duration,bit_rate,start_time,nb_frames:"
    "packet=size,duration_time:packet_side_data=skip_samples,discard_padding"
)


def inventory(root, paths):
    return [
        {
            "path": p.relative_to(root).as_posix(),
            "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        }
        for p in paths
    ]


def inventory_hash(items):
    data = "".join(f"{i['path']}\t{i['bytes']}\t{i['sha256']}\n" for i in items)
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def number(value):
    return float(value) if value not in (None, "N/A", "") else None


def probe(root, path):
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         ENTRIES, "-of", "json", str(path)],
        capture_output=True, text=True, encoding="utf-8", check=True,
    )
    data = json.loads(result.stdout)
    streams = data.get("streams", [])
    if len(streams) != 1:
        raise ValueError(f"Expected one selected audio stream: {path}")
    stream, fmt, packets = streams[0], data["format"], data.get("packets", [])
    if not packets:
        raise ValueError(f"No audio packets: {path}")
    stream_s, container_s = number(stream.get("duration")), number(fmt["duration"])
    duration = stream_s if stream_s is not None else container_s
    if duration is None or not math.isfinite(duration) or duration <= 0:
        raise ValueError(f"Invalid duration: {path}")
    total_bytes = path.stat().st_size
    if total_bytes != int(fmt["size"]):
        raise ValueError(f"ffprobe size mismatch: {path}")
    payload = sum(int(p["size"]) for p in packets)
    if payload > total_bytes:
        raise ValueError(f"Packet bytes exceed file size: {path}")
    side_data = [s for p in packets for s in p.get("side_data_list", [])]
    return {
        "path": path.relative_to(root).as_posix(),
        "pack": path.parents[2].name,
        "clip": path.stem,
        "file_bytes": total_bytes,
        "codec": stream["codec_name"],
        "profile": stream.get("profile", ""),
        "codec_tag": stream.get("codec_tag_string", ""),
        "container": fmt["format_name"],
        "channels": int(stream["channels"]),
        "channel_layout": stream.get("channel_layout", ""),
        "sample_rate_hz": int(stream["sample_rate"]),
        "duration_s": duration,
        "stream_duration_s": stream_s,
        "container_duration_s": container_s,
        "stream_bit_rate_bps": number(stream.get("bit_rate")),
        "container_bit_rate_bps": number(fmt.get("bit_rate")),
        "effective_payload_bit_rate_bps": payload * 8 / duration,
        "effective_file_bit_rate_bps": total_bytes * 8 / duration,
        "audio_payload_bytes": payload,
        "container_metadata_bytes": total_bytes - payload,
        "packet_count": len(packets),
        "packet_duration_s": sum(float(p.get("duration_time", 0)) for p in packets),
        "skip_samples": sum(int(s.get("skip_samples", 0)) for s in side_data),
        "discard_padding_samples": sum(int(s.get("discard_padding", 0)) for s in side_data),
    }


def percentile(values, p):
    ordered = sorted(values)
    position = (len(ordered) - 1) * p
    lower, upper = math.floor(position), math.ceil(position)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def distribution(values):
    return {
        "min": min(values), "median": statistics.median(values),
        "p90": percentile(values, 0.90), "max": max(values),
    }


def size_estimate(codec, bitrate_kbps, duration_s, packet_duration_s,
                  overhead_bytes, original_bytes):
    payload = duration_s * bitrate_kbps * 1000 / 8
    # A shared accounting convention for comparison, not an Ogg/MP4 guarantee.
    # The upper sensitivity also budgets the current AAC packet-time excess.
    lower = payload + overhead_bytes
    upper = packet_duration_s * bitrate_kbps * 1000 / 8 + overhead_bytes * 2
    return {
        "codec": codec, "mono": True, "target_kbps": bitrate_kbps,
        "theoretical_payload_bytes": payload,
        "budget_size_low_bytes": lower, "budget_size_high_bytes": upper,
        "budget_savings_low_bytes": original_bytes - upper,
        "budget_savings_high_bytes": original_bytes - lower,
        "budget_savings_low_percent": (original_bytes - upper) / original_bytes * 100,
        "budget_savings_high_percent": (original_bytes - lower) / original_bytes * 100,
    }


def summarize(rows):
    duration = sum(r["duration_s"] for r in rows)
    packet_duration = sum(r["packet_duration_s"] for r in rows)
    size = sum(r["file_bytes"] for r in rows)
    payload = sum(r["audio_payload_bytes"] for r in rows)
    overhead = size - payload
    bins = Counter()
    for row in rows:
        kbps = row["stream_bit_rate_bps"] / 1000
        label = next((label for boundary, label in (
            (56, "<56"), (60, "56–<60"), (64, "60–<64"),
            (68, "64–<68"), (72, "68–<72"), (float("inf"), ">=72"),
        ) if kbps < boundary), ">=72")
        bins[label] += 1
    return {
        "clips": len(rows), "total_file_bytes": size,
        "total_audio_payload_bytes": payload, "total_container_metadata_bytes": overhead,
        "container_metadata_percent": overhead / size * 100,
        "total_duration_s": duration, "total_duration_minutes": duration / 60,
        "duration_seconds": distribution([r["duration_s"] for r in rows]),
        "clips_under_1_second": sum(r["duration_s"] < 1 for r in rows),
        "clips_under_2_seconds": sum(r["duration_s"] < 2 for r in rows),
        "total_packet_duration_s": packet_duration,
        "packet_duration_excess_s": packet_duration - duration,
        "total_skip_samples": sum(r["skip_samples"] for r in rows),
        "total_skip_duration_s": sum(r["skip_samples"] / r["sample_rate_hz"] for r in rows),
        "weighted_effective_payload_kbps": payload * 8 / duration / 1000,
        "weighted_effective_file_kbps": size * 8 / duration / 1000,
        "stream_bitrate_kbps": distribution([r["stream_bit_rate_bps"] / 1000 for r in rows]),
        "container_bitrate_kbps": distribution([r["container_bit_rate_bps"] / 1000 for r in rows]),
        "stream_bitrate_bins_kbps": dict(sorted(bins.items())),
        "codecs": dict(Counter(r["codec"] for r in rows)),
        "profiles": dict(Counter(r["profile"] for r in rows)),
        "containers": dict(Counter(r["container"] for r in rows)),
        "channels": dict(Counter(str(r["channels"]) for r in rows)),
        "sample_rates_hz": dict(Counter(str(r["sample_rate_hz"]) for r in rows)),
        "estimates": [size_estimate(codec, bps, duration, packet_duration, overhead, size)
                      for codec, rates in (("AAC", (24, 32, 48)), ("Opus", (16, 24, 32)))
                      for bps in rates],
        "shortest": min(rows, key=lambda r: r["duration_s"])["path"],
        "longest": max(rows, key=lambda r: r["duration_s"])["path"],
    }


def markdown(report, csv_path, json_path):
    s, integrity = report["summary"], report["integrity"]
    duration, br = s["duration_seconds"], s["stream_bitrate_kbps"]
    lines = [
        "# SmartFit 训练语音体积统计（2026-10-22）", "",
        f"695 条语音合计 **{s['total_file_bytes'] / 1e6:.6f} MB**；全部已是 "
        "**AAC-LC、M4A 容器、44.1 kHz、单声道**。单声道本身没有额外缩小空间，"
        "进一步节省来自码率或编码器改变。本次只读取与测量，未转码、未改素材或 pack.json。", "",
        "MB = 1,000,000 字节；kbps = 1,000 bit/s。以下原始文件口径与此前 APK 内语音文件总字节相同；"
        "不把 APK ZIP 压缩率、签名或 ZIP 条目开销算进音频编码估算。", "",
        "## 实测", "",
        "| 指标 | 数字 |", "|---|---:|",
        f"| 文件 / 音频 packet / 容器元数据 | {s['total_file_bytes']:,} / {s['total_audio_payload_bytes']:,} / {s['total_container_metadata_bytes']:,} B |",
        f"| 容器元数据占比 | {s['container_metadata_percent']:.2f}% |",
        f"| 总有效时长 | {s['total_duration_s']:.3f} s（{s['total_duration_minutes']:.3f} 分钟） |",
        f"| 单条时长 min / median / p90 / max | {duration['min']:.3f} / {duration['median']:.3f} / {duration['p90']:.3f} / {duration['max']:.3f} s |",
        f"| < 1 秒 / < 2 秒 | {s['clips_under_1_second']} / {s['clips_under_2_seconds']} 条 |",
        f"| 流码率 min / median / p90 / max | {br['min']:.3f} / {br['median']:.3f} / {br['p90']:.3f} / {br['max']:.3f} kbps |",
        f"| 按总时长加权的有效音频 / 文件码率 | {s['weighted_effective_payload_kbps']:.3f} / {s['weighted_effective_file_kbps']:.3f} kbps |",
        f"| packet 总时长 − 有效流总时长 | {s['packet_duration_excess_s']:.3f} s |",
        f"| skip-samples 标记 | {s['total_skip_samples']:,} samples（{s['total_skip_duration_s']:.3f} s） |", "",
        "流码率为 ffprobe 的每条 audio stream bit_rate；有效加权码率直接用总 packet 字节或总文件字节 ÷ 总有效时长，"
        "不取 695 条码率的简单平均。packet 字节包含编码首尾帧；文件与 packet 的差额仅算容器 / 元数据，避免把编码延时重复算作容器开销。", "",
        "| 流码率区间（kbps） | 条数 |", "|---|---:|",
    ]
    lines += [f"| {name} | {count} |" for name, count in s["stream_bitrate_bins_kbps"].items()]
    lines += ["", "## 低码率预算（理论估算，尚未编码或评估音质）", "",
        "payload = 总有效时长 × 目标 bit/s ÷ 8。为避免把 695 个短文件当成长音频，统一给出一组**比较预算**："
        "低端 = 理论 payload + 当前实测容器开销；高端 = 当前 packet 总时长 × 目标 bit/s ÷ 8 + 当前容器开销 × 2。"
        "高端使用当前 AAC 首尾帧时间差和双倍容器预算做敏感性分析，**不是 AAC / Opus 成品大小的保证上下界**。"
        "Opus 的 Ogg 等封装、实际 pre-skip / padding、AAC 目标编码器的帧填充和 VBR 偏差都须转码后重测。", "",
        "| 目标（均单声道） | 理论音频 payload | 含开销比较预算 | 预计节省 | 节省比例 |",
        "|---|---:|---:|---:|---:|",
    ]
    for e in s["estimates"]:
        lines.append(
            f"| {e['codec']} {e['target_kbps']} kbps | {e['theoretical_payload_bytes'] / 1e6:.2f} MB | "
            f"{e['budget_size_low_bytes'] / 1e6:.2f}–{e['budget_size_high_bytes'] / 1e6:.2f} MB | "
            f"{e['budget_savings_low_bytes'] / 1e6:.2f}–{e['budget_savings_high_bytes'] / 1e6:.2f} MB | "
            f"{e['budget_savings_low_percent']:.1f}–{e['budget_savings_high_percent']:.1f}% |"
        )
    lines += ["", "建议后续先用 **AAC 32 kbps 和 Opus 24 kbps** 做同一句台词的盲听对比："
        "两点都有可观的理论节省，并能区分仅降码率与换编码器的收益；AAC 48 kbps 可作为较温和的比较点。"
        "这只是下一轮实验取点，不代表已经确认音质或移动端播放兼容性。"
        "验收应覆盖短数字、动作名、换侧口令、长要领，重新校核实际解码时长、响度、真峰值及时间线。"
        "当前资产已经是有损 AAC，若以后正式转码，应优先使用保留的原始音源，避免从本次成品反复有损编码。", "",
        "## 可复查证据", "",
        f"- [逐条 CSV]({csv_path.name})：695 条路径、格式、时长、码率、packet / 容器字节与前后 SHA-256。",
        f"- [完整 JSON]({json_path.name})：汇总、估算公式输入以及前后完整文件 SHA-256 inventory。",
        f"- 测量前 inventory SHA-256：`{integrity['before_inventory_sha256']}`。",
        f"- 测量后 inventory SHA-256：`{integrity['after_inventory_sha256']}`。",
        f"- 文件集合、长度和内容校验：**{'完全一致' if integrity['unchanged'] else '不一致（本次统计失败）'}**。",
        "- 工具只执行 ffprobe 的只读探测，不执行 ffmpeg、网络请求或写入 assets。", "",
        "运行：`python tools/voice/measure_voice_size.py --workers 8`。",
    ]
    # Markdown lives one directory above the machine-readable report files.
    return "\n".join(lines).replace(f"]({csv_path.name})", f"](reports/{csv_path.name})").replace(
        f"]({json_path.name})", f"](reports/{json_path.name})") + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--workers", type=int, default=8, choices=range(1, 9))
    args = parser.parse_args()
    root = args.root.resolve()
    paths = sorted(root.glob("assets/packs/*/voice/zh/*.m4a"))
    if len(paths) != 695:
        raise SystemExit(f"Expected 695 shipped Chinese clips, found {len(paths)}")
    before = inventory(root, paths)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(lambda p: probe(root, p), paths))
    after_paths = sorted(root.glob("assets/packs/*/voice/zh/*.m4a"))
    after = inventory(root, after_paths)
    before_by_path = {i["path"]: i for i in before}
    after_by_path = {i["path"]: i for i in after}
    for row in rows:
        row["sha256_before"] = before_by_path[row["path"]]["sha256"]
        row["sha256_after"] = after_by_path.get(row["path"], {}).get("sha256", "")
    unchanged = before == after
    if not unchanged:
        raise SystemExit("Source inventory changed during the read-only audit; no reports written")
    report = {
        "schema_version": 1, "audit_date": "2026-10-22",
        "measured_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_glob": "assets/packs/*/voice/zh/*.m4a",
        "ffprobe_version": subprocess.check_output(
            ["ffprobe", "-version"], text=True, encoding="utf-8").splitlines()[0],
        "units": {"MB": "1,000,000 bytes", "kbps": "1,000 bits/second"},
        "summary": summarize(rows),
        "estimate_method": {
            "payload": "total_stream_duration_s * target_kbps * 1000 / 8",
            "budget_size_low": "payload + measured_current_container_metadata_bytes",
            "budget_size_high": "total_current_packet_duration_s * target_kbps * 1000 / 8 + measured_current_container_metadata_bytes * 2",
            "limitation": "Sensitivity budget, not encoded file sizes or guaranteed bounds. Future container, pre-skip/padding and VBR require measurement. No quality or compatibility determination.",
        },
        "integrity": {
            "unchanged": unchanged,
            "inventory_canonical_format": "sorted relative POSIX path + TAB + bytes + TAB + sha256 + LF; UTF-8",
            "before_inventory_sha256": inventory_hash(before),
            "after_inventory_sha256": inventory_hash(after),
            "before": before, "after": after,
        },
        "clips": rows,
    }
    json_path = root / "docs/reports/voice-size-2026-10-22.json"
    csv_path = root / "docs/reports/voice-clips-2026-10-22.csv"
    md_path = root / "docs/voice-size-2026-10-22.md"
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    with csv_path.open("w", encoding="utf-8-sig", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    md_path.write_text(markdown(report, csv_path, json_path), encoding="utf-8", newline="\n")
    print(json.dumps({"summary": report["summary"], "unchanged": unchanged,
                      "inventory_sha256": inventory_hash(before)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
