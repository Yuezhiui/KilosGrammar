extends SceneTree

## Deterministic Catch/Balloon FLOOR calibration acceptance/diagnosis without a webcam.
## Human Plane's independent planted-feet steering protocol is checked by
## test_calibration_stationary_wing_roll.gd.
## Godot --headless --path . --script res://tools/test_calibration_sparse_pose_fps.gd
## Covers sparse 2.5 Hz actual pose packets, 3-second hold, >=8 unique packets,
## startup without pose, zone limits, and a packet burst across one UI tick.

const SCENE := "res://ui/vision/calibration.tscn"
const TOKEN := "synthetic-calibration-safety-qa"
const ZONES := ["CENTER", "RIGHT", "LEFT"]
const POSITIONS := [0.50, 0.82, 0.18]
const FPS_DT := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []
var pose: Node


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    pose = root.get_node_or_null("PoseService")
    _check(pose != null, "Real PoseService autoload available")
    if pose == null:
        _finish()
        return
    await _check_sparse_holds()
    await _check_zone_thresholds_and_eight_distinct()
    await _check_adaptive_low_fps_gap()
    await _check_udp_burst_distinct_packets()
    _check_bounded_pose_source_history()
    _finish()


func _prepare_pose() -> void:
    pose.stop_camera()
    pose.set_process(false)
    pose.set("active", true)
    pose.set("player_x", -1.0)
    pose.set("current_status", {"state": "loading", "pose": false, "lock_state": "waiting"})
    pose.set("last_pose_ms", 0)


func _make_screen() -> Control:
    var packed := ResourceLoader.load(SCENE) as PackedScene
    _check(packed != null, "Calibration scene and PoseService autoload compile")
    if packed == null:
        return null
    var screen := packed.instantiate() as Control
    _check(screen != null and screen.has_method("set_context"),
        "Real calibration script is attached to authored screen")
    if screen == null or not screen.has_method("set_context"):
        if screen != null:
            screen.free()
        return null
    root.add_child(screen)
    screen.set_process(false)
    screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    screen.call("set_context", {"activity": "Catch the Word",
        "topic": "Noun", "game_mode": "Seconds", "keyboard_mode": false})
    return screen


