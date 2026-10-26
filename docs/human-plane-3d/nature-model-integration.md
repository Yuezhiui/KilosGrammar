# Human Plane NATURE grass and mountain integration

Verified in the shared Godot 4.7.2 project on 2026-10-26. This integrates the **original supplied NATURE models** into Human Plane's real SubViewport 3D scenery. The webcam/pose input, gameplay answer-line scoring and 3D ring animation live in separate components and were not changed.

## Source assets and provenance

All nine source files were copied from `C:\Users\Yue\Downloads\NATURE` into the corresponding project-relative tree under `res://Components/Gameplay/Human Plane/3D/`. Each copied file had its SHA-256 independently compared against the original and **all nine hashes matched**. Godot's import sidecars are generated separately; the FBX, glTF, binary, texture and license source bytes were preserved.

| Folder | Files | Source information |
| --- | --- | --- |
| `grass-green/source/` | `Grass_green.fbx` (FBX binary 7400, 65,484 bytes) | Godot imported a single grass MeshInstance3D with 14 quad surfaces, 56 source vertices and 28 triangles. The source scene also contains a camera and light not needed for vegetation rendering. |
| `grass-green/textures/` | `Grass_green.png` (1024×685), `Normal_grass.png` (1024×693) | Original diffuse/alpha and normal textures. The diffuse PNG has actual alpha (pixel 0,0 transparent). |
| `mountain/` | `scene.gltf`, `scene.bin`, `license.txt` | Sketchfab glTF 2.0, one imported mesh with 16,576 vertices, 16,638 indices / 5,546 triangles, one material. The imported source model's hierarchy resolves its axis orientation and ~9.3897 built-in scale. |
| `mountain/textures/` | `Default_OBJ_baseColor.jpeg`, `Default_OBJ_metallicRoughness.png`, `Default_OBJ_normal.png` | Original 2048×2048 PBR textures retained at their supplied resolution. |

### Copyright and release restriction

The supplied mountain license is **Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0)**, not a permissive commercial license. It names **“Mountain” by dario scaramuzza**, [original model](https://sketchfab.com/3d-models/mountain-d7829c144aee4b6fa09e66e9d1891913), [author](https://sketchfab.com/dariotolkien) and [license](https://creativecommons.org/licenses/by-nc-nd/4.0/). It requires credit, forbids commercial use and disallows redistribution of adapted versions. The game currently renders instances of the original glTF scene without modifying that model. **Do not ship this asset in a commercial product or distribute modified copies without additional permission from the rights holder.** The source `mountain/license.txt` is retained for attribution.

No separate license or origin information was included in the provided `grass-green/` folder. Its distribution rights must be established before releasing a build that bundles it.

## Rendering arrangement

- `ui/minigames/human_plane_3d_foliage.gd`: loads the actual imported grass FBX geometry, applies its authored transform and UV mapping, and combines the 14 quads into **one in-memory ArrayMesh surface**. One alpha-scissored, double-sided `StandardMaterial3D` samples the original albedo and normal textures. No source FBX or texture edits occur. Four reusable 45-m scenery bands each render **340 NATURE grass patches** in one `MultiMeshInstance3D` draw batch: **1,360 live grass instances**, covering the forest ground and smaller low clumps on the runway. Existing **120 procedurally batched forest trees** plus the separately instanced NATURE tree FBXs remain.
- `ui/minigames/human_plane_3d_mountains.gd`: uses the original `scene.gltf` PackedScene instances authored under `Terrain/Mountains`. The Godot editor now contains **24 artist-positioned instances** with unique transforms, which the script leaves unchanged. Imported scene meshes and textures are reused; no procedural peaks remain. Instance shadows are disabled and visibility distance is capped. The original Godot `.gltf.import` has `meshes/generate_lods=true`.
- `ui/minigames/human_plane_3d_view.gd/.tscn`: continues to recycle scenery nodes without allocating during gameplay and retains blue/green/orange ring materials and render interpolation. Terrain, model scales and material settings remain editable. Grass visibility distance is approximately 108 units; procedural trees 148; mountain meshes 235. The camera's far plane is 240.

## GPU QA and performance

Hardware: **NVIDIA GeForce RTX 3050 6GB Laptop GPU**, OpenGL 3.3 Compatibility renderer, Godot 4.7.2. The 3D visual QA produced **6/6** screenshots at 1280×720, 1600×900, and 1920×1080 (near and distant phases); the user-authored 24-mountain layout was used for the final pass. Images were inspected, then temporary QA PNGs/imports were removed from `docs/` so that production Godot artwork stays exclusively within `Components/`; fresh screenshots can be captured using `tools/test_human_plane_3d_visual.gd` in `user://`. Inspection confirmed grass uses real detailed blades, the mountain meshes frame the runway, and the ring words and original HUD remain legible.

The additional **uncapped, no-VSync scene-only renderer** sampled 100 actual GPU-presented frames per condition and resolution; it paused gameplay logic and used no webcam, YOLO inference, or database. Values depend on scheduling, warm-up and driver and are useful only for a relative isolated render smoke check:

| Resolution | NATURE enabled FPS | NATURE hidden FPS | Video memory reported (MB) | Draw calls enabled / hidden |
| --- | ---: | ---: | ---: | ---: |
| 1280×720 | 279.9 | 398.1 | 87.7 | 82 / 55 |
| 1600×900 | 753.1 | 802.3 | 99.8 | 82 / 55 |
| 1920×1080 | 599.9 | 435.9 | 109.5 | 82 / 55 |

Godot engine static memory was 77.1–77.4 MB and 307 scene nodes/objects were reported in these samples. Video memory did not change when scenery was hidden, as hiding nodes does **not unload** the texture assets; the figures are not the incremental memory cost of the models. The enabled FPS figures were all above 60 in this isolated test, but this is **not proof of 60 FPS with live YOLO/USB camera inference**.

Additional headless regression on the **latest** 24-mountain editor scene passed the 3D motion/performance suite (**377/377**), world/assets suite (**155/155**), 3D interactions suite (**120/120**), and Human Plane continuous-flight suite (**1,212/1,212**), for **1,864/1,864** checks. The Godot editor parsed the project successfully after temporary benchmarking tools were removed. The 3D visual test passed its six planned GPU captures.
