extends SceneTree

## Occupancy-only live camera contract. NO webcam/YOLO/Python/DB/process spawn.
## Godot --headless --path . --script res://tools/test_pose_long_absence_safe_reacquisition.gd
const TOKEN := "offline-occupancy-only"
var pose: Node
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "Real PoseService autoload exists")
	if pose == null:
		_finish()
		return
	_session()
	_test_single_completed_calibration()
	_test_crowd_and_empty_invalidate()
	_test_long_absences_without_recalibration()
	_test_idless_one_person()
	_test_invalid_packet_security()
	_test_source_samples()
	_test_stalled_preview_and_restart()
	await _test_authentic_ordered_udp()
	pose.stop_camera()
	_check(pose.calibration.is_empty(), "New round explicitly clears old physical calibration")
	_finish()


func _session() -> void:
	pose.stop_camera()
	pose.set_process(false)
	pose.active = true
	pose.session_token = TOKEN
	pose._ever_tracked = true
	pose._worker_was_tracking = true
	pose._launch_ms = Time.get_ticks_msec()
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._latest_worker_packet_time = -1.0
	pose._apply_pose_packet(_packet(1, 3, 0.5), Time.get_ticks_msec())


func _packet(count: int = 1, id: int = -1, x: float = 0.5,
		state: String = "locked", age: Variant = 35, token: String = TOKEN,
		epoch: int = 1) -> Dictionary:
	return {
		"token": token, "kind": "pose", "state": "tracking",
		"pose": true, "camera": true, "camera_phase": "tracking",
		"people": count, "lock_state": state, "locked_id": id,
		"tracking_epoch": epoch, "needs_recalibration": epoch > 1,
		"lock_reacquired": epoch > 1,
		"x": x, "camera_frame_age_ms": age, "hand_up": true,
		"hand_observation_valid": true, "plane_steering": x,
		"plane_steering_valid": true, "plane_neutral_valid": true
	}


func _send(data: Dictionary) -> void:
	pose._apply_pose_packet(data, Time.get_ticks_msec())


func _test_single_completed_calibration() -> void:
	_check(pose.has_valid_pose(), "Fresh one-person stable YOLO frame moves the student")
	_check(pose.set_calibration(0.18, 0.50, 0.82, 3),
		"One CENTER/RIGHT/LEFT calibration stores valid measured physical positions")
	_check(pose.calibration == {"valid": true, "left": 0.18,
		"center": 0.50, "right": 0.82},
		"Completed physical calibration stores NO registered ID or epoch")
	_check(not pose.requires_player_recalibration(),
		"Legacy recalibration reroute is permanently disabled")
	var snapshot: Dictionary = pose.calibration.duplicate(true)
	pose.clear_calibration_for_reentry()
	_check(pose.calibration == snapshot,
		"Obsolete reentry helper cannot erase completed round calibration")
	_check(is_zero_approx(pose.normalized_body_x()),
		"Calibrated CENTER yields neutral camera movement")


func _test_crowd_and_empty_invalidate() -> void:
	for count in [0, 2, 3, 9]:
		_send(_packet(count, 3, 0.8))
		_check(not pose.has_valid_pose() and pose.player_x == -1.0,
			"%d YOLO people pauses movement immediately, even if pose=true" % count)
		_check(not pose.has_hand_raised() and not
			bool(pose.current_status.get("hand_up", false)),
			"%d YOLO people clears unsafe gesture state" % count)
		_check(is_zero_approx(pose.normalized_body_x()),
			"%d YOLO people cannot make ghost rightward movement" % count)
		_check(bool(pose.calibration.get("valid", false)),
			"%d YOLO people preserve the initial measurements" % count)
	_send(_packet(1, 3, 0.72, "waiting"))
	_check(not pose.has_valid_pose(), "One person without stable YOLO solo lock remains paused")
	_send(_packet(1, 3, 0.72, "locked"))
	_check(pose.has_valid_pose() and pose.normalized_body_x() > 0.0,
		"One newly stable person resumes the SAME round without another calibration")


