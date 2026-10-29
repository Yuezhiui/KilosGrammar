extends SceneTree

## New policy: calibration is performed ONCE at new-round entry with a single
## fresh person, not a registered ByteTrack ID. Never launches a webcam/DB.
## --headless --path . --script res://tools/test_calibration_single_person_round.gd
const SCENE := "res://ui/vision/calibration/calibration.tscn"
var checks := 0
var failures: Array[String] = []
var pose: Node
var packed: PackedScene
var source_when := 1000.0


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(25.0).timeout
	_assert(false, "single-person synthetic test watchdog")
	_finish()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	packed = load(SCENE) as PackedScene
	if pose == null or packed == null:
		_assert(false, "PoseService autoload and calibration scene loaded")
		_finish()
		return
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		await _stress_round(activity)
		await _check_fresh_new_round(activity)
	pose.worker_pid = -1 # Mock PID is Godot itself; never let stop_camera kill it.
	pose.stop_camera()
	_finish()


func _new_screen(activity: String) -> Control:
	# Simulated model is already warm; set_context must neither reopen the
	# camera nor preserve the prior round's calibration for this new round.
	if pose.peer == null:
		pose.peer = PacketPeerUDP.new()
		_assert(pose.peer.bind(0, "127.0.0.1") == OK,
			activity + " / synthetic loopback camera transport is bound")
	pose.worker_pid = OS.get_process_id() # Liveness ONLY, no subprocess/camera.
	pose.set("active", true)
	pose.set("session_token", "same-warm-camera")
	pose.set("_camera_start_requested", true)
	pose.set("_model_prestarting", true)
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.set_context({"activity": activity, "entry_source": "play",
		"camera_requested": true, "game_mode": "Seconds", "keyboard_mode": false})
	_assert(pose.active and pose.peer != null and pose.worker_pid == OS.get_process_id() and
		String(pose.session_token) == "same-warm-camera" and
		bool(pose.get("_camera_start_requested")),
		activity + " / preserves authenticated synthetic warm camera session")
	_assert(not bool((pose.calibration as Dictionary).get("valid", false)),
		activity + " / new round cannot inherit previous calibration")
	screen.call("_process", 3.01)
	return screen


