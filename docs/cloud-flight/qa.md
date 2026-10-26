# KILOS GRAMMAR / Human Plane — inline cloud + neutral-pose QA

Last verified: 26 October 2026, Godot 4.7.2, Windows, NVIDIA GeForce RTX 3050 Laptop GPU (OpenGL 3.3 Compatibility). All commands here are offline and do not open a physical webcam, YOLO worker process, live PostgreSQL/CSV student database, or destructive UI.

## Production contract

The gameplay wrapper `ui/minigames/human_plane.tscn` mounts **one inspector-editable 3D scene**, `ui/minigames/human_plane_3d_view.tscn`. It serializes both sets of LEFT/CENTER/RIGHT real torus meshes, their labels/materials and all independently positioned 3D cloud nodes **within the same 3D .tscn**. No separate `human_plane_3d_ring.tscn` or `Skybox/CloudCluster.tscn` is loaded. The original RedPlane model remains directly under `PlayerRig` with scale 100 in its native editor transform, no hidden parent normalization. Import/display enlargement is verified through physical bounds and rendered GPU pixels, not by asserting arbitrary extra scale pivots.

The original user-provided cloud source is `Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/scene.gltf` + its `scene.bin`. Godot's GLTF import supplies actual real mesh/surface materials; testing a `CloudCluster` placeholder or old procedural puffs is no longer valid. `Skybox/sky_panorama.png` remains the 2D background on a `PanoramaSkyMaterial`, behind the imported 3D clouds. Old Terrain/Scenery remains invisible; preserved mountain source transforms do not produce rendered roads, grass or mountains. Every asset must remain editor-editable, while gameplay ring X and collision alignment stay authoritative.

The cloud source includes a separate CC BY 4.0 license file (`Skybox/StylizeClouds/license.txt`) crediting **ragad.sallabi** for [stylize clouds](https://sketchfab.com/3d-models/stylize-clouds-32ed464f19fe4acf86723eaff08dd568). Preserve this license and attribution with redistributed assets.

Human Plane alone now calibrates **ONE** relaxed, stationary, neutral wrist/shoulder pose. The user keeps the same floor position, both hands and torso in view, one verified locked tracking identity. The camera intro does not count toward the **2.5-second hold** or **eight distinct fresh source packets** minimum. Seven source frames, duplicate/stale frames, an unverified person or a changed track ID may never unlock the game. The measured neutral median and jitter give an adaptive deadzone/sensitivity for small, natural LEFT and RIGHT banks; no fabricated endpoint measurements are stored. After acceptance, gameplay is automatically queued; no manual check-camera or forced wide-arm pose is required. Lost tracking/another person/unreliable wrists freeze the last airplane X. The two *other* games, Catch the Word and Balloon Popping, still require three actual physical CENTER/RIGHT/LEFT standing-zone measurements.

Authoritative scoring is unchanged: **+100** for an unambiguous centered correct ring, **zero point deductions** on wrong/miss/two-ring boundary ambiguity, and a cumulative **+14% lifetime ring/scenery speed boost** on true correct answers only. The collision score and visible 3D rings share the same 3-resolution lane centers.

## Focused test entry points and verified results

From the Godot project root (replace `godot` with the installed Godot 4.7.2 console executable):

```powershell
godot --headless --editor --path . --quit
godot --headless --path . --script res://tools/test_human_plane_cloud_flight.gd
godot --headless --path . --script res://tools/test_human_plane_3d_pbr.gd
godot --headless --path . --script res://tools/test_human_plane_3d_scale_flow.gd
godot --headless --path . --script res://tools/test_human_plane_3d_motion_performance.gd
godot --headless --path . --script res://tools/test_calibration_stationary_wing_roll.gd
godot --headless --path . --script res://tools/test_human_plane_stationary_calibration.gd
godot --headless --path . --script res://tools/test_human_plane_body_integration.gd
godot --headless --path . --script res://tools/test_calibration_human_plane_center_only.gd
godot --headless --path . --script res://tools/test_calibration_sparse_pose_fps.gd
godot --headless --path . --script res://tools/test_human_plane_collision_boundary.gd
godot --headless --path . --script res://tools/test_human_plane_fixed_score_speed.gd
godot --headless --path . --script res://tools/test_human_plane_speed_multiplier.gd
godot --headless --path . --script res://tools/test_human_plane_pose_hitbox_qa.gd
godot --headless --path . --script res://tools/test_all_scenes_bruteforce.gd
godot --headless --path . --script res://tools/test_component_prune_integrity.gd
godot --headless --path . --script res://tools/test_asset_cleanup_integrity.gd
godot --headless --path . --script res://tools/test_projectwide_orphan_integrity.gd
```

Results on this working tree: cloud GLTF/editor hierarchy **PASS (75 checks)**; source GLTF/native PBR **PASS (67)**; enlarged plane/ring scale **PASS (70)**; cloud motion/performance **PASS (377)**; single neutral calibration including duplicate-packet and stale-pose rejection **PASS (28)**; real gameplay-wrapper stationary input **PASS (40)**; Catch/Balloon retention plus rejected old plane floor-input **PASS (25)**; sparse real source packet calibration for Catch **PASS (91)**; scoring collision ambiguity **PASS (354)**; +100/no point penalty/speed contract **PASS (271)**; cumulative speed boost **PASS (345)**; pose/collision bounds **PASS (325)**; final RedPlane/material/asset QA **PASS (238)**. Godot editor import **PASS**.

Scene inventory is **dynamic**: currently **29 loadable .tscn scenes**, but removal of obsolete child scenes or creation of other legitimate UI scenes can change that number. Never add a fake scene or restore Credits to hit a hardcoded historic count. The audits instantiate and check **all discovered** scenes, then verify essential 3D/wrapper scenes exist, Credits is absent and no orphan references remain. Latest audits: brute scenes **PASS (1,626 checks; 29 scenes)**; Components **PASS (893)**; asset cleanup **PASS (734)**; project-wide orphan/GLTF binary and texture references **PASS (2,782)**.

## Real GPU screen-space evidence

```powershell
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/test_human_plane_3d_camera_visibility.gd
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/test_human_plane_3d_visual.gd
```

Actual NVIDIA OpenGL pixel-difference and aircraft camera-frustum QA: **PASS (507 checks, zero failures)** for LEFT/CENTER/RIGHT across **1280×720, 1600×900, 1920×1080**, for near/approach distances. The enlarged aircraft occupies approximately **11.1% of viewport width in CENTER and 13.7% in LEFT/RIGHT** (exceeding the 8% minimum), stays fully onscreen, and does not obscure ring words. Six valid near/distant game screenshots were captured, one for each resolution/phase, at `user://_qa_human_plane_3d_<width>x<height>_{distant|near}.png`; the native screenshot paths are under `C:/Users/Yue/AppData/Roaming/Godot/app_userdata/KilosGrammar/`.

**Remaining validation boundary:** offline source-shaped packet tests and GPU screenshots do not establish actual physical webcam/YOLO throughput, student-level lock quality in a crowded classroom, or student ergonomics. Those require an in-person supervised camera test, not synthetic runtime calibration. No commits or live data changes are part of these QA tests.
