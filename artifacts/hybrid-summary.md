# 0.2 hybrid · 3 characters

Godot 4.6.3 / Mesa llvmpipe software renderer. Fixed 60 Hz simulation, wall-frame timings; 120 warmup + 600 samples.

| Backend | Mean ms | p99 ms | Peak ms | Event window peak ms | Hit call peak ms | Cloth script per tick ms | Mesh builds (actor 1) |
|---|---:|---:|---:|---:|---:|---:|---:|
| cpu | 111.024 | 155.755 | 250.078 | 132.949 | 2.850 | 12.172 | 725 |
| gpu | 104.746 | 134.367 | 231.569 | 134.367 | 3.030 | 2.745 | 1 |

CPU reference rebuilds the same dense visual mesh; GPU updates only the proxy texture.
Shader execution was tested on a software driver; these results do not establish real GPU performance or game FPS.