func _stress_round(activity: String) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var screen := _new_screen(activity)
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		routes.append({"route": route, "payload": payload.duplicate(true)}))
	var order: Array = screen.call("_capture_order")
	var balloon := activity == "Balloon Popping"
	var expected_order := (["CENTER"] if activity == "Human Plane" else
		["LEFT", "CENTER", "RIGHT"] if balloon else ["CENTER", "RIGHT", "LEFT"])
	_assert(order == expected_order,
		activity + " / correct once-per-round physical stage order")
	var first_zone_x := 0.2 if balloon else 0.5
	var second_zone_x := 0.5 if balloon else 0.8
	var third_zone_x := 0.8 if balloon else 0.2
	var first_zone_name := "left" if balloon else "center"
	var second_zone_name := "center" if balloon else "right"
	var third_zone_name := "right" if balloon else "left"
	# Multiple visible people/zero people/unknown people: even an accidentally
	# retained 'pose':true and x=0.5 must NEVER earn hold time or route.
	for count in [0, 2, 4, -1]:
		_push(screen, 0.50, 0.20, count)
		_assert(int(screen.get("live_step")) == 0 and
			is_zero_approx(float(screen.get("live_timer"))) and
			(screen.get("live_samples") as Array).is_empty() and routes.is_empty(),
			activity + " / rejects people=%d despite synthetic pose=true" % count)
	# Five real packets may start an incomplete first-zone hold; a second person
	# entering immediately resets that hold, but not earlier completed stages.
	for _i in range(5):
		_push(screen, first_zone_x, 0.125, 1, -1)
	_assert((screen.get("live_samples") as Array).size() == 5 and
		int(screen.get("live_step")) == 0,
		activity + " / five unregistered solo packets start real first-zone hold")
	_push(screen, first_zone_x, 0.125, 2)
	_assert((screen.get("live_samples") as Array).is_empty() and
		is_zero_approx(float(screen.get("live_timer"))),
		activity + " / bystander cancels partial solo hold immediately")
	# A >5s absence cannot earn stored time or mutate calibration, even when
	# the synthetic service remains active with its warm camera session.
	_set_missing(0)
	for _i in range(32):
		screen.call("_process", 0.20)
	_assert(int(screen.get("live_step")) == 0 and
		is_zero_approx(float(screen.get("live_timer"))) and routes.is_empty(),
		activity + " / >6s absence freezes calibration without ghost frames")
	# A returning freshly tracked person may use a DIFFERENT numeric tracking
	# ID or NO ID at all; neither changes the number of required holds.
	if balloon:
		_complete_balloon_zone(screen, first_zone_x, "LEFT", -1)
	else:
		var first_count := 9 if activity == "Human Plane" else 34
		for _i in range(first_count):
			_push(screen, first_zone_x, 0.40 if activity == "Human Plane" else 0.125, 1, -1)
	_assert(int(screen.get("live_step")) == 1 and
		(screen.get("measured_points") as Dictionary).has(first_zone_name),
		activity + " / fresh no-ID solo first-zone hold succeeds after long absence")
	if activity != "Human Plane":
		# Disrupt the SECOND floor zone: only its current hold restarts. The
		# finished first zone remains measured even after a crowd arrives.
		for _i in range(7):
			_push(screen, second_zone_x, 0.15, 1, 19)
		_push(screen, second_zone_x, 0.15, 2, 19)
		_assert(int(screen.get("live_step")) == 1 and
			(screen.get("measured_points") as Dictionary).has(first_zone_name) and
			is_zero_approx(float(screen.get("live_timer"))),
			activity + " / crowd on second zone retains first completed zone")
		if balloon:
			_complete_balloon_zone(screen, second_zone_x, "CENTER", 301)
		else:
			for _i in range(25):
				_push(screen, second_zone_x, 0.15, 1, 301)
		_assert(int(screen.get("live_step")) == 2 and
			(screen.get("measured_points") as Dictionary).has(second_zone_name),
			activity + " / new tracker ID completes second zone without redoing first")
		# Long absence on the THIRD zone: previous two remain.
		for _i in range(5):
			_push(screen, third_zone_x, 0.15, 1, 302)
		_set_missing(0)
		for _i in range(30):
			screen.call("_process", 0.20)
		_assert(int(screen.get("live_step")) == 2 and
			is_zero_approx(float(screen.get("live_timer"))) and
			(screen.get("measured_points") as Dictionary).has(first_zone_name) and
			(screen.get("measured_points") as Dictionary).has(second_zone_name),
			activity + " / >5s absence interrupts third zone but keeps past floor measurements")
		if balloon:
			_complete_balloon_zone(screen, third_zone_x, "RIGHT", -1)
		else:
			for _i in range(25):
				_push(screen, third_zone_x, 0.15, 1, -1)
		_assert(int(screen.get("live_step")) == 3,
			activity + " / return with no ID completes final physical third zone")
	var calibration: Dictionary = pose.calibration
	_assert(bool(calibration.get("valid", false)) and not calibration.has("locked_id") and
		int(screen.get("live_step")) == order.size() and bool(screen.get("transition_queued")),
		activity + " / one completed round has no registered ID binding")
	if activity == "Human Plane":
		_assert(bool((pose.plane_calibration as Dictionary).get("neutral_only", false)) and
			not calibration.has("left") and not calibration.has("right"),
			activity + " / real full T-pose 3.0s/8+ packets without invented side positions")
	else:
		_assert(calibration.has("center") and calibration.has("left") and calibration.has("right"),
			activity + " / all three real physical floor positions measured")
	# A FINISHED authentic round must not restart on motion, zero people,
	# multiple people, disappearing wrists, or an expired source. Each of these
	# conditions blocks GO until freshly authenticated raw SOLO returns.
	var measured: Dictionary = screen.measured_points.duplicate(true)
	_assert(bool(screen.get("success_running")) and bool(screen.get("transition_queued"))
		and routes.is_empty(), activity + " / physical holds open separate 3s SUCCESS screen")
	for _i in range(12):
		_push_raw_solo_without_pose(screen, 0.15)
	_assert(bool(screen.get("success_running")) and routes.is_empty()
		and screen.measured_points == measured,
		activity + " / pose joints may disappear during SUCCESS with SOLO box")
	var success_before: float = screen.success_elapsed
	for count in [2, 0]:
		_push(screen, 0.50, 0.15, count)
		_assert(routes.is_empty() and bool(screen.get("success_running"))
			and int(screen.get("live_step")) == order.size()
			and screen.measured_points == measured
			and is_equal_approx(float(screen.success_elapsed), success_before),
			activity + " / raw %d people freeze success, no replay or erased holds" % count)
	# Not enough source freshness even if the cached camera still shows a person.
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 100
	screen.call("_process", 6.0)
	_assert(routes.is_empty() and bool(screen.get("success_running"))
		and screen.measured_points == measured
		and is_equal_approx(float(screen.success_elapsed), success_before),
		activity + " / 6s stale source freezes SUCCESS without new holds")
	# Require complete separate 3-second SOLO presence before gameplay.
	var prior_success: float = screen.success_elapsed
	var before_ticks := maxi(0, floori((3.0 - prior_success - 0.16) / 0.15))
	for _i in range(before_ticks):
		_push_raw_solo_without_pose(screen, 0.15)
	_assert(routes.is_empty(), activity + " / no handoff before full separate 3s success")
	for _i in range(4):
		_push_raw_solo_without_pose(screen, 0.15)
	_assert(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay" and
		bool((routes[0].get("payload", {}) as Dictionary).get("start_countdown", false)),
		activity + " / fresh authentic SOLO authorizes ONE gameplay handoff")
	screen.call("_continue_flow", false)
	_assert(routes.size() == 1, activity + " / duplicate Continue cannot launch twice")
	_assert(bool(screen.get("passing_to_ready")) and
		bool((pose.calibration as Dictionary).get("valid", false)) and
		screen.measured_points == measured,
		activity + " / post-success routing preserves original floor/T-pose measurement")
	screen.queue_free()
	await process_frame
	await process_frame
	_assert(pose.active and bool((pose.calibration as Dictionary).get("valid", false)),
		activity + " / camera and calibration transfer to gameplay")


