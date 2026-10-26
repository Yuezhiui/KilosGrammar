# Human Plane 3D — real OpenGL performance and lifecycle QA

Measured 2026-10-26 on Windows with **Godot 4.7.2 stable**, **NVIDIA GeForce RTX 3050 6 GB Laptop GPU**, NVIDIA OpenGL **3.3 / driver 617.42**, Compatibility renderer (`opengl3`). The test mounts the actual `ui/minigames/human_plane.tscn`, keeps the native HUD and 3D SubViewport visible, advances scrolling scenery, and renders the real toy plane and three word rings. It **does not** launch camera/YOLO, game wrapper, or database calls. Results describe 3D rendering headroom on this GPU, not complete class-time performance with pose inference running.

## Reproduction

From `/kilos-grammar` in Windows PowerShell:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only --script res://tools/test_human_plane_3d_performance.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/test_human_plane_3d_performance.gd -- --seconds=10 --cycles=12 --warmup=90
```

This is a visible-window **real OpenGL3** benchmark; do not add `--headless` to the second command. It disables VSync and any FPS cap, warms the scene for 90 rendered frames, and samples 10 seconds of `RenderingServer.frame_post_draw` intervals at each window resolution. It freezes the authoritative quiz progress during samples while keeping the 3D scenery animation active. Then it repeatedly mounts and frees the game and exercises correct, wrong, missed voice recordings, pause and resume. Command-line options: `--seconds=1..60`, `--cycles=4..100`, `--warmup=3..300`. `PERF|...` lines are machine-parseable.

## Measured results — final 10-second run

| Metric | 1280 × 720 | 1920 × 1080 |
| --- | ---: | ---: |
| Frames sampled | 3,324 | 2,716 |
| Average interval between completed draw signals | **3.009 ms** | **3.682 ms** |
| 95th percentile frame interval | **4.877 ms** | **5.842 ms** |
| Observed uncapped draw-signal throughput | **332.34/s** | **271.59/s** |
| Average draw calls per rendered frame | 57.33 | 57.45 |
| Average `Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME` | 54,942 | 55,008 |
| Average rendered objects per frame | 77.33 | 77.45 |
| Renderer-reported video memory at end of sample | 84.99 MiB | 103.03 MiB |

Both runs: **186 live game scene nodes**, of which 105 are inside `FlightWorld`; **41 `MeshInstance3D` nodes**, **12 `MultiMeshInstance3D` nodes**, **1,000 GPU-instanced trees/grass elements**. Based on triangle-array indices/vertices, the mounted mesh geometry has an estimated **80,972-triangle full-scene budget**, including **21,800 triangles from MultiMesh instances**. This is a static budget across all mesh nodes, *before* frustum/distance culling; it is not the number of triangles actually rendered per frame. The Godot `RENDER_TOTAL_PRIMITIVES_IN_FRAME` monitor counts submitted vertices/indices, including additional passes, and must not be mislabeled as triangles.

The `Performance.TIME_PROCESS` monitor was also sampled, but its reports update at a coarse interval, so the values do not represent independent per-frame CPU durations or isolated GPU timing. Frame-post-draw wall intervals similarly measure render-loop throughput and scheduling, **not a GPU timestamp query**. Frame times vary with OS scheduling, GPU power mode, warm caches, other running programs, and real camera/YOLO workloads. The achieved throughput in this artificial uncapped test should not be used as a promise of 270+ FPS during gameplay.

## Audio and cleanup under real OpenGL

- **12-cycle normal run: PASS** (zero assertions failed). Each cycle loaded correct and wrong audio clips, paused and verified the voice player stopped and released the stream, resumed and loaded a missed clip, then freed the entire scene. After freeing, baseline was **3 scene-tree nodes**, **0 orphan nodes**. All 12 cycles released the game and its 3D SubViewport/voice player.
- **40-cycle extended run: PASS** (`--seconds=1 --cycles=40 --warmup=3`). Root/node count stayed **3**, orphan nodes stayed **0**; after startup/cache warmup, object counts fluctuated between approximately **1,661 and 1,667** from cycle 13 through 39, ending at **1,661**. The initial apparent `OBJECT_COUNT` rise (+32 over early warmup in the 12-cycle run) did **not** continue unbounded in 40 cycles. This supports bounded resource caching in the tested scenario; it is not an exhaustive native heap/VRAM leak analysis.
- No Godot ObjectDB/orphan-node leak warnings were observed in the full or extended runs. The script explicitly tests `AudioStreamPlayer` cleanup with real playback and a display-backed driver, in addition to scene node reclamation.

## Safe tuning guidance

1. **Keep the current segmented `MultiMesh` approach.** Four forest strips contain 12 MultiMesh render nodes and 1,000 instances, which avoids one draw call per individual blade/tree. MultiMesh culls by group rather than each instance; retaining reasonably small strips and distance limits is useful. Do not convert all foliage into one world-sized MultiMesh: that makes culling less selective. Godot 4.7 [MultiMesh optimization guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html).
2. **Measure on the actual school computer with the body tracker active.** The RTX-only synthetic draw benchmark exceeds the 60 FPS frame budget, but YOLO inference, camera conversion, audio mixing, and other scenes were intentionally excluded. Measure 1% lows/95th percentile frame times while a student moves and steering updates; isolate GPU vs CPU inference before changing art complexity.
3. **For integrated GPUs, tune cheaper knobs first after measuring.** Reduce 3D SubViewport resolution while retaining the 2D HUD's native size, then compare shadow cost and imported tree mesh LOD/visibility range. Keep real-time shadow casters limited and distant foliage low-poly. Adjust only when tests on target hardware show dropped frames. Godot [3D optimization guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html).
4. **Keep scenery pooled and material count bounded.** Procedural mountain ridges and forest strips currently create meshes once in `_ready()`; `_process()` moves/recycles the existing nodes. The gameplay sky now uses a 2048×1024 local derivative of the supplied 6K panorama, so it uploads around one-ninth as many source pixels; the 6K original is retained as source art. On weak integrated graphics, profile SubViewport render scale and native 3D texture memory before lowering visual quality further.

No reliable numerical **before** benchmark exists for the earlier empty/FBX-only version, and production was changing concurrently while this worker developed the test. Consequently no fabricated performance delta or optimized-vs-baseline percentage is reported. The renderer metrics above come from the finished version present at the time of capture. All work performed here is isolated to the benchmark script and this report.
