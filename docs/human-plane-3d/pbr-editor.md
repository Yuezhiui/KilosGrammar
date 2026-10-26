# Human Plane 3D — PBR materials and editable grass

Godot 4.7.2 project integration (2026-10-26). This file describes the completed reusable assets and the scene hookup expected in `ui/minigames/human_plane_3d_view.tscn`. The 3D scene is edited by another workstream; preserve its user-positioned plane, rings, trees and 24 mountain transforms.

## Source and license

The supplied map sets are ambientCG [Road 008 A](https://ambientcg.com/view?id=Road008A) and [Grass 004](https://ambientcg.com/view?id=Grass004), 1K-PNG. The original texture files are under `C:\Users\Yue\Downloads\NATURE\PBR\Road008A_1K-PNG\` and `...\Grass004_1K-PNG\`. Official [ambientCG licensing](https://docs.ambientcg.com/license/) is **Creative Commons CC0 1.0** and permits game use, modifications and commercial redistribution without mandatory attribution. The downloaded folders do not themselves include a separate LICENSE file; the asset names match ambientCG's published names. This CC0 status **does not** change the existing mountain model's restrictive CC BY-NC-ND license or establish rights to the separate grass-green FBX.

Only four original image maps per material were copied, byte-for-byte (8/8 SHA-256 matches), to:

- `res://Components/Gameplay/Human Plane/3D/pbr/road008a/` — `Road008A_1K-PNG_Color.png`, `_NormalGL.png`, `_Roughness.png`, `_AmbientOcclusion.png`.
- `res://Components/Gameplay/Human Plane/3D/pbr/grass004/` — `Grass004_1K-PNG_Color.png`, `_NormalGL.png`, `_Roughness.png`, `_AmbientOcclusion.png`.

Original `NormalDX` files and height/displacement maps were intentionally omitted. Godot expects the OpenGL Y+ normal convention, and enabling height displacement on broad flat surfaces would add cost without necessary geometry. All source textures remain untouched in Downloads.

## Editable materials

Two `StandardMaterial3D` resources can be opened and edited directly in the Godot Inspector:

| Resource path under `res://Components/Gameplay/Human Plane/3D/pbr/` | Assign to | UV1 repeat scale | UV tile meaning |
| --- | --- | --- | --- |
| `road008a_path.tres` | `Terrain/FlyingPath.material_override` | `(10, 116, 1)` | On the current 21 m × 260 m route, ~2.1 m × 2.24 m repeating texture. |
| `grass004_ground.tres` | `Terrain/Grass.material_override` | `(180, 190, 1)` | On the current 250 m × 270 m floor, ~1.39 m × 1.42 m repeating texture, matching Grass004's stated ~1.4 m reference. |

Both resources link the albedo, NormalGL, grayscale roughness, and AO maps. Roughness/AO use Godot's grayscale channel setting. Textures use mipmapped filtering for distant samples. They do **not** require shader code or runtime texture construction. Keep the existing editable `BoxMesh` geometry and camera; fine-tune the repeat values in the material inspector if the floor dimensions change.

## Real FBX grass editing and batching

`res://Components/Gameplay/Human Plane/3D/pbr/nature_grass_clump_mesh.tres` is a *derived, local, Godot ArrayMesh* representing all 14 real quad surfaces of the supplied `grass-green/source/Grass_green.fbx` merged into one surface while retaining geometry/UVs. Its original FBX/textures remain byte-exact and are still included under `Components/Gameplay/Human Plane/3D/grass-green/`. The authoring camera/light from that FBX are not instanced.

Four serializable `MultiMesh` resources are available at `pbr/nature_grass_band_a.tres`, `..._b.tres`, `..._c.tres`, and `..._d.tres`. Each stores **340 nonidentical transforms/colors** with a finite culling AABB (4 × 340 = **1,360 real FBX grass clumps**). They reference the same extracted ArrayMesh; the source-material texture stays the existing `Grass_green.png` + `Normal_grass.png` on the grass drawing nodes. The road/ground PBR textures belong to the terrain surfaces, not to each cutout grass blade.

`pbr/nature_grass_blades.tres` is the editor-openable grass blade material using the original FBX's albedo/alpha and normal maps. `human_plane_3d_foliage.gd` applies it to editor-authored `NatureGrass*` nodes when their material override is initially blank, without changing their existing batch transforms. Set `grass_blade_material` on the parent or edit a child node's material override to adjust the blade appearance.

The intended editor arrangement under `Viewport3D/FlightWorld/Scenery`:

```text
GrassInstances (Node3D; script = human_plane_3d_foliage.gd)
├── NatureGrassA (MultiMeshInstance3D, band_a.tres, Z=+16)
├── NatureGrassB (MultiMeshInstance3D, band_b.tres, Z=-29)
├── NatureGrassC (MultiMeshInstance3D, band_c.tres, Z=-74)
└── NatureGrassD (MultiMeshInstance3D, band_d.tres, Z=-119)
```

All children are editor-authored, independently selectable and draggable; `MultiMeshInstance3D.multimesh` is assigned in the Inspector, not introduced invisibly at runtime. The `@tool` script exposes `grass_count`, `grass_outer_distance`, `grass_runway_half_width`, `grass_color`, `runway_grass_color`, and `variation_seed`. The **Refresh Grass Preview** Inspector button explicitly regenerates the distribution using the original FBX; normal scene loading preserves serialized MultiMesh instance placements. The renderer uses one batch per segment and disables grass shadows.

When updating the scene's scrolling logic, make `GrassInstances/NatureGrassA..D` the four moving/recycling props (cycle **180 world units** when a prop reaches **Z=64**) so moving the group in the Inspector does not cause snapback. Existing artist-authored FBX tree models (`PINE TREE.fbx`, `TREE.fbx`, `CUTTED TREE.fbx`) supply tree silhouettes. **No generated cone/cylinder trees remain** in `human_plane_3d_foliage.gd`.

## Validation and performance

- Run the one-time resource generation (requires a **real renderer**, since Godot's headless dummy renderer discards GPU MultiMesh buffers): `Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_3d_pbr.gd -- --generate`.
- Normal focused regression: `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/test_human_plane_3d_pbr.gd`. The headless suite checks the serialized buffer text instead of calling `MultiMesh.get_instance_transform()`, which returns zeros in the dummy renderer.
- GPU-focused verification: same normal test command **without `--headless`**, adding `--rendering-method gl_compatibility`. This additionally reads back actual transforms and buffers.
- Scene integration should use `tools/test_human_plane_3d_world.gd` and the real GPU screenshot test `tools/test_human_plane_3d_visual.gd`, with imported texture/shadow/vegetation readability inspected.

Validated on the final scene hookup: focused PBR/foliage suite **53/53 headless** and **57/57 RTX 3050 OpenGL GPU**; full 3D world scene suite **156/156**, six 3D GPU screenshots captured successfully, and editor parse completed. A separate existing motion suite reported 12 ring color/progress failures while other workers were editing ring/view logic; those are outside the PBR/foliage ownership and were sent to the main agent for review.

Frustum and visibility-range culling, importer-generated mesh LOD where available, texture mipmaps and `MultiMesh` batching are rendering optimizations. Raycasting is a physics query and does **not** perform geometry occlusion culling. A confirmed end-to-end webcam + YOLO FPS benchmark is still necessary.
