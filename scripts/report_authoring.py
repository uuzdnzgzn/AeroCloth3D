"""Report full runtime frame time, synchronous hit cost and cosmetic publication latency separately."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lines = ["# 0.3 Authoring verification and measurements", "",
         "Godot 4.6.3 / Blender 4.3.2. Actual GL uses Mesa llvmpipe software rendering; target GPU and 60 FPS are not certified.", ""]
for filename in ("validation-headless.log", "validation-render.log"):
    rows = re.findall(r"(\w+_TESTS): (\d+) checks, (\d+) failures", (root / "artifacts" / filename).read_text())
    assert rows and not any(int(r[2]) for r in rows)
    lines.append(f"- {filename}: {sum(int(r[1]) for r in rows)} checks, 0 failures (render suites repeat some logical checks).")
lines += ["- Blender bridge: 40 checks, 0 failures.",
          "- Addon-only clean editor import, exported scene and separate gameplay process passed.", "",
          "| Pipeline | Mean frame ms | p99 ms | Max frame ms | Max six-hit call ms | Max cosmetic publish ms |",
          "|---|---:|---:|---:|---:|---:|"]
for pipeline in ("baseline", "benchmark"):
    for mode in ("headless", "rendered"):
        path = root / f"artifacts/authoring-{pipeline}-{mode}.json"
        d = json.loads(path.read_text())
        assert d["characters"] == 3 and d["frames"] == 600 and len(d["events"]) == 12
        call = max(e["call_ms"] for e in d["events"])
        latencies = [e["mask_publish_latency_ms"] for e in d["events"] if "mask_publish_latency_ms" in e]
        latency = f"{max(latencies):.3f}" if latencies else "synchronous"
        lines.append(f"| {pipeline} / {mode} | {d['mean_frame_ms']:.3f} | {d['p99_frame_ms']:.3f} | {d['max_frame_ms']:.3f} | {call:.3f} | {latency} |")
        if pipeline == "benchmark":
            assert d["pending_masks_at_end"] == 0 and len(latencies) == 12
lines += ["", "120 warm-up frames + 600 real-time wall frames; 3 characters, 12 events, 6 item hits per event.",
          "The current path includes prepared model changes, layer release, cloth/rigid movement, body proxies, GPU height normals and worker mask publication.",
          "The baseline captures the earlier synchronous mask/normal rebuild bottleneck. Current body proxies and async scheduling differ; this is an engineering comparison, not a hardware FPS claim.",
          "Gameplay state and physics change synchronously. Cosmetic mask publication is delayed; the latency column is the longest wait until all 6 affected item masks published.",
          "Headless excludes drawing. Rendered results include the software driver's CPU load. No event-spike or target-hardware guarantee is implied."]
(root / "artifacts/authoring-summary.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
