#!/usr/bin/env python3
"""Build a separate ten-clip AAC audition. Never writes application assets.

Requires ffmpeg/ffprobe and fdkaac. For mono HE-v1, apply the adjacent
fdkaac-mono-he-signaling.patch to the pinned fdkaac source before building.
All file sizes include the M4A container; MB/kB use decimal units.
"""

import argparse
import csv
import hashlib
import html
import json
import shutil
import subprocess
import tempfile
import wave
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SELECTION = [
    ("_common", "n.1", "最短 / 数字"),
    ("_common", "n.10", "数字"),
    ("_common", "n.60", "两位数"),
    ("h-crunch", "name", "最短动作名"),
    ("n-wide-fold", "name", "最长动作名"),
    ("h-band-hip-ir", "name", "多音节动作名"),
    ("h-incline-pushup", "rest", "最长提示"),
    ("h-good-morning", "rest", "第二长提示"),
    ("h-9090-liftoff", "side_switch", "换侧提示"),
    ("hip-flexors-A", "rest", "提示中含数字"),
]
LABELS = {"original": "原件", "lc32": "AAC-LC 32kbps", "he32": "HE-AAC v1 32kbps"}


def run(args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True,
                          text=True, encoding="utf-8", errors="replace").stdout


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    paths = sorted(root.glob("assets/packs/*/voice/zh/*.m4a"))
    return [{"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size,
             "sha256": sha(p)} for p in paths]


def inventory_hash(items):
    canonical = "".join(f"{i['path']}\t{i['bytes']}\t{i['sha256']}\n" for i in items)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def probe(ffprobe, path):
    data = json.loads(run([ffprobe, "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,profile,channels,sample_rate,duration,bit_rate:"
        "format=duration,size:packet=size", "-of", "json", path]))
    stream = data["streams"][0]
    size = path.stat().st_size
    payload = sum(int(p["size"]) for p in data["packets"])
    return {"codec": stream["codec_name"], "profile": stream["profile"],
            "channels": int(stream["channels"]), "sample_rate_hz": int(stream["sample_rate"]),
            "duration_s": float(stream.get("duration", data["format"]["duration"])),
            "stream_bit_rate_bps": int(stream.get("bit_rate", 0)),
            "bytes": size, "audio_packet_bytes": payload, "container_bytes": size - payload,
            "sha256": sha(path)}


def decode(ffmpeg, source, output, rate=None):
    # No silence trimming, normalization, denoising, speed or pitch changes.
    args = [ffmpeg, "-v", "error", "-xerror", "-nostdin", "-n", "-i", source,
            "-map", "0:a:0", "-vn", "-c:a", "pcm_s16le"]
    if rate:
        args += ["-ar", str(rate)]
    run(args + [output])
    with wave.open(str(output), "rb") as wav:
        if wav.getnchannels() != 1:
            raise ValueError(f"Decoded audio must be mono: {source}")
        return wav.getnframes() / wav.getframerate()