func _check_sparse_holds() -> void:
    _prepare_pose()
    var screen := _make_screen()
    if screen == null:
        return
    var constants: Dictionary = screen.get_script().get_script_constant_map()
    _check(float(constants.get("HOLD_SECONDS", -1)) == 3.0,
        "Every stage requires exactly 3.0 seconds of tracked stationary hold")
    _check(int(constants.get("REQUIRED_SAMPLES", -1)) >= 8,
        "Every stage requires at least 8 DISTINCT pose frames")
    _check(constants.get("CAPTURE_ORDER", []) == ZONES,
        "Calibration order remains CENTER, RIGHT, LEFT")
    # Simulated 7-second device startup with no valid positions. Real clock
    # need not pass: integration calls the authored calibration _process() with
    # a deterministic render delta (physical webcam and DB remain untouched).
    for _i in range(7 * 60):
        screen.call("_process", FPS_DT)
    _check(not bool(screen.get("intro_running")), "Startup surpasses the 2.5-second intro")
    _check(int(screen.get("live_step")) == 0 and
        is_zero_approx(float(screen.get("live_timer"))),
        "Seven seconds without a student never earns implicit calibration time")
    _check((screen.get("live_samples") as Array).is_empty(),
        "Delayed YOLO startup cannot fabricate any of the eight real frames")

    # 2.5 real pose frames/second, not 60 repeated UI redraws/second. At each
    # accepted 0.4-second interval, there are 24 redraws of the same packet.
    # This must still complete a 3s+8-real-frame hold (roughly 4 seconds).
    for index in range(ZONES.size()):
        var before_seq := int(pose.get("packet_sequence"))
        var frame_count := 0
        var step_before := int(screen.get("live_step"))
        for packet in range(13):
            var jitter := 0.009 if packet % 2 == 0 else -0.009
            _real_pose(POSITIONS[index] + jitter)
            frame_count += 1
            for _tick in range(24):
                screen.call("_process", FPS_DT)
            if int(screen.get("live_step")) > step_before:
                break
        _check(int(screen.get("live_step")) == step_before + 1,
            "%s sparse 2.5 Hz pose passes actual 3s/8-frame hold" % ZONES[index])
        _check(frame_count >= 8, "Sparse " + ZONES[index] + " cannot pass using 60Hz redraw duplicates")
        _check(int(pose.get("packet_sequence")) - before_seq == frame_count,
            "Every sparse %s sample corresponds to exactly one distinct packet" % ZONES[index])
        _check((screen.get("measured_points") as Dictionary).has(ZONES[index].to_lower()),
            "Sparse %s measurement saved after real distinct poses" % ZONES[index])
    _check(int(screen.get("live_step")) == 3,
        "Real CENTER,RIGHT,LEFT measurements complete despite 2.5Hz inference")
    _check(bool((pose.get("calibration") as Dictionary).get("valid", false)),
        "Successfully measured travel bounds are stored as real 3-point calibration")
    var saved: Dictionary = pose.get("calibration")
    _check(float(saved.get("left", 0.0)) < float(saved.get("center", -1.0)) and
        float(saved.get("center", 1.0)) < float(saved.get("right", 0.0)),
        "Measured travel remains strictly ordered and is never synthesized")
    # The same measurements feed Human Plane movement, including neutral
    # CENTER and genuine signed LEFT/RIGHT steering.
    _real_pose(float(saved["center"]))
    _check(absf(float(pose.call("normalized_body_x"))) < 0.02,
        "Measured CENTER is neutral in gameplay body steering")
    _real_pose(float(saved["right"]))
    _check(float(pose.call("normalized_body_x")) > 0.95,
        "Measured RIGHT produces strong positive normalized movement")
    _real_pose(float(saved["left"]))
    _check(float(pose.call("normalized_body_x")) < -0.95,
        "Measured LEFT produces strong negative normalized movement")
    pose.set("current_status", {"state":"stale", "pose":false})
    _check(is_zero_approx(float(pose.call("normalized_body_x"))),
        "Stale pose freezes gameplay body steering rather than ghost movement")
    screen.queue_free()
    await process_frame
    await process_frame
    pose.stop_camera()


func _check_zone_thresholds_and_eight_distinct() -> void:
    _prepare_pose()
    var screen := _make_screen()
    if screen == null:
        return
    screen.set("intro_running", false)
    screen.call("_finish_intro_only")
    _check(bool(screen.call("_inside_zone", "CENTER", 0.33)) and
        bool(screen.call("_inside_zone", "CENTER", 0.67)) and
        not bool(screen.call("_inside_zone", "CENTER", 0.31)),
        "Wider CENTER accepts approximately 0.32–0.68, rejects outside")
    _check(bool(screen.call("_inside_zone", "RIGHT", 0.641)) and
        not bool(screen.call("_inside_zone", "RIGHT", 0.639)),
        "Wider RIGHT begins at 0.64 with measured center at 0.5")
    _check(bool(screen.call("_inside_zone", "LEFT", 0.359)) and
        not bool(screen.call("_inside_zone", "LEFT", 0.361)),
        "Wider LEFT ends at 0.36 with measured center at 0.5")
    screen.set("live_step", 1)
    screen.set("measured_points", {"center": 0.5})
    _real_pose(0.70)
    screen.call("_process", 0.1)
    _check(float(screen.get("live_timer")) > 0.0, "Stable RIGHT enters hold")
    # Two samples are BOTH inside the RIGHT zone, but their 0.11 lateral
    # difference triggers the independent 0.095 fixed-anchor stability gate.
    # This reproduces intermittent apparent "unregistered" movement near the
    # threshold. It is a safety feature, not a made-up scoring pass.
    _check(bool(screen.call("_inside_zone", "RIGHT", 0.70)) and
        bool(screen.call("_inside_zone", "RIGHT", 0.81)),
        "Positions 0.70 and 0.81 both qualify for RIGHT region")
    _real_pose(0.81)
    screen.call("_process", 0.1)
    _check(is_zero_approx(float(screen.get("live_timer"))) and
        (screen.get("live_samples") as Array).is_empty(),
        "0.11 motion inside RIGHT correctly resets its stationary hold")
    # A point just outside the new, wider edge still must reset a hold. This
    # protects the measured range against students who did not reach RIGHT.
    _real_pose(0.74)
    screen.call("_process", 0.1)
    _real_pose(0.635)
    screen.call("_process", 0.1)
    _check(is_zero_approx(float(screen.get("live_timer"))),
        "Borderline RIGHT 0.635 fails widened 0.64 threshold and resets")

    screen.set("live_step", 0)
    screen.set("measured_points", {})
    screen.call("_reset_current_hold")
    # Even though 7 genuinely distinct 2 Hz camera frames cover >3 seconds,
    # the scene must not pass until the eighth unique source frame arrives.
    for i in range(7):
        _real_pose(0.5 + (0.01 if i % 2 == 0 else -0.01))
        screen.call("_process", 0.5)
    _check(float(screen.get("live_timer")) >= 3.0,
        "Three physical seconds are actually observed at 2Hz")
    _check((screen.get("live_samples") as Array).size() == 7,
        "Seven source packets produce exactly seven calibration samples")
    _check(int(screen.get("live_step")) == 0,
        "3s hold with only seven distinct frames cannot advance CENTER")
    _real_pose(0.5)
    screen.call("_process", 0.5)
    _check(int(screen.get("live_step")) == 1,
        "Eighth real distinct frame unlocks completed 3-second CENTER hold")
    _check((screen.get("measured_points") as Dictionary).has("center"),
        "Accepted eight-sample CENTER position derives from real measurements")

    screen.queue_free()
    await process_frame
    await process_frame
    pose.stop_camera()


