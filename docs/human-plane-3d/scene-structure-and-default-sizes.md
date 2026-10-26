# Human Plane: one editable 3D scene and actual model sizes

## Canonical editor scenes

The user's later request to **edit the entire 3D world in one .tscn** supersedes
the earlier proposal to keep the torus as a reusable standalone scene.

| Scene | Responsibility |
| --- | --- |
| `ui/minigames/human_plane.tscn` | Separate 2D gameplay/HUD wrapper, hidden scoring guides, and quiz controller |
| `ui/minigames/human_plane_3d_view.tscn` | **Only authored 3D scene:** camera, sky, 12 editable native glTF clouds, six inlined torus/labels, aircraft, hidden original terrain |

The six inlined torus roots continue to use the same
`ui/minigames/human_plane_3d_ring.gd` script. Imported FBX and glTF assets
are source models, not extra authored .tscn world/layout files. This keeps
the moving camera, rings and clouds open in **one Godot Inspector hierarchy**
while leaving stable 2D quiz/HUD/scoring separate.

## Current flight model dimensions

* The source RedPlane FBX is extremely tiny. Import setting
  `nodes/apply_root_scale=true` and `nodes/root_scale=28.0` corrects its
  original source units at import time, **without changing the FBX file**.
* The editor-visible `PlayerRig.scale` remains **(1, 1, 1)**.
  `PlayerRig/RedPlane` remains mirrored on X/Z, with local scale magnitude
  **(100, 100, 100)**. There is no invisible 14.5-scale parent. The resulting
  approximate native mesh wingspan is **3.07 world units** (pending individual
  end-to-end GPU size verification for future model-import changes), chosen
  because the previous 1.59-unit airplane was too small in gameplay.
* Each torus is a native `TorusMesh` with original outer radius **2.22**,
  inner radius **1.78**, or **4.44 outer diameter** and **3.56 opening
  diameter**. The visually larger aircraft is still narrower than the
  opening. The six separate root transforms, materials, and `Label3D`
  properties remain editable in the one 3D scene.
* All cloud instances use the user's real
  `Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/scene.gltf`,
  with original `scene.bin` and imported material. Its CC BY 4.0 attribution
  to ragad.sallabi is preserved in the asset's `license.txt` and flight docs.
  It provides native mesh material information but no separate image texture
  maps; no artificial PBR maps should be claimed.

The 3D scene's rendering uses the game controller's **actual 2D authored
hitbox centers**, mapping each scored choice to its 3D torus center. Visually
moving the camera/rings without updating their alignment can break scoring;
run the GPU camera and collision boundary regressions after such edits.
One correct crossing remains +100 score and +14% permanently accumulated
flight speed; ambiguous or missed crossings earn no points.

The Human Plane camera now calibrates one natural hand/shoulder neutral pose
while standing still. It is distinct from Catch the Word and Balloon Popping,
which keep their physical CENTER/RIGHT/LEFT calibration. See
`docs/cloud-flight/calibration.md` for the one-student lock, real frame
requirements, and runtime control details.
