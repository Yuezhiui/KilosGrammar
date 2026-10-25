# Source-art UI toolkit for Godot 4.7

Use `cartoon_widgets.gd` to build native controls styled with the
user-supplied extracted art. All sprites are separate PNGs under
`Components/<screen>/Redesign/` (such as `Components/Settings/Redesign/`);
`ui/redesign/assets/` now keeps the extraction scripts and manifests only;
no runtime extractor, injected screenshots,
or generated fake art.

Typical scene script:

```gdscript
const ART = preload("res://ui/redesign/shared/cartoon_widgets.gd")

func _ready() -> void:
    ART.background(self, "tutorial", "bg_classroom")
    var start := ART.button($ButtonRow, "tutorial", "button_guided",
                            "Start guided tutorial")
    start.pressed.connect(_start_tutorial)
```

For a screen using the Game Over assets:

```gdscript
var retry := ART.button($Actions, "game_over", "button_retry",
                        "Retry", "button_retry_hover")
retry.pressed.connect(_retry_round)
```

Use `ART.image(parent, category, sprite)` for backgrounds, titles,
decorations, and empty art cards; it creates a normal Godot
TextureRect with `MOUSE_FILTER_IGNORE`. `ART.card(...)` requests
expand/fill sizing. `ART.skin_button(...)` applies a source-derived
StyleBoxTexture to an **existing** Button, retaining real hit areas,
focus indication, keyboard navigation, disabled and hover states.
`ART.atlas_texture(source_texture, Rect2i(...))` is available for
optional on-project atlas imports; today's assets are standalone
extracted PNGs.

For 875×500 and similarly compact displays, wrap content in a
ScrollContainer, then use `ART.columns(grid, viewport_width)`
to switch between one and two columns. The screen must keep all
controls focusable and scrollable. A helper makes the scroll area:

```gdscript
var scroll := ART.scrolling_root(self)
var grid := GridContainer.new()
scroll.add_child(grid)
ART.columns(grid, size.x)
```

For single fixed-position artwork sections, `ART.fit_stage(stage,
size)` fits a 1280×720 logical stage within the visible viewport
without distorting illustrated art. `responsive_canvas.gd` offers
the same behavior from an exported node script, plus optional
grid/scroll/compact hint paths. Call
`responsive_canvas.reveal_focused(control)` when moving keyboard
focus to a control below the current scroll position.

When labels are baked into a sprite, the Button's text colors are
made transparent by `skin_button`, while `Button.text` and
`tooltip_text` remain available to Godot. Do not use static
`volume_preview_*.png` with baked “100%” for a dynamic Settings
volume value; use a native slider and a separately live value label.

Verify scripts and sample resources:

```powershell
Godot --headless --path . --script res://ui/redesign/shared/smoke_test.gd
```
