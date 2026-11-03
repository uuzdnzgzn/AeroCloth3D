# 0.3 Authoring verification and measurements

Godot 4.6.3 / Blender 4.3.2. Actual GL uses Mesa llvmpipe software rendering; target GPU and 60 FPS are not certified.

- validation-headless.log: 626 checks, 0 failures (render suites repeat some logical checks).
- validation-render.log: 146 checks, 0 failures (render suites repeat some logical checks).
- Blender bridge: 40 checks, 0 failures.
- Addon-only clean editor import, exported scene and separate gameplay process passed.

| Pipeline | Mean frame ms | p99 ms | Max frame ms | Max six-hit call ms | Max cosmetic publish ms |
|---|---:|---:|---:|---:|---:|
| baseline / headless | 11.559 | 168.545 | 480.922 | 456.937 | synchronous |
| baseline / rendered | 37.227 | 231.701 | 528.569 | 460.515 | synchronous |
| benchmark / headless | 6.900 | 11.714 | 15.801 | 7.307 | 169.844 |
| benchmark / rendered | 34.594 | 73.004 | 85.356 | 12.909 | 329.885 |

120 warm-up frames + 600 real-time wall frames; 3 characters, 12 events, 6 item hits per event.
The current path includes prepared model changes, layer release, cloth/rigid movement, body proxies, GPU height normals and worker mask publication.
The baseline captures the earlier synchronous mask/normal rebuild bottleneck. Current body proxies and async scheduling differ; this is an engineering comparison, not a hardware FPS claim.
Gameplay state and physics change synchronously. Cosmetic mask publication is delayed; the latency column is the longest wait until all 6 affected item masks published.
Headless excludes drawing. Rendered results include the software driver's CPU load. No event-spike or target-hardware guarantee is implied.