func _check_adaptive_low_fps_gap() -> void:
    _prepare_pose()
    var screen := _make_screen()
    if screen == null:
        return
    screen.set("intro_running", false)
    screen.call("_finish_intro_only")
    _check(float(screen.call("_allowed_packet_gap_seconds")) >= 0.7,
        "Default packet-gap protection remains at least 700 ms")
    for index in range(13):
        _real_pose(0.5 + (0.004 if index % 2 == 0 else -0.004))
        # Worker-reported source FPS, not monitor redraw rate. 1.5 Hz means
        # 667 ms between real inferred frames; 40 UI ticks repeat old data.
        var status: Dictionary = pose.get("current_status")
        status["fps"] = 1.5
        pose.set("current_status", status)
        for _ui in range(40):
            screen.call("_process", FPS_DT)
        if int(screen.get("live_step")) > 0:
            break
    _check(int(screen.get("live_step")) == 1,
        "Adaptive 1.5Hz genuine student frames eventually complete real CENTER hold")
    _check((screen.get("measured_points") as Dictionary).has("center"),
        "Adaptive low-FPS calibration still stores actual student CENTER measurement")
    # A much longer outage must invalidate the partial RIGHT hold even when
    # the inferred FPS is low. No old packets can earn this missing time.
    _real_pose(0.82)
    var right_status: Dictionary = pose.get("current_status")
    right_status["fps"] = 1.5
    pose.set("current_status", right_status)
    screen.call("_process", 0.10)
    _check(float(screen.get("live_timer")) > 0.0,
        "Right-side hold starts on genuine first frame after sparse CENTER")
    screen.call("_process", 1.30)
    _check(is_zero_approx(float(screen.get("live_timer"))),
        "1.30s inference outage still resets low-FPS hold; never manufactures 3 seconds")
    screen.queue_free()
    await process_frame
    await process_frame
    pose.stop_camera()