func _check_fresh_new_round(activity: String) -> void:
	# A retry begins a NEW round, so previously completed measurements cannot
	# be reused to bypass the new real hold sequence.
	var old: Dictionary = pose.calibration.duplicate()
	var old_plane: Dictionary = pose.plane_calibration.duplicate()
	_assert(bool(old.get("valid", false)), activity + " / prior round measurements existed")
	var screen := _new_screen(activity)
	var routes: Array[String] = []
	screen.requested.connect(func(route: String, _payload: Dictionary) -> void:
		routes.append(route))
	screen.call("_continue_flow", false)
	_assert(routes.is_empty() and int(screen.get("live_step")) == 0 and
		not bool((pose.calibration as Dictionary).get("valid", false)),
		activity + " / Retry requires remeasurement, no former-round bypass")
	# A caller may reuse an already completed calibration Control instead of
	# instantiating a new scene. Explicit SAME-activity retry is a fresh round.
	pose.calibration = old.duplicate(true)
	pose.plane_calibration = old_plane.duplicate(true)
	screen.set("live_step", (screen.call("_capture_order") as Array).size())
	screen.set("passing_to_ready", true)
	screen.call("set_context", {"activity": activity, "entry_source": "play",
		"camera_requested": true, "new_round": true, "keyboard_mode": false})
	_assert(int(screen.get("live_step")) == 0 and
		not bool(screen.get("passing_to_ready")) and
		not bool((pose.calibration as Dictionary).get("valid", false)) and
		not bool((pose.plane_calibration as Dictionary).get("valid", false)),
		activity + " / SAME-activity reused-screen retry discards earlier round")
	screen.call("_continue_flow", false)
	_assert(routes.is_empty() and pose.active and
		String(pose.session_token) == "same-warm-camera",
		activity + " / same-screen retry cannot bypass holds or restart warm camera")
	screen.queue_free()
	pose.worker_pid = -1 # Mock liveness is the Godot test process itself.
	await process_frame
	await process_frame
	pose.stop_camera()