def render(output, report):
    totals = report["totals_bytes"]
    rows = []
    for clip in report["clips"]:
        cells = []
        for key in LABELS:
            v = clip["variants"][key]
            delta = 100 * (1 - v["bytes"] / clip["variants"]["original"]["bytes"])
            cells.append(f'<td><audio controls preload="none" src="{html.escape(v["preview"])}"></audio>'
                         f'<p>{v["bytes"]:,} B · {v["bytes"]/1000:.2f} kB'
                         + (f' · 节省 {delta:.1f}%' if key != "original" else '')
                         + f'</p><a href="{html.escape(v["file"])}" download>下载 M4A</a></td>')
        rows.append(f'<tr><th scope="row">{clip["number"]:02d} · {html.escape(clip["category"])}'
                    f'<p>{html.escape(clip["text"])}</p><small>{clip["variants"]["original"]["duration_s"]:.2f} 秒'
                    f' · {html.escape(clip["pack"] + "/" + clip["line"])}</small></th>{"".join(cells)}</tr>')
    total_cells = ''.join(f'<td>{totals[k]:,} B<br>{totals[k]/1000:.2f} kB'
                         + (f'<br>节省 {100*(1-totals[k]/totals["original"]):.1f}%' if k != 'original' else '')
                         + '</td>' for k in LABELS)
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>SmartFit 语音试听 · AAC 32kbps</title>
<style>body{font:16px/1.6 system-ui,sans-serif;background:#f5f7fa;color:#172435;margin:0;padding:28px}
main{max-width:1400px;margin:auto}h1{font-size:28px}p{margin:8px 0}table{border-collapse:collapse;width:100%;background:white}
th,td{text-align:left;padding:18px;border-bottom:1px solid #dce3ec;vertical-align:top}thead,tfoot{background:#e9eff7}
th{max-width:350px}td{min-width:240px}audio{width:100%;max-width:280px}small{font-weight:normal;color:#566476}
.table{overflow:auto;border:1px solid #dce3ec;border-radius:14px}a{color:#165aca}section{padding:16px 0}
.note{background:#e7f1ff;padding:16px;border-radius:12px}</style><main>
<h1>SmartFit 语音试听 · AAC 32kbps</h1>
<p>10 条原件与两种单声道编码逐条对照。LC：22.05kHz；HE-AAC v1：44.1kHz（核心 22.05kHz）。</p>
<p class="note">试听播放器使用从对应 M4A 完整解码出的 PCM WAV，避免浏览器不支持 HE-AAC；
“下载 M4A”取得实际压缩样件。下表体积只统计 M4A，含文件封装，不计试听 WAV。</p>
<section>请重点听数字起音、动作名辨识度、长提示的齿音和尾音。每次只播放一条，音量一致。
试听后回复“选 LC”或“选 HE”；收到选择后再处理全部 695 条。</section>
<div class="table"><table><thead><tr><th>内容</th><th>原件 · AAC-LC ~64kbps</th><th>AAC-LC · 32kbps</th>
<th>HE-AAC v1 · 32kbps</th></tr></thead><tbody>''' + ''.join(rows) + '''</tbody><tfoot><tr><th>10 条合计</th>''' + total_cells + '''</tr></tfoot></table></div>
<section>原件全部按字节复制。未调整响度、语速或音调。所有样件通过本机 FFmpeg 解码检查；
Android / iOS 实际播放验收和真机 20 分钟训练尚未执行。生产素材、字体、清单均未修改。</section>
<a href="comparison.csv">逐条体积 CSV</a> · <a href="manifest.json">参数与 SHA-256 清单</a>
<script>document.querySelectorAll('audio').forEach(a=>a.addEventListener('play',()=>document.querySelectorAll('audio').forEach(b=>{if(a!==b)b.pause()})))</script>
</main></html>'''
    (output / "index.html").write_text(page, encoding="utf-8")
    lines = ["# AAC 32kbps 试听", "", "打开 index.html，逐行比较原件、LC 和 HE。",
             "所有原件和 M4A 样件都在本目录；previews/ 中的 WAV 只供浏览器试听。",
             "", "| 10 条合计 | 实际 M4A 字节 | 节省 |", "|---|---:|---:|"]
    for key, label in LABELS.items():
        lines.append(f"| {label} | {totals[key]:,} | {100*(1-totals[key]/totals['original']):.2f}% |")
    lines += ["", "仅制作这 10 条，等待开哥选择 LC 或 HE 后才转换全部 695 条。",
              "原件 SHA-256 与源文件逐一相同；全部 695 条源语音转换前后哈希一致。",
              "LC 22.05kHz 单声道、HE v1 44.1kHz 单声道，FDK AAC 2.0.3，目标 CBR 32,000 bit/s。",
              "HE 的 ASC 显式声明 PS=false；不使用 HE v2/Opus。见项目 tools/voice/fdkaac-mono-he-signaling.patch。",
              "两种编码均启用 afterburner；M4A 同时带 iTunSMPB 和 ISO gapless 信息。",
              "保持源解码的全部 PCM，不做裁剪或音量归一。源 AAC 的末帧填充可能导致转换后声明时长略增，详见 manifest.json。",
              "播放控件使用各 M4A 解码的 PCM WAV，体积对比不计 WAV。不能据此声称 Android/iOS 已验收。",
              "", "字体跳过进一步子集：当前字体已经是 GB2312 加应用字符的子集，4,110,060 字节。",
              "按静态文案再裁会删除聊天动态内容可能用到的字（咖啡、熬夜、焦虑等），不满足不影响聊天的前提。",
              "", "未覆盖素材、未更新生产清单、未合并或推送。真机 20 分钟训练留待有设备。"]
    (output / "README.md").write_text('\n'.join(lines) + '\n', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fdkaac", type=Path, required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    if output.is_relative_to(root) or root.is_relative_to(output):
        parser.error("Output must be separate from the application checkout")
    if output.exists():
        parser.error("Output already exists; refusing to overwrite")
    before = inventory(root)
    if len(before) != 695:
        raise ValueError(f"Expected 695 source voice clips, got {len(before)}")
    report = {"schema_version": 1, "created_utc": datetime.now(timezone.utc).isoformat(),
              "source_root": str(root), "target_bitrate_bps": 32000,
              "tools": {"ffmpeg": run([args.ffmpeg, "-version"]).splitlines()[0],
                        "fdkaac_path": str(args.fdkaac.resolve()), "fdkaac_sha256": sha(args.fdkaac),
                        "fdkaac_upstream_commit": "cdfd8a555c31ffa7d0c2e303e84bb197ba518ed8",
                        "fdk_aac_version": "2.0.3", "mono_he_asc": "explicit PS=false; adjacent patch"},
              "status": "awaiting_profile_selection", "clips": []}
    output.mkdir(parents=True, exist_ok=False)
    (output / "previews").mkdir()
    temp_parent = root / ".buildlog" / "voice-tools"
    temp_parent.mkdir(parents=True, exist_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix="audition-pcm-", dir=temp_parent) as temp:
            temp = Path(temp)
            for number, (pack, line, category) in enumerate(SELECTION, 1):
                source = root / "assets" / "packs" / pack / "voice" / "zh" / f"{line}.m4a"
                metadata = json.loads((root / "assets" / "packs" / pack / "pack.json").read_text(encoding="utf-8"))
                text = next(item["text"]["zh"] for item in metadata["voice"]["lines"] if item["id"] == line)
                stem = f"{number:02d}_{pack}_{line}"
                clip = {"number": number, "pack": pack, "line": line, "category": category,
                        "text": text, "source": source.relative_to(root).as_posix(), "variants": {}}
                original = output / f"{stem}_original.m4a"
                shutil.copyfile(source, original)
                assert sha(source) == sha(original)
                for key, profile, rate in [("original", None, None), ("lc32", 2, 22050), ("he32", 5, 44100)]:
                    target = original if key == "original" else output / f"{stem}_{key}.m4a"
                    if profile:
                        pcm = temp / f"{stem}_{key}.wav"
                        decode(args.ffmpeg, original, pcm, rate)
                        run([args.fdkaac, "-S", "-p", profile, "-b", 32000, "-m", 0,
                             "-a", 1, "-G", 2, "--moov-before-mdat", "-o", target, pcm])
                    info = probe(args.ffprobe, target)
                    expected_profile = "HE-AAC" if key == "he32" else "LC"
                    if info["codec"] != "aac" or info["profile"] != expected_profile or info["channels"] != 1:
                        raise ValueError(f"Unexpected codec/profile/channels: {target}: {info}")
                    if rate and info["sample_rate_hz"] != rate:
                        raise ValueError(f"Unexpected output rate: {target}")
                    preview = output / "previews" / f"{stem}_{key}.wav"
                    info["decoded_duration_s"] = decode(args.ffmpeg, target, preview)
                    info["file"] = target.name
                    info["preview"] = preview.relative_to(output).as_posix()
                    clip["variants"][key] = info
                report["clips"].append(clip)
        report["totals_bytes"] = {key: sum(c["variants"][key]["bytes"] for c in report["clips"]) for key in LABELS}
        report["integrity"] = {"voice_count": len(before), "before_inventory_sha256": inventory_hash(before),
                               "original_copies_verified": True, "all_30_m4a_decode_verified": True}
        render(output, report)
        with (output / "comparison.csv").open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["number", "text", "source", "duration_s", "original_bytes", "lc32_bytes", "he32_bytes", "lc_saving_pct", "he_saving_pct"])
            for c in report["clips"]:
                v = c["variants"]
                writer.writerow([c["number"], c["text"], c["source"], v["original"]["duration_s"],
                                 v["original"]["bytes"], v["lc32"]["bytes"], v["he32"]["bytes"],
                                 round(100*(1-v["lc32"]["bytes"]/v["original"]["bytes"]), 2),
                                 round(100*(1-v["he32"]["bytes"]/v["original"]["bytes"]), 2)])
    finally:
        after = inventory(root)
        if before != after:
            raise RuntimeError("SOURCE VOICE INVENTORY CHANGED")
    report["integrity"].update(after_inventory_sha256=inventory_hash(after), source_unchanged=True)
    (output / "manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding="utf-8")
    print(json.dumps({"output": str(output), "totals_bytes": report["totals_bytes"], "integrity": report["integrity"]}))


if __name__ == "__main__":
    main()