func _test_long_absences_without_recalibration() -> void:
	var original: Dictionary = pose.calibration.duplicate(true)
	for gap in [5000, 15000, 60000]:
		_send(_packet(0, -1, 0.5, "lost"))
		pose.last_pose_ms = Time.get_ticks_msec() - gap
		_check(not pose.has_valid_pose(), "%d ms zero-person absence freezes game" % gap)
		# ByteTrack id, epoch, sticky needs_recalibration have no authority to
		# invalidate the original room-position measurements.
		var next_id: int = 100 + gap
		var next_epoch := 20 + int(gap / 1000)
		_send(_packet(1, next_id, 0.8, "locked", 42, TOKEN, next_epoch))
		_check(pose.has_valid_pose() and pose.normalized_body_x() > 0.0,
			"%d ms absence resumes with a DIFFERENT stable person ID" % gap)
		_check(pose.calibration == original and not pose.requires_player_recalibration(),
			"%d ms absence preserves exact three holds and never reroutes" % gap)
		_check(not pose.current_status.has("recalibration_required") and
			not pose.current_status.has("new_lock_id"),
			"%d ms absence never emits ID-change reroute flags" % gap)
		_send(_packet(0, -1, 0.5, "lost"))
		_send(_packet(1, 3, 0.2, "locked", 20, TOKEN, next_epoch + 1))
		_check(pose.has_valid_pose() and pose.normalized_body_x() < 0.0,
			"%d ms absence also allows recycled tracker ID/epoch" % gap)


func _test_idless_one_person() -> void:
	_send(_packet(0, -1, 0.5, "lost"))
	var idless := _packet(1, -1, 0.8, "locked", 35, TOKEN, 999)
	_send(idless)
	_check(pose.has_valid_pose() and pose.normalized_body_x() > 0,
		"Stable solo person with locked_id=-1 moves with NO registration")
	idless.erase("locked_id")
	_send(idless)
	_check(pose.has_valid_pose(),
		"Stable solo person with NO locked_id field still moves")
	_check(pose.calibration.has("left") and not pose.calibration.has("locked_id"),
		"IDless recovery preserves completed left/right physical range")
	_check(pose.set_stationary_plane_calibration(0.5, -1, 0.5),
		"Human Plane initial neutral calibration accepts NO tracker ID")
	_check(not pose.plane_calibration.has("locked_id") and
		pose.has_stationary_plane_pose(),
		"Human Plane uses same fresh solo occupancy gate without stored ID")
	_send(_packet(2, -1, 0.8))
	_check(not pose.has_stationary_plane_pose(),
		"Human Plane immediately pauses on second visible YOLO person")
	_send(_packet(1, 955, 0.6, "locked", 20, TOKEN, 234))
	_check(pose.has_stationary_plane_pose(),
		"Human Plane resumes from new ID and epoch without new neutral calibration")
	_check(pose.set_calibration(0.18, 0.5, 0.82, -1),
		"Catch physical calibration can be reselected only at new round setup")


func _test_invalid_packet_security() -> void:
	for bogus in [
		_packet(1, -1, 0.5, "waiting"),
		_packet(1, -1, 0.5, "ambiguous"),
		_packet(0, 4, 0.5),
		_packet(2, 4, 0.5),
		_packet(1, 4, 0.5, "locked", 651),
		_packet(1, 4, 0.5, "locked", NAN),
		_packet(1, 4, 0.5, "locked", -1),
		_packet(1, 4, 0.5, "locked", "old")
	]:
		_send(bogus)
		_check(not pose.has_valid_pose() and pose.player_x == -1.0,
			"Unsafe/ambiguous/stale YOLO packet cannot move player: %s" % str(bogus))
	var bad_camera := _packet(1)
	bad_camera["camera"] = false
	_send(bad_camera)
	_check(not pose.has_valid_pose(), "Camera=false status cannot resurrect ghost person")
	var wrong_token := _packet(1, 6, 0.3, "locked", 15, "previous-session")
	_send(wrong_token)
	_check(not pose.has_valid_pose(), "Rejected previous session token cannot revive movement")
	var no_count := _packet(1)
	no_count.erase("people")
	_send(no_count)
	_check(not pose.has_valid_pose(), "Missing real YOLO occupancy count never controls game")
	var fractional := _packet(1)
	fractional["people"] = 1.5
	_send(fractional)
	_check(not pose.has_valid_pose(), "Fractional person count cannot be interpreted as solo")
	_send(_packet(1, -1, 0.5, "locked"))
	_check(pose.has_valid_pose(), "Fresh stable SOLO after malformed packets recovers normally")


