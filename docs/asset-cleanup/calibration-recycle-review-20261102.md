# Calibration artwork cleanup — Nov 2, 2026

The new Catch/Balloon single-player neutral calibration and the dedicated
two-player neutral calibration **do not display** the older directional
standing/hand-raise pose guide PNGs.

## Why the old PNGs were NOT moved to the Windows Recycle Bin yet

The legacy shared scene
`ui/vision/calibration/calibration.tscn` still **serializes explicit
ext_resource references** to these image files and some controls. Human
Plane still uses separate existing T-pose/left/right demonstration imagery,
and older editable scenes and regression fixtures may rely on the shared
artwork nodes. Deleting or moving tracked resources while those references
remain would produce missing texture errors and risk breaking the original
single-player game.

This assessment respects the user's requirement to **preserve rather than
permanently delete** old artwork. A later cleanup can first remove/retarget
the unused scene references and update affected fixtures, then move each
confirmed-unused file to a dedicated recoverable archive or the Windows
Recycle Bin. Never recycle any files referenced by the active Human Plane
scene or integrated tutorial.

No original artwork was deleted, replaced, renamed or recycled in this
development checkpoint.