func _complete_balloon_zone(screen: Control, x: float, zone: String,
		track_id: int) -> void:
	# One zone means TWO separately fresh 3.0s holds. The first must prove
	# BOTH hands lowered; the second must prove BOTH lifted. We deliberately
	# send a full bogus one-hand hold before each phase; aggregate hand_up is
	# never sufficient even when pose=true and people=1.
	var zone_index := int(screen.live_step)
	var zone_key := zone.to_lower()
	for phase in range(2):
		_assert(int(screen.live_step) == zone_index
			and int(screen.balloon_pose_phase) == phase,
			"Balloon " + zone + " / correct bilateral phase begins")
		for _i in range(24):
			_push(screen, x, 0.15, 1, track_id, true)
		_assert(int(screen.live_step) == zone_index
			and int(screen.balloon_pose_phase) == phase
			and is_zero_approx(float(screen.live_timer)),
			"Balloon " + zone + " / 3.6s aggregate one-hand UP never proves BOTH wrist positions")
		for _i in range(19):
			_push(screen, x, 0.15, 1, track_id)
		_assert(int(screen.live_step) == zone_index
			and int(screen.balloon_pose_phase) == phase,
			"Balloon " + zone + " / 2.85s source-fresh bilateral hold cannot complete early")
		for _i in range(4):
			_push(screen, x, 0.15, 1, track_id)
		_assert(int(screen.live_step) == zone_index + (1 if phase == 1 else 0)
			and int(screen.balloon_pose_phase) == (0 if phase == 1 else 1),
			"Balloon " + zone + " / full 3s + 8+ source frames advances exactly one phase")
		if phase == 0:
			_assert((screen.measured_points as Dictionary).has(zone_key)
				and not bool((pose.calibration as Dictionary).get("valid", false)),
				"Balloon " + zone + " / DOWN captures real floor X but no early valid calibration")


func _set_missing(people: int) -> void:
	var packet := {"token": pose.session_token, "kind": "pose", "state": "tracking",
		"camera": true, "camera_phase": "tracking", "pose": false,
		"people": people, "x": -1.0, "lock_state": "lost",
		"camera_frame_age_ms": 20, "fps": 8.0, "detail": "No one visible"}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())


func _push(screen: Control, x: float, dt: float,
		people: int, track_id: int = -1, one_hand_only: bool = false) -> void:
	pose.set("active", true)
	var balloon := String(screen.context.get("activity", "")) == "Balloon Popping"
	var raised_phase := balloon and int(screen.balloon_pose_phase) == 1
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "camera_phase": "tracking", "pose": true,
		"camera": true, "people": people, "x": x,
		"lock_state": "locked", "camera_frame_age_ms": 20,
		"plane_steering": 0.0, "plane_steering_valid": true,
		"plane_neutral_valid": true, "fps": 8.0,
		"hand_observation_valid": true, "plane_t_pose_valid": true,
		"hand_up": raised_phase or one_hand_only,
		# These are strict, SAME source frame bilateral wrist observations;
		# hand_up remains an either-hand gameplay flag and cannot prove either.
		"both_hands_up": people == 1 and raised_phase and not one_hand_only,
		"both_hands_down": people == 1 and balloon and not raised_phase and not one_hand_only}
	if track_id >= 0:
		packet["locked_id"] = track_id
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if people == 1:
		# Camera UI smoothing is not the raw source pose; keep stable source X.
		pose.player_x = x
	source_when += dt
	pose.call("_record_fresh_calibration_pose", packet, source_when)
	screen.call("_process", dt)


func _push_raw_solo_without_pose(screen: Control, dt: float) -> void:
	# A child genuinely remains visible to raw YOLO while joints/wrists flicker.
	# Such occupancy can complete SUCCESS but cannot create physical samples.
	source_when += dt
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"people": 1, "pose": false, "lock_state": "pending", "x": -1.0,
		"camera_frame_age_ms": 20, "fps": 8.0,
		"hand_observation_valid": false, "hand_up": false}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	screen.call("_process", dt)


func _assert(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("SINGLE PERSON CALIBRATION FAIL: ", detail)


func _finish() -> void:
	if pose != null:
		pose.worker_pid = -1
		pose.stop_camera()
	print("SINGLE PERSON CALIBRATION PER ROUND: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
