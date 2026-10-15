# Catch-the-Word generated character / fruit composition audit

Run: Godot 4.7.2 headless, `--script res://tools/test_catch_fruit_composition.gd`.

All four generated character textures loaded; body, collected-fruit and basket layer order was correct. At counts 0, 1, 2 and 3, the test observed exactly that many live apples with nonempty word labels, with no apples intersecting the upper 32% of the body rectangle. These are **geometry assertions**, not visual proof of readable labels or the artwork's exact wicker rim.

## Observed 1280×720 scene-space rectangles (x, y, width, height)

| Character | Body | Basket | Each apple (size) | Apple top |
| --- | --- | --- | --- | --- |
| Boy | 133.60,345.60,278.40,417.60 | 109.68,510.45,326.25,244.47 | 104.40×104.40 | 492.88 |
| Girl | 147.90,335.68,249.80,624.65 | 111.52,529.68,322.56,215.04 | 103.22×103.22 | 506.71 |
| Grandma | 147.90,335.68,249.80,624.65 | 111.52,529.68,322.56,215.04 | 103.22×103.22 | 506.71 |
| Grandpa | 147.90,335.68,249.80,624.65 | 111.52,529.68,322.56,215.04 | 103.22×103.22 | 506.71 |

At three apples, Boy left edges are 122.46, 220.60, 318.74; other characters 124.16, 221.19, 318.22. All fruit are behind the foreground basket sprite (`z=2` versus `z=3`) and ahead of the body (`z=0`).

## Resolution limitation

Changing `SceneTree.root.size` to 1600×900 or 1920×1080 under the current headless setup did **not** change `_view_size()` or measured scene coordinates. The test therefore exercised three requested window settings but **did not verify distinct rendered layouts** at the larger resolutions. GUI/window viewport validation is required before claiming responsive scaling passes.

## Proposed adjustment to prime (not applied)

At 1280×720, fruit tops are 17.57 px above the Boy basket texture rectangle and 22.97 px above the Girl/Grandma/Grandpa basket rectangle. The current overlap checks pass, but texture rectangle top is not the actual wicker opening. Inspect alpha/rim geometry visually before changing. If apples visibly float above the rim, move the apple group **down 15–25 px** at 720-high, equivalent to adding `view.y * 0.021–0.035` to apple y position, while retaining the upward word-label offsets. Avoid moving body/basket without a corresponding remeasurement. Do not assert label readability from nonempty text alone.
