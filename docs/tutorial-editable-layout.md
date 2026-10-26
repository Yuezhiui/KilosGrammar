# Tutorial spotlight — editable Godot scene layout

The screenshots' cream instruction card, violet/blue/red/green buttons,
transparent highlight openings, red arrows and body-position practice card
are controlled by `ui/tutorial/spotlight_overlay.tscn`.

Open **this scene in Godot's 2D editor**. Expand:

* `Overlay/CaptionCard` for the card, StepCounter, Header, Caption and
  independently draggable Back/Replay/Skip/Next buttons.
* `Overlay/GuideArrows` for separately draggable TextureRect art:
  CatchWordPromptArrow (question), CatchWordPlayArrow (basket),
  ModeArrow (timer/lives), ScoreArrow, PauseArrow, and the Balloon/Plane
  variants. The script changes only each arrow's visibility; it does **not**
  rewrite its scene-authored position, rotation or size. To place a hidden
  arrow in the editor, temporarily enable its eye icon, drag it, then hide it.
* `Overlay/FocusRegions/CatchWord`, `BalloonPopping`, or `HumanPlane`.
  Each has independent editor-authored **Prompt, PlayArea, Seconds, Lives,
  Score, Pause** rectangles. Select a rectangle, then drag its handles to
  change which part of the dimmed scene the tutorial highlights. These are
  non-rendering Control nodes: you see resize handles in Godot, not boxes
  over children's gameplay. The root FocusRegions node stays enabled so
  the controls remain selectable in the editor, but mouse input is ignored.
* `Overlay/MovementFeedbackPanel` for the smaller movement panel, heading
  and status text shown during the activity's movement tutorial.

`SpotlightOverlay.use_editor_highlights` is enabled by default: authored
rectangle positions are now the source of truth for the shader holes.
Disable the export only when deliberately choosing automatic tracking of
the live, possibly moving target widget. All tutorial assets remain
individually serialized and adjustable, not generated at runtime.

The camera's person detection / gameplay freeze is separate. The
`COME BACK INTO THE CAMERA!` banner belongs to
`ui/play/gameplay.tscn` under `TrackingNoticeLayer` and can be edited
there without touching Calibration or Catch the Word scenes.
Showing it requires a fresh zero-people YOLO inference after a real
student session has been established, and a sustained 1.25-second gap.
Camera stalls, another student in view, or temporarily invalid
calibration/hand measurements do not trigger that particular message.

**Tutorial is practice-only:** it does not register new student profiles
or save scores, including after Retry, Results, Pause/Restart or Skip.
`main_menu.gd` gates all registration and completed-score writes;
`ui/secondary/results.gd` reports the non-persistent tutorial state.
Scores are saved only for ordinary sessions started via Main Menu **Play**
when local PostgreSQL is connected and a real round completes.

The Credits button and original Credits screen were restored under
`MainLayer/LeftMenu/Credits` and `ui/secondary/credits.tscn` at the user's
request. Calibration and Catch the Word scene layouts and PNG files were
**not modified** as part of this change.
