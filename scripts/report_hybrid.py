"""Controlled three-character CPU reference / GPU deformation comparison."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rows = []
for backend in ("cpu", "gpu"):
    data = json.loads((root / f"artifacts/hybrid-{backend}-3.json").read_text())
    assert data["fixed_step_comparison"] and data["characters"] == 3
    assert data["accessory_rule"] == 2 and data["visual_vertices_per_character"] == 1353
    assert len(data["events"]) == 6
    row = dict(backend=backend, mean=data["mean_frame_ms"], p99=data["p99_frame_ms"],
               peak=data["max_frame_ms"], event_peak=max(e["window_max_ms"] for e in data["events"]),
               hit=max(e["call_ms"] for e in data["events"]), cloth=data["mean_cloth_script_ms"],
               mesh_builds=data["cloth_mesh_builds"])
    rows.append(row)
lines = ["# 0.2 hybrid · 3 characters", "",
         "Godot 4.6.3 / Mesa llvmpipe software renderer. Fixed 60 Hz simulation, wall-frame timings; 120 warmup + 600 samples.", "",
         "| Backend | Mean ms | p99 ms | Peak ms | Event window peak ms | Hit call peak ms | Cloth script per tick ms | Mesh builds (actor 1) |",
         "|---|---:|---:|---:|---:|---:|---:|---:|"]
for r in rows:
    lines.append("| {backend} | {mean:.3f} | {p99:.3f} | {peak:.3f} | {event_peak:.3f} | {hit:.3f} | {cloth:.3f} | {mesh_builds} |".format(**r))
lines += ["", "CPU reference rebuilds the same dense visual mesh; GPU updates only the proxy texture.",
          "Shader execution was tested on a software driver; these results do not establish real GPU performance or game FPS."]
(root / "artifacts/hybrid-summary.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
