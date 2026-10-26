# Human Plane full-3D: unambiguous ring collision

## Behavior

The user's question: **What happens if a player stands between a wrong and
correct answer?**

**Answer: it is a miss.** The game never guesses which grammar answer the
student intended. When the moving gates reach the invisible, editor-authored
`AnswerLine`, exactly **one** ring must be clearly and centrally entered
by the student aircraft's editor-authored `PlaneRig/Hitbox`.

The authoritative `human_plane.gd::_lane_hit_at_answer_line()` now:

1. Locates the pilot hitbox from the existing body-controlled
   `plane_x_norm`, native `FlightPaths/PlaneLeftLimit` and
   `PlaneRightLimit`, and the drag-and-drop `PlaneRig/Hitbox`
   offsets. It does **not** depend on the texture's invisible
   letterboxed margins.
2. Finds every intersecting *visible* ring rectangle at the actual
   crossing time using the existing `_gate_visible_rect()` function
   and native gate start/end/artwork control offsets.
3. If the pilot hitbox intersects **zero or more than one** ring, returns
   `-1` (miss) before considering whether any word is correct.
   A tiny second overlap is not silently ignored, and left-to-right
   lane order cannot bias scoring.
4. If exactly one ring is intersected, requires at least **70% of the
   horizontal hitbox width** to overlap that ring, and the hitbox center
   to stay within **30% of the ring's visible width** either side of
   its center. For very narrow, editor-resized rings, the center window
   shrinks so the entire pilot hitbox must be able to fit inside the
   rendered ring. Merely touching the colored rim/outer edge is
   insufficient.
5. Returns the single unambiguous lane index only when all tests pass.

Both 70% coverage and the centered window use fractional dimensions
from the **authored** controls; no hard-coded pixel positions, fixed
viewport coordinates or generated proxy collision meshes are added.
With the current editor layout at the answer crossing, each visible
gate is approximately **177 logical pixels** wide and adjacent gate
centers are approximately **190 pixels** apart. The 44-pixel native
hitbox is therefore wide enough to touch **both** gate frames across
their ~14-pixel separation. The former first-overlap loop could
arbitrarily award the left ring. Now this is always a miss, independent
of the order of the correct/wrong grammar words.

### Scoring, feedback and lives are unchanged

- **Clearly centered correct**: exactly **+100 points**, one permanent
  **+14% speed** boost, unchanged lives.
- **Clearly centered incorrect**: **0-point deduction**, no speed
  boost or rollback, one heart lost, streak reset.
- **Between, straddling, grazing, or missing rings**: `selected_lane=-1`,
  **0-point deduction**, no speed boost or rollback, one heart lost,
  streak reset. Existing missed-gate feedback plays.
- Resolving a wave is idempotent. A correct move **after** crossing
  cannot retroactively award points or reverse a miss.
- `set_body_x()` still accepts only fresh calibrated body coordinates
  when both arms are out; pose loss freezes movement, and the normal
  per-frame movement cap prevents last-millisecond teleports.

## Full-3D rendering and editor geometry

Human Plane continues to use **only** `WorldView3D`. The game sends
the same pose-normalized `plane_x_norm` and selected ring index to its
existing 3D renderer; the 3D model, camera, torus scenes, PBR materials,
24 mountain transforms and 3D moving rings were **not modified** by
this collision change. The hidden native 2D guides are strictly the
editor-authorable scoring projections. Their scene positions, anchors,
ring offsets, world HUD and source art remain unchanged.

**Separate visual alignment dependency:** The scene-authored 2D
scoring ring centers correspond approximately to normalized
`[0.33, 0.50, 0.67]`. During this collision change, the separately
owned 3D renderer changed its horizontal player mapping from
`[-9.5, +9.5]` to an exported `visual_lane_extent` of **3.6**,
while its physical ring center nodes remained at world X
`[-6, 0, 6]`. Those values are not inherently a physical
ring-center match. Their actual visual projection and enlarged model
span must be verified by the 3D-view owner independently; the
authoritative scoring side **must not** silently compensate by
changing editor-authored answer boundaries. This preexisting /
concurrent **renderer-space alignment concern** was reported to the
prime/3D-view owner with exact constants, and is outside the
authorized `human_plane.gd` collision-only edits. No code-generated
lane geometry was added.

## Focused offline regression

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_collision_boundary.gd
```

The test uses **1280×720, 1600×900 and 1920×1080**, both Seconds and
Lives modes. It validates all three ring centers, off-center single
ring grazing, two adjacent correct/wrong orderings, two rings that
overlap because their *editor-authored guide nodes* were moved, a
widened truly empty gap, two simultaneously correct answers in an
ambiguous hit, late real pose movement and movement **after** gate
resolution. It also checks point/heart rules, persistent +14% boost,
no repeated scoring and no pose movement with arms down.

Related legacy regression suites:

- `tools/test_human_plane_fixed_score_speed.gd`
- `tools/test_human_plane_assets_pose.gd`
- `tools/test_human_plane_speed_multiplier.gd`

All tests run offline with no physical camera, PostgreSQL connection or
destructive game-state writes. The normal 3D scene and collision guides
remain editable in Godot's scene editor.
