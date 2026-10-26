# Human Plane: cumulative flight speed and original 3D aircraft

## Flight speed and scoring (authoritative `human_plane.gd`)

The game uses one persistent per-round counter, `speed_boost_count`, and a
single multiplier:

```gdscript
speed_multiplier = 1.0 + float(speed_boost_count) * 0.14
gate_progress_per_second = DIFFICULTY_CONFIG[difficulty]["gate_speed"] * speed_multiplier
```

- Each **correct** ring scores exactly **+100 points** and adds **+0.14×**
  to the speed multiplier: 1.00×, 1.14×, 1.28×, 1.42×, etc.
- **Wrong/missed** rings do not subtract score or accumulated speed.
  They still cost one of the three hearts and reset the answer streak.
  Earlier speed boosts remain even after the streak resets.
- No arbitrary multiplier cap, slowing collision animation, post-answer
  speed reset, or per-ring wait. New current rings, retiring rings and
  prefetched rings advance on the same difficulty-speed × multiplier clock.
- Timing and scoring still use the original authoritative 2D hitbox/lane
  guides. The visible torus hole, body pose bridge and camera renderer
  do not change which word/lane counts as correct.
- Context serializes `plane_speed_boosts` and `plane_speed_multiplier`;
  recreating a paused game restores the earned speed independently of streak.
  Correct-answer count is also used as a safe old-save fallback.

The 3D view receives `set_speed_multiplier()`, so its foreground scenery
scrolls faster as the authoritative ring motion accelerates. The renderer's
old **0.7 progress-per-second visual cap** was removed; it previously made
rings appear to drag behind fast-authoritative game progression. Ring
interpolation is limited by a maximum **25 milliseconds of look-ahead** to
prevent visually crossing the scoring plane before collision resolves.
View progress is presentation-only and cannot award scores or cause misses.

## Editable full-3D model and world

- Original supplied red FBX: `res://Components/Gameplay/Human Plane/3D/red-plane/2b69a53022ec45b396ce8015291cc9ea.fbx`.
  **22 original imported mesh parts** and the **five supplied texture PNGs**
  are retained byte-exact, with Godot-generated import sidecars.
- An inspector-editable `RedPlane` PackedScene instance is under
  `WorldView3D/Viewport3D/FlightWorld/PlayerRig`, with editor-authored
  scale and rotation. Actual model wingspan is approximately **4.49
  world units** and fits through the inner torus opening (~4.74 units),
  preserving collision-lane accuracy. The 3D camera frames this plane near
  the bottom of the game screen.
- The imported FBX contains skin-bound meshes with an invalid skeleton
  bind pose for this runtime. The view disconnects `skin` and `skeleton`
  on the **existing meshes** at scene initialization. It never generates
  a different airplane mesh or alters the FBX source. This was essential
  for the real airplane to render as a complete red aircraft.
- Full PBR template:
  `res://Components/Gameplay/Human Plane/3D/red-plane/red_plane_pbr.tres`.
  It references the supplied albedo, OpenGL normal, metallic, roughness and
  ambient-occlusion PNG maps. `red_plane_pbr_template` is export-editable
  on the view scene. The renderer duplicates each mesh's imported material
  **per surface** to retain the original texture and individual part colors,
  attaches the provided physical maps, and keeps original surface meshes
  unchanged. Changing the template does not overwrite the source FBX.
- Blue, green and orange torus rings remain three separate editable
  PackedScene instances per wave, with `Label3D` grammar words centered in
  each hole. Torus radii: inner **2.37**, outer **2.87**, and lane centers
  **6 units** apart, avoiding overlapping ring geometry.
- Real user-provided ground materials, rendered directly by Godot:
  `pbr/road008a_path.tres` on `Terrain/FlyingPath` and
  `pbr/grass004_ground.tres` on `Terrain/Grass`.
- Four editor-visible `NatureGrassA..D` MultiMeshInstance3D bands under
  `Scenery/GrassInstances` use the user's `grass-green` FBX-derived mesh,
  texture, normal and **340 instances each**, from the four serialized
  `pbr/nature_grass_band_[a-d].tres` resources. Their nodes are independently
  movable in Godot and recycled during movement. The obsolete
  `ForestStrip*` code-generated cone-tree nodes are gone. Actual imported
  FBX trees and stones remain. The existing **24 authored mountain model
  transforms were not changed**.

### Provenance and licensing

The original attribution `Cartoon Plane by MahdiHasan.txt` is preserved
verbatim under `red-plane/`. It names the Sketchfab *Cartoon Plane* URL and
`https://sketchfab.com/3DPolyForge` as author. **It contains no express
license or grant of redistribution rights**, and it mentions a
`3d_Ripper_Pro` export path. The model was integrated for **local project
preview only**; do not package or publicly redistribute it until the
rightsholder's license and origin have been verified. The unused downloaded
`Thumbnail.jpg` and its `.import` were removed after confirming no scene
or test references them. No source mesh/texture/attribution was altered.

## Focused verification

From the project root in Godot 4.7.2:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_speed_multiplier.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_fixed_score_speed.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_3d_pbr.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_3d_motion_performance.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_speed_multiplier.gd -- --capture
```

Most recently observed: focused headless speed **345/0**, fixed scoring
**271/0**, 3D PBR **53/0**, 3D motion and frame-rate **377/0**,
and GPU accelerated-speed/model/PBR proof **441/0** including two
nonempty screenshot captures. The capture test
explicitly instantiates **full 3D** even though the separate 2.5D/3D
experiment currently defaults to 2.5D. It checks that all 22 original
mesh surfaces remain, that skin binding is detached, that material PBR
maps load, and that enough visible red pixels appear in the plane's
expected foreground region.

Full-3D screenshots are kept outside the project under Godot's
`user://_qa_human_plane_red_plane_3d_1280x720.png` and
`user://_qa_human_plane_red_plane_3d_1920x1080.png`.
No tests access a real camera, pose sensor, live DB or leaderboard.