func _test_source_samples() -> void:
	pose._recent_pose_samples.clear()
	pose.latest_pose_sample_id = 0
	pose._record_fresh_calibration_pose(_packet(2), 100.0)
	pose._record_fresh_calibration_pose(_packet(0), 101.0)
	pose._record_fresh_calibration_pose(_packet(1, -1, 0.5, "waiting"), 102.0)
	pose._record_fresh_calibration_pose(_packet(1, -1, 0.5, "locked", 900), 103.0)
	_check(pose.latest_pose_sample_id == 0,
		"Multiple/zero/unstable/stale frames never count towards physical hold")
	pose._record_fresh_calibration_pose(_packet(1, -1, 0.5), 104.0)
	_check(pose.latest_pose_sample_id == 1 and
		int(pose.get_pose_samples_after(0)[0].get("people", -1)) == 1,
		"First IDless stable fresh SOLO sample has explicit one-person occupancy")
	pose._record_fresh_calibration_pose(_packet(1, 1234, 0.6), 104.0)
	_check(pose.latest_pose_sample_id == 1, "Repeated source timestamp never double-counts hold")
	pose._record_fresh_calibration_pose(_packet(1, 9999, 0.6), 105.0)
	_check(pose.latest_pose_sample_id == 2 and
		not pose.get_pose_samples_after(0)[1].has("locked_id"),
		"Changed ByteTrack ID can contribute second fresh solo calibration packet")


func _test_stalled_preview_and_restart() -> void:
	var previous: Dictionary = pose.calibration.duplicate(true)
	var fake_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	pose.preview_texture = ImageTexture.create_from_image(fake_image)
	pose._last_preview_ms = 1000
	var cleared := [false]
	var listener := func(texture: Texture2D) -> void:
		if texture == null:
			cleared[0] = true
	pose.preview_updated.connect(listener)
	pose._expire_preview(3000)
	_check(pose.preview_texture == null and cleared[0],
		"Expired camera preview clears ghost skeleton from subscribed screens")
	pose.preview_updated.disconnect(listener)
	pose._last_packet_ms = Time.get_ticks_msec() - 6200
	pose._worker_was_tracking = true
	_check(String(pose._camera_watchdog_status(Time.get_ticks_msec())) == "stream_stalled",
		"Silent 5.5s worker stream triggers bounded restart")
	pose._schedule_restart(Time.get_ticks_msec())
	_check(pose._restart_pending and not pose.has_valid_pose(),
		"Restart safely pauses movement and never keeps old pose")
	_check(pose.calibration == previous and not pose.requires_player_recalibration(),
		"Process restart retains EXACT completed physical calibration")
	pose._restart_pending = false
	pose._latest_worker_packet_time = -1.0
	pose._last_packet_ms = Time.get_ticks_msec()
	pose.session_token = "fresh-worker"
	_send(_packet(1, -1, 0.7, "locked", 20, "fresh-worker", 23))
	_check(pose.has_valid_pose() and pose.calibration == previous,
		"Fresh worker SOLO resumes same round even with new token/ID/epoch")
	pose.session_token = TOKEN


func _test_authentic_ordered_udp() -> void:
	# Validate real status parser's strict worker source ordering, not merely a
	# direct helper method. This uses localhost fake UDP, no camera process.
	pose._restart_pending = false
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK, "Offline UDP receiver bound")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", pose.peer.get_local_port())
	pose.worker_pid = OS.get_process_id() # Keep watchdog from launching helper.
	pose._launch_ms = Time.get_ticks_msec()
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._latest_worker_packet_time = -1.0
	var packet := _packet(1, -1, 0.65)
	packet["when"] = 100.0
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.has_valid_pose(), "Fresh authenticated UDP YOLO frame drives solo movement")
	var first_seq: int = pose.packet_sequence
	packet["x"] = 0.15
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer()) # Duplicate when.
	packet["when"] = 99.0
	sender.put_packet(JSON.stringify(packet).to_utf8_buffer()) # Reordered when.
	await process_frame
	pose._process(0.016)
	_check(pose.packet_sequence == first_seq and pose.player_x > 0.5,
		"Duplicate and reordered source packets cannot rewind/reanimate old pose")
	var second := _packet(2, -1, 0.3)
	second["when"] = 101.0
	sender.put_packet(JSON.stringify(second).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(not pose.has_valid_pose() and pose.player_x == -1.0,
		"Fresh two-person UDP packet immediately pauses camera movement")
	var recovered := _packet(1, -1, 0.7, "locked", 20, TOKEN, 734)
	recovered["when"] = 102.0
	sender.put_packet(JSON.stringify(recovered).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.has_valid_pose() and not pose.requires_player_recalibration(),
		"Fresh stable solo UDP after crowd resumes without any ID registration")
	pose.worker_pid = -1 # NEVER kill our own Godot process in stop_camera!
	sender.close()
	pose.peer.close()
	pose.peer = null


func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)
		printerr("SOLO RESUME FAIL: ", why)


func _finish() -> void:
	print("SOLO OCCUPANCY LONG ABSENCE: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