func _check_udp_burst_distinct_packets() -> void:
    # Renderer still draws only the newest worker body pose, while calibration
    # consumes every source-unique locked-student frame in the bounded buffer.
    # Previous build lost N-1 genuine poses per UI tick; strict QA guards
    # against that regression without ever counting duplicate renderer redraws.
    _prepare_pose()
    var receiver := PacketPeerUDP.new()
    _check(receiver.bind(0, "127.0.0.1") == OK, "Local mock UDP receiver binds without camera")
    var sender := PacketPeerUDP.new()
    _check(sender.set_dest_address("127.0.0.1", receiver.get_local_port()) == OK,
        "Local synthetic UDP sender is restricted to loopback")
    pose.set("peer", receiver)
    pose.set("session_token", TOKEN)
    pose.set("worker_pid", OS.get_process_id())
    var now := Time.get_ticks_msec()
    pose.set("_launch_ms", now)
    pose.set("_last_packet_ms", now)
    pose.set("_latest_worker_packet_time", -1.0)
    var screen := _make_screen()
    _check(screen != null, "Live calibration scene starts before worker's burst")
    if screen == null:
        pose.set("worker_pid", -1)
        pose.stop_camera()
        sender.close()
        return
    screen.set("intro_running", false)
    screen.call("_finish_intro_only")
    var baseline_seq := int(pose.get("packet_sequence"))
    for index in range(8):
        var payload := {"kind": "pose", "token": TOKEN,
            "when": 100.0 + float(index) * 0.1,
            "state": "tracking", "pose": true, "x": 0.50,
            "lock_state": "locked", "locked_id": 17}
        _check(sender.put_packet(JSON.stringify(payload).to_utf8_buffer()) == OK,
            "Distinct # %d valid source pose packet delivered" % index)
    await process_frame
    _check(receiver.get_available_packet_count() == 8,
        "Eight distinct source datagrams are awaiting a single UI frame")
    pose.call("_process", FPS_DT)
    var frame_delta := int(pose.get("packet_sequence")) - baseline_seq
    print("CALIBRATION UDP BURST SOURCE_FRAMES=8 ACCOUNTED_UNIQUE_POSES=%d" % frame_delta)
    _check(frame_delta == 8,
        "All eight genuine distinct tracked person packets survive a single queued UDP burst")
    _check(int(pose.get("latest_pose_sample_id")) == 8,
        "Eight genuine locked-person UDP frames receive eight fresh sample IDs")
    var queued: Array = pose.call("get_pose_samples_after", 0)
    _check(queued.size() == 8, "Buffered source sample history preserves eight x/timestamp values")
    for i in range(queued.size()):
        var entry: Dictionary = queued[i]
        _check(int(entry.get("id", -1)) == i + 1 and
            is_equal_approx(float(entry.get("x", -1.0)), 0.5) and
            is_equal_approx(float(entry.get("when", -1.0)), 100.0 + 0.1 * i),
            "Each source sample retains its unique ID, tracked x and monotonic when")
    screen.call("_process", FPS_DT)
    _check((screen.get("live_samples") as Array).size() == 8,
        "Calibration consumes all eight real buffered samples, not one UI redraw")
    _check(int(screen.get("live_step")) == 0,
        "Eight simultaneous source frames do NOT bypass actual three-second hold")
    _check(bool(pose.get("current_status").get("pose", false)),
        "Newest source pose remains the visible calibrated student packet")
    _check(is_equal_approx(float(pose.get("player_x")), 0.5),
        "Latest student position remains authoritative despite burst processing")
    # Invalid and previously-seen timestamps must NOT inflate that count.
    var bad := [{"kind":"pose", "token":TOKEN, "when":100.7, "state":"tracking",
        "pose":true, "x":0.8, "lock_state":"locked", "locked_id":17},
        {"kind":"pose", "token":"old-token", "when":200.0, "state":"tracking",
        "pose":true, "x":0.1, "lock_state":"locked", "locked_id":99}]
    for packet in bad:
        sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
    await process_frame
    pose.call("_process", FPS_DT)
    _check(int(pose.get("packet_sequence")) == baseline_seq + frame_delta,
        "Duplicated timestamp and wrong session token never credit calibration again")
    _check(int(pose.get("latest_pose_sample_id")) == 8,
        "Stale duplicate and bad session token do not append to recent source poses")
    screen.call("_process", FPS_DT)
    _check((screen.get("live_samples") as Array).size() == 8,
        "Duplicate packets cannot enlarge the live calibration sample count")
    # A student who moves during a coalesced render tick may deliver multiple
    # valid tracked packets, but they are NOT eight stable CENTER observations.
    # Raw source samples must be inspected for each hold, not replaced by the
    # averaged/latest apparent body position.
    for index in range(8):
        var moving := {"kind":"pose", "token":TOKEN,
            "when":100.8 + float(index) * 0.1, "state":"tracking", "pose":true,
            "x":0.5 if index < 4 else 0.83, "lock_state":"locked", "locked_id":17}
        sender.put_packet(JSON.stringify(moving).to_utf8_buffer())
    await process_frame
    pose.call("_process", FPS_DT)
    screen.call("_process", FPS_DT)
    _check(int(pose.get("latest_pose_sample_id")) == 16,
        "All eight real frames from student movement are recorded as source frames")
    _check((screen.get("live_samples") as Array).is_empty() and
        int(screen.get("live_step")) == 0,
        "Cross-zone movement during one UDP burst INVALIDATES CENTER hold, not fake-stable")
    # Bystander/occluded report may update display status but never gives a
    # new source frame or passes a hold as the original tracked student.
    var bystander := {"kind": "pose", "token": TOKEN, "when": 101.6,
        "state": "ambiguous", "pose": false, "x": 0.1,
        "lock_state": "ambiguous", "locked_id": 99}
    sender.put_packet(JSON.stringify(bystander).to_utf8_buffer())
    await process_frame
    pose.call("_process", FPS_DT)
    _check(int(pose.get("latest_pose_sample_id")) == 16,
        "Ambiguous bystander packet never credited as a student pose sample")
    _check(not bool(pose.call("has_valid_pose")),
        "Bystander report immediately removes ability to finish calibration")
    # The mock PID is this very Godot process. Clear it BEFORE freeing the
    # screen, whose real _exit_tree otherwise calls stop_camera/OS.kill().
    pose.set("worker_pid", -1)
    screen.queue_free()
    await process_frame
    await process_frame
    pose.stop_camera()
    pose.set_process(false)
    sender.close()


