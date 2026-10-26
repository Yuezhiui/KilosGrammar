# Human Plane — one editable 3D cloud-flight scene

**Current implementation:** Godot 4.7.2, October 26, 2026. The only authored, playable Human Plane 3D world scene is `ui/minigames/human_plane_3d_view.tscn`. Its controlling gameplay/UI wrapper remains `human_plane.tscn` because that is a separate gameplay responsibility; no duplicate 3D world is required.

## Real supplied clouds, preserved native material

The user supplied `C:\Users\Yue\Downloads\NATURE\stylize_clouds\scene.gltf`, `scene.bin`, and `license.txt`. All **three** source files were copied byte-for-byte, with matching SHA-256 hashes, into:

```text
res://Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/
    scene.gltf
    scene.bin
    license.txt
```

Godot imports the Sketchfab glTF as a PackedScene. The original contains **9 source glTF nodes, 3 source meshes, and one shared imported StandardMaterial3D named `normal`**. There are no texture files in the supplied asset package; no invented textures, recoloring or per-instance material overrides are applied. The artist-authored mesh and its material/reflection characteristics are retained.

The main view scene owns **12 `CloudFlight/CloudProps/Cloud01` through `Cloud12`** imported glTF instances. Each has its own editor-authored transform and is marked editable in the Godot scene editor. The script advances these reusable instances along Z and wraps them at the far edge, without spawning or destroying 3D nodes per frame. The source panorama `res://Components/Gameplay/Human Plane/3D/Skybox/sky_panorama.png` (1774×887) provides the 2D equirectangular sky background, retaining a 2D+3D combination. The obsolete made-up `CloudCluster.tscn` is no longer a runtime dependency.

### Mandatory cloud-model attribution (retain when distributing)

This work is based on **"stylize clouds"** ([source model](https://sketchfab.com/3d-models/stylize-clouds-32ed464f19fe4acf86723eaff08dd568)) by **ragad.sallabi** ([author](https://sketchfab.com/ragad.sallabi)), licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)** ([license](https://creativecommons.org/licenses/by/4.0/)).

The source `scene.gltf` and `scene.bin` are unmodified; multiple instances have been placed, scaled, and rotated for gameplay in `human_plane_3d_view.tscn`. This placement is a presentation change. The original `license.txt` accompanies the shipped glTF. **Do not remove this credit or `license.txt` from distributed packages.** The in-game Credits screen was deliberately removed in another task; attribution is provided in this distributable document and in the model's original license file instead.

## Single 3D scene with inline rings

There are **six real ring gates**, `CurrentRings/GateLeft`, `GateCenter`, `GateRight`, and the corresponding three under `UpcomingRings`, all directly authored inside the **one** `human_plane_3d_view.tscn`.

Each gate has editable `Torus` and `InnerGlow` mesh nodes plus a centered editable `WordLabel` (`Label3D` in Titan One). The exact existing `human_plane_3d_ring.gd` script is attached directly to each inlined gate root, preserving `set_word(word, tint, resolved, correct)` and score feedback. The torus geometry has `inner_radius=1.78`, `outer_radius=2.22`. Each ring has its **own two material subresources**, preventing colored materials from leaking between left/center/right or between active/upcoming groups. The gameplay colors remain blue, green, and orange, and dynamically updated grammar text stays inside each ring.

The old `human_plane_3d_ring.tscn` and `CloudCluster.tscn` were confirmed unreferenced across the active scenes, scripts and tests and were removed with main-agent approval. The reusable `human_plane_3d_ring.gd` script remains attached to the six inlined ring nodes. The new cloud glTF is external **source data**, not another bespoke, editable 3D world scene.

## Gameplay, airplane, and preserved old scenery

The owner of the airplane's scale/position/camera is the prime gameplay agent. This cloud/ring integration **does not adjust `PlayerRig`, `RedPlane`, the camera or their transforms**, or change importer units. At the final validation pass, the separate scale owner had increased the FBX import normalization so the 22-mesh plane's actual width measured **3.0693 world units**, projecting to roughly **134×69 pixels at 1280×720**, **168×86 at 1600×900**, and **201×103 at 1920×1080**. The actual red plane appeared in GPU screenshots at all three sizes (red-dominant pixels counted as 1,843 / 2,944 / 4,303).

The authoritative `HumanPlane.gd` scoring still decides which ring is hit. The view maps the currently accepted body-X lane centers to its three 3D ring positions without another translation smoothing delay; only airplane banking is smoothed independently. Real-time render interpolation, cumulative correct-answer speed boost, ring score-plane depth, and pause behavior are preserved. No webcam/calibration, gameplay parent, hitboxes, database, or scoring scripts were edited as part of this change.

The old `Terrain` and `Scenery` roots stay hidden but are **not deleted**. The **24 editor-positioned original mountain nodes and exact transforms** remain intact (comparison fingerprint `720FD7E71F6842175416265BEAE271AAF8D0911E4095E689DB76E4AB2FC1F531`); Road008A and Grass004 PBR terrain, original NATURE grass MultiMesh batches, trees and rocks are also preserved.

## Validation

- Source glTF, bin and license: **3/3** byte-identical SHA-256 matches; imported by Godot without source geometry or material replacement.
- Single-world inlining: **12** independently editable glTF cloud instances, **6** direct scripted ring roots, **12** independent colored ring material resources; no active `CloudCluster.tscn` or `human_plane_3d_ring.tscn` PackedScene reference.
- `tools/test_human_plane_cloud_flight.gd`: **75/75** focused inline glTF/cloud checks passed after deletion of the orphan 3D scenes.
- `tools/test_human_plane_3d_scale_flow.gd`: **70/70** focused headless checks and **148/148** GPU checks passed after the plane-size update; includes near/distant 1280×720, 1600×900, 1920×1080 actual GPU projections. Actual red pixels were measured from those GPU images independently.
- Existing motion/performance **377/377** and gameplay interaction **120/120** checks passed; real GPU visual workflow produced **6/6** gameplay near/distant captures.
- Godot editor import completed. The editor's own restored workspace occasionally tried to load files from the previously deleted Credits screen; that unrelated editor-state issue was not modified here.

Screenshots and one-off diagnostics were kept in Godot's `user://` runtime output; no temporary QA PNGs are retained as project assets.
