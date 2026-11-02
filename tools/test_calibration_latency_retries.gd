extends "res://tools/test_single_neutral_calibration_20261102.gd"

# Migrated latency/source-freshness suite. The SOLO Catch/Balloon task now
# makes one measured 3s hold at any visible camera X, not three floor zones
# or six wrist phases. Inherited integration QA verifies 8+ distinct source
# packets, no stale image credit, crowd/absent blocking, and no false GO.
# Preserve the historic 700ms packet gap safety threshold and 3s gate.

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    var probe := scene.instantiate() as Control
    var constants: Dictionary = probe.get_script().get_script_constant_map()
    probe.free()
    _check(is_equal_approx(float(constants.get("MAX_PACKET_GAP_SECONDS", -1)), 0.7)
        and is_equal_approx(float(constants.get("HOLD_SECONDS", -1)), 3.0)
        and int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
        activity + " retains strict 700ms source gap, 3s hold and 8 source-frame minimum")
