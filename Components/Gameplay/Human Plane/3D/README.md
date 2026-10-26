# Human Plane 3D — NATURE local assets

All live 3D models, scenery, textures and material resources are bundled under `res://Components/Gameplay/Human Plane/3D/...`. The game does not depend on a user's Windows Downloads folder.

The gameplay aircraft is `red-plane/2b69a53022ec45b396ce8015291cc9ea.fbx`, a real imported, textured 3D model retaining all five original PBR maps. The separate original `toy_plane/scene.gltf` and license are retained as reference assets. The current sky is `Skybox/sky_panorama.png` in a Godot PanoramaSkyMaterial; twelve editable cloud instances use the real `Skybox/StylizeClouds/scene.gltf` model and its source `scene.bin`. The original `Skybox/textures/clouds_anime_6k.jpg` remains preserved as source art. FBX trees/rocks and old terrain resources are present in the Godot scene as hidden, editable legacy assets.

The entire live 3D world is authored in `ui/minigames/human_plane_3d_view.tscn`. Its six 9:16 open portrait answer portals are native CapsuleMesh frames with editable pastel materials and dark Label3D word plaques, grouped as `CurrentRings` and `UpcomingRings`. Gameplay changes the word, answer feedback colors and forward Z position; the gates' inspector-authored X and Y positions are preserved. The RedPlane model's scene scale and Camera3D are also editable in the same scene.

**Current RedPlane model provenance:** [Cartoon Plane](https://sketchfab.com/3d-models/cartoon-plane-2b69a53022ec45b396ce8015291cc9ea), authored by [3DPolyForge](https://sketchfab.com/3DPolyForge) (provided download metadata: `red-plane/Cartoon Plane by MahdiHasan.txt`). Its license was not included in the supplied metadata; verify redistribution terms before publishing.

**Live stylized clouds attribution:** “stylize clouds” by [ragad.sallabi](https://sketchfab.com/ragad.sallabi), [Sketchfab model](https://sketchfab.com/3d-models/stylize-clouds-32ed464f19fe4acf86723eaff08dd568), licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Keep `Skybox/StylizeClouds/license.txt` with the source.

**Toy Plane attribution:** “Toy Plane” by [l3clarke](https://sketchfab.com/l3clarke), from [Sketchfab](https://sketchfab.com/3d-models/toy-plane-804d6814818247978f28d12efcc38cce), licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). We scaled/rotated the model for the game. Preserve `toy_plane/license.txt` and attribution in any distributed release.

The supplied NATURE FBX/environment textures do not contain redistribution licenses: verify their provenance/permission before publicly releasing the game. [mujtaba-io/3d-endless-runner](https://github.com/mujtaba-io/3d-endless-runner) is MIT licensed; only the general 3-lane/recycled-world concept was adapted.

Regression: `tools/test_human_plane_3d_world.gd`, `tools/test_human_plane_3d_interactions.gd`, `tools/test_human_plane_3d_visual.gd` and the unchanged fixed-score/body steering tests. No database writes or camera service required.

## Published source beta asset policy (v0.2.0-beta.1)

The GitHub scene uses the CC BY 4.0 Toy Plane and the CC BY 4.0 stylize clouds; both remain fully included with their licenses and authors. The original local red FBX, its PBR maps, CC BY-NC-ND mountain, grass/road textures, and FBX vegetation are **not redistributed** in the source beta. The developer's local 3D scene and originals are unchanged. The publication copy replaces the aircraft reference with Toy Plane and removes hidden terrain/scenery and their asset dependencies. The scene keeps its own editable 3D clouds, camera, portal meshes, and gameplay hierarchy. Public copy visuals differ from the licensed/unlicensed local developer model. See `docs/BUILD_VERSION.md` for test and deployment limitations.