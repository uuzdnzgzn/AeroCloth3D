"""Summarize measurements without converting container results to a hardware promise."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
reports = []
for path in sorted((root / "artifacts").glob("benchmark-*-*.json")):
    data = json.loads(path.read_text())
    events = data["events"]
    reports.append({
        "file": path.name,
        "characters": data["characters"],
        "mean_ms": round(data["mean_frame_ms"], 3),
        "p99_ms": round(data["p99_frame_ms"], 3),
        "peak_ms": round(data["max_frame_ms"], 3),
        "event_window_peak_ms": round(max(e["window_max_ms"] for e in events), 3),
        "max_hit_call_ms": round(max(e["call_ms"] for e in events), 3),
        "mean_physics_monitor_ms": round(data["mean_physics_monitor_ms"], 3),
        "mean_cloth_script_ms": round(data["mean_cloth_script_ms"], 3),
        "renderer": data["renderer"] or "headless (drawing excluded)",
    })
print(json.dumps(reports, indent=2, ensure_ascii=False))
(root / "artifacts/benchmark-summary.json").write_text(json.dumps(reports, indent=2) + "\n")
