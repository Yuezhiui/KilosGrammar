# Catch the Word — editor-editable character artwork

The four Catch the Word characters are **separate native Godot `Sprite2D`
body/basket pairs**, not a flattened screenshot or a runtime replacement
texture. You can adjust each character independently in the scene editor,
including its body position, basket/hands position, crop, scale, and stacking.

## How to edit them (Godot 2D)

Open **`res://ui/minigames/catch_word.tscn`** and expand its scene tree:

```text
CatchTheWord
└── CharacterRig  (shared gameplay steering/movement origin)
    ├── Body                 (Boy)
    ├── Basket               (Boy)
    ├── CollectedWords       (caught apples/labels, in front of body)
    ├── Girl
    │   ├── Body
    │   └── Basket
    ├── Grandma
    │   ├── Body
    │   └── Basket
    └── Grandpa
        ├── Body
        └── Basket
```

Select **Body** or **Basket** underneath the required character and move it
directly in Godot's **2D editor** with the Move tool. Use the Inspector's
`Transform > Position` and `Scale` for precise positioning. The sprites have
independent, persistent `Texture2D`, `Region Enabled`, and `Region Rect`
properties so an artwork crop can be fixed without changing the others.
For non-Boy characters, choose the Girl / Grandma / Grandpa group in the
scene tree; temporarily toggle its visibility in the editor if the other
artwork obstructs it. Restore the desired starting visibility afterward;
the game will show exactly the selected character at runtime.

The Boy pair is directly under `CharacterRig` for compatibility with earlier
game screens/tests; the other pairs are under named groups. The runtime's
`catch_character` value chooses **Boy**, **Girl**, **Grandma**, or **Grandpa**.
This selection may change *visibility* and which sprite receives the basket
hitbox, but must **never reset your body/basket local position, crop, texture,
rotation, or scale**. Movement changes only the parent rig's gameplay X,
using its editor-authored resting location for initial placement.

At larger resolutions the game also scales the **parent CharacterRig only**
by `min(viewport width / 1280, viewport height / 720)` relative to its
editor-authored scale (for example, ×1.5 at 1920×1080). That keeps the
character proportional to the HUD **without rewriting Body or Basket's
independently draggable transforms**. Basket collision uses the selected
sprite's **global/world scale and scaled center offset**. Caught apples
continue to use local basket dimensions inside that same scaled parent.

## Framing and basket collision

The intended view is **1280×720** (also checked at 1600×900 and 1920×1080).
Keep the head, body/feet, hands and basket inside the viewport at the resting
position; the game clips content outside its bounds, so a correctly authored
sprite may still look cut if moved too low or made too large. Avoid moving
the character down to hide its feet. Cropped sprite `region_rect`, not an
entire source texture with transparent padding, defines the visual bounds.

The basket's catch area must follow its **live transformed Sprite2D**, not a
hardcoded screen-space location or an obsolete Boy crop. After adjusting the
basket in the editor, apples should collide with that newly positioned
basket, regardless of which character is selected. The effective collision
rectangle is intentionally narrower and shallower than the basket artwork;
it represents the opening rather than the whole sprite. Collected apples
must render between the body and foreground basket (`Body < CollectedWords
< Basket`) and follow the active basket. No separate runtime-created body
or basket sprite should shadow the editable nodes.

## Regression test

From the project root, run:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_catch_character_editor_rig.gd
```

The test instantiates the **real** scene for all four characters at three
resolutions. It verifies editor ownership and the original body/basket PNGs;
simulates individual Inspector moves **before** `_ready()`; checks that
character selection, reset, resize, and movement preserve every editor-saved
local transform and crop; verifies visibility, layering and no clipping at
the initial location **and both left/right steering extremes**. It also checks
all three caught grammar apples, real basket collision dimensions, and hitbox
movement when the basket alone is moved. Test mutations
exist only in memory and do not modify the `.tscn` file.

If this test fails immediately after a change, first inspect the indicated
character's **actual scene node**, selected texture, crop and saved transform.
Never fix framing by reintroducing code that assigns `Body.position`,
`Basket.position`, or their scales during startup: that would again make the
Godot drag-and-drop editing ineffective.

The headless test checks sprite geometry and collision behavior, not the
per-pixel look of a rendered screenshot. A final 1280×720/1920×1080
graphical preview is useful to confirm that no decorative HUD art masks the
face or basket during a real game.
