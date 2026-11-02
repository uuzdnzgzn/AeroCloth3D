"""Optional export plot; needs matplotlib. Runtime and validation do not."""
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[1]
plt.style.use("dark_background")
fig, axes = plt.subplots(2, 1, figsize=(12, 8), constrained_layout=True)
for axis, mode, title in zip(axes, ["headless", "rendered"],
                             ["Headless: drawing excluded", "Rendered: Mesa llvmpipe software renderer"]):
    for count, color in [(1, "#91a9ce"), (3, "#48dfca")]:
        data = json.loads((root / f"artifacts/benchmark-{mode}-{count}.json").read_text())
        axis.plot(range(121, 721), data["raw_frame_ms"], linewidth=.9, color=color,
                  label=f"{count} character(s), mean {data['mean_frame_ms']:.2f} ms, p99 {data['p99_frame_ms']:.2f} ms")
        if count == 3:
            for event in data["events"]:
                axis.axvline(event["frame"], color="#ffbb70" if event["kind"] == "first_break" else "#fa7182",
                             alpha=.5, linestyle="--", linewidth=.9)
    axis.set_title(title, loc="left", fontsize=12)
    axis.set_ylabel("Wall frame time (ms)")
    axis.set_xlabel("Frame after launch (120-frame warmup excluded)")
    axis.grid(alpha=.16)
    axis.legend(fontsize=9, loc="upper left")
fig.suptitle("AeroCloth3D 0.1-rebuild · Godot 4.6.3 · container, not target hardware", fontsize=15)
fig.text(.5, -.02, "Orange: first connection break · Red: final connection detach · 3 characters hit in the same process callback",
         ha="center", fontsize=10)
for extension in ["png", "svg"]:
    fig.savefig(root / f"artifacts/frame-times.{extension}", dpi=160, bbox_inches="tight")