func _real_pose(x: float) -> void:
    pose.set("active", true)
    pose.set("player_x", x)
    pose.set("last_pose_ms", Time.get_ticks_msec())
    pose.set("current_status", {"kind":"pose", "state":"tracking", "pose":true,
        "lock_state":"locked", "locked_id":17, "x":x})
    pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)


func _check_bounded_pose_source_history() -> void:
    _prepare_pose()
    var constants: Dictionary = pose.get_script().get_script_constant_map()
    var limit := int(constants.get("MAX_RECENT_POSE_SAMPLES", -1))
    _check(limit > 8 and limit <= 192,
        "PoseService recent real-source history is explicitly memory-bounded")
    if limit <= 8 or limit > 192:
        pose.stop_camera()
        return
    var records := limit + 24
    for i in range(records):
        pose.call("_record_fresh_calibration_pose",
            {"state":"tracking", "pose":true, "x":0.5}, 300.0 + 0.04 * i)
    var retained: Array = pose.call("get_pose_samples_after", 0)
    _check(retained.size() == limit,
        "Only newest %d real source samples remain after %d tracked frames" % [limit, records])
    _check(int(retained[0].get("id", -1)) == 25 and
        int(retained[-1].get("id", -1)) == records,
        "Capped FIFO discards oldest 24 frames without duplicating recent IDs")
    var newest: Array = pose.call("get_pose_samples_after", records - 1)
    _check(newest.size() == 1 and int(newest[0].get("id", -1)) == records,
        "Only true frames after supplied unique ID are returned")
    if not newest.is_empty():
        newest[0]["x"] = 0.1
        var unaffected: Array = pose.call("get_pose_samples_after", records - 1)
        _check(unaffected.size() == 1 and
            is_equal_approx(float(unaffected[0].get("x", -1.0)), 0.5),
            "Read-only snapshot cannot mutate true source history through caller")
    pose.stop_camera()
    _check((pose.call("get_pose_samples_after", 0) as Array).is_empty() and
        int(pose.get("latest_pose_sample_id")) == 0,
        "Explicit worker stop releases bounded sample history and unique IDs")


func _check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
        printerr("CALIBRATION SPARSE POSE FAIL: ", description)


func _finish() -> void:
    print("CALIBRATION SPARSE POSE: %s (%d checks, %d failures)" % [
        "PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
