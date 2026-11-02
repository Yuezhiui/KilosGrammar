extends "res://tools/test_single_neutral_calibration_20261102.gd"

# Nov 2 migration of the historic bilateral-consumer fixture.
# The SOLO calibration deliberately requires fresh torso packets, NOT
# both wrists DOWN then UP. Re-run the source-verified safety matrix with
# alternating raised/unraised hands to prove the retired wrist gate is gone.
# Human Plane retains independent T-pose tests in the calibration suite.
var _wrist_up_next := false

func _packet(screen: Control, x: float, people := 1, fresh_pose := true, wrist_valid := false) -> void:
    if people == 1 and fresh_pose:
        _wrist_up_next = not _wrist_up_next
        super._packet(screen, x, people, fresh_pose, _wrist_up_next)
    else:
        super._packet(screen, x, people, fresh_pose, wrist_valid)

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    _check(activity in ["Catch the Word", "Balloon Popping"],
        activity + " former bilateral test now covers torso-only neutral hold")