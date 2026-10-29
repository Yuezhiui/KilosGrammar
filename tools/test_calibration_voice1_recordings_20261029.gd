extends SceneTree

# The user's actual eleven VOICE1 recordings, imported without synthesis.
# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_voice1_recordings_20261029.gd
# No webcam/YOLO, database, speakers or production asset modifications.
const Voice = preload("res://ui/vision/calibration/calibration_voice.gd")
const SCENE := "res://ui/vision/calibration/calibration.tscn"
const EXPECTED := {
	"center": "center.wav",
	"stay_center": "stay_center.wav",
	"left": "left.wav",
	"stay_left": "stay_left.wav",
	"right": "right.wav",
	"stay_right": "stay_right.wav",
	"t_pose": "t_pose.wav",
	"raise_left_hand": "raise_left_hand.wav",
	"raise_right_hand": "raise_right_hand.wav",
	"raise_both_hands": "raise_both_hands.wav",
	"success": "success.wav",
}
const BALLOON_ORDER := ["CENTER", "RIGHT", "LEFT"]
const CATCH_ORDER := ["CENTER", "RIGHT", "LEFT"]
# SHA-256 of the eleven genuine user-supplied VOICE1 source WAVs.
# The exact bytes are checked, not simply filenames or decoded audio lengths.
const EXPECTED_SHA256 := {
	"center.wav": "291FEED06375946E883671641F16EBB7BBF428B9FE5DDF8730B61FFF18E7E368",
	"left.wav": "E0E2D3E3D7220C687E6938498B0A7B665C9CBCD01427080C430AF60FE87F58B5",
	"raise_both_hands.wav": "2DC3AE1D2C3B7092DA1400C2E31210558374FD880298649BDDFF227BDE6DC025",
	"raise_left_hand.wav": "659714A4942535B020F6DA38C1BCDCCAACA07F02B22058140A9A3E978036AB34",
	"raise_right_hand.wav": "BE73928E75FC06464D546F9DD59F0DC95C51360862DBABF797A71C577125E825",
	"right.wav": "7B5443F45BFDEDE7E0057463858E7FEFDBD31F32283D96B40BA5BE49447DF349",
	"stay_center.wav": "334F0A8E37EA89EF0F4F127C5E2DA93588412D1CA410A44395241B90C4045E47",
	"stay_left.wav": "4433D100E9F7C8DA214C397B52EB6B5C9F9A1CDF863CAC798B2669ED83137756",
	"stay_right.wav": "1AC3193C823915D649E52C21D0BA817ABF5888114C913A2200F8075E68E1468B",
	"success.wav": "FFB200D356ACF6410B8B29F60C7064CF43B551BF8C338B89FF78FF508170758B",
	"t_pose.wav": "F82B22BDE4C1152E863621E94695CEC50411C782AE98963C88BE19C31DC7DAB8",
}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var loaded := load(SCENE) as PackedScene
	_check(loaded != null, "Calibration scene parses with source WAVs imported")
	if loaded == null:
		_finish()
		return
	_check(not ResourceLoader.exists(Voice.VOICE_DIR + "raise_hand.wav"),
		"No generic one-hand VOICE1 recording was fabricated")
	_check(EXPECTED.size() == 11 and EXPECTED_SHA256.size() == 11,
		"Exactly eleven genuine VOICE1 recordings have pinned SHA-256 digests")
	var menu_source := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(menu_source.contains('route in ["calibration", "gameplay", "pause"]'),
		"Title music is paused while teacher/student hears calibration instructions")
	var voice := Voice.new()
	root.add_child(voice)
	var player := voice.get_node_or_null("PromptPlayer") as AudioStreamPlayer
	_check(player != null and player.bus == "KilosSFX", "One prompt player uses Settings-controlled effects bus")
	for cue in EXPECTED:
		var name := String(EXPECTED[cue])
		var path := Voice.VOICE_DIR + name
		_check(ResourceLoader.exists(path), "User-supplied PCM file resolves: " + name)
		var bytes := FileAccess.get_file_as_bytes(path)
		_check(bytes.size() > 44 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF"
			and bytes.slice(8, 12).get_string_from_ascii() == "WAVE",
			"Original source RIFF/WAVE file is intact: " + name)
		if bytes.size() >= 36:
			_check(bytes.decode_u16(20) == 1 and bytes.decode_u16(22) == 1
				and bytes.decode_u32(24) == 24000 and bytes.decode_u16(34) == 16,
				"Original source is 24kHz mono PCM16: " + name)
		_check(FileAccess.get_sha256(path).to_upper() == String(EXPECTED_SHA256[name]),
			"SHA-256 matches genuine user-supplied audio: " + name)
		var audio := load(path) as AudioStreamWAV
		_check(audio != null, "Godot imported a WAV AudioStream: " + name)
		if audio != null:
			_check(audio.mix_rate == 24000 and not audio.stereo and audio.get_length() > 0.4,
				"24kHz mono, nonempty authentic instruction: " + name)
		_check(voice.play_stage("SUPPLIED:" + String(cue), String(cue)),
			"Real recording plays once for cue: " + String(cue))
		_check(player.stream is AudioStreamWAV and not voice.play_stage("SUPPLIED:" + String(cue), String(cue)),
			"Exactly one audio player and no repeated prompt for: " + String(cue))
	_check(voice.get_children().size() == 1, "All eleven recordings reuse one player")
	voice.queue_free()
	await process_frame

	# Call the real scene's instruction boundary WITHOUT set_context(), which
	# intentionally starts a physical camera. We only inject authored activity
	# metadata and inspect which real audio resource is selected.
	var screen := loaded.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.set("intro_running", false)
	var narrator := screen.get_node_or_null("CalibrationVoice") as Node
	var speaker := narrator.get_node_or_null("PromptPlayer") as AudioStreamPlayer if narrator != null else null
	_check(narrator != null and speaker != null, "Calibration creates one actual narration helper")
	if narrator != null and speaker != null:
		for activity in ["Catch the Word", "Balloon Popping"]:
			narrator.call("reset_for_new_attempt")
			screen.set("context", {"activity": activity})
			var order: Array = BALLOON_ORDER if activity == "Balloon Popping" else CATCH_ORDER
			_check(screen.call("_capture_order") == order,
				activity + " has correct physical zone order")
			_check(float(screen.call("_hold_seconds")) == 3.0,
				activity + " physically holds each stage for 3 seconds")
			if activity == "Balloon Popping":
				_check(order.size() * 2 * float(screen.call("_hold_seconds")) == 18.0,
					"Balloon completes six independent bilateral holds totaling 18 valid seconds")
			for zone in range(order.size()):
				var target: String = String(order[zone]).to_lower()
				screen.set("live_step", zone)
				screen.set("balloon_pose_phase", 0)
				screen.call("_set_stage_instruction")
				if activity == "Balloon Popping":
					if target == "center":
						_check(speaker.stream == narrator.call("_load_cue", "hands_down"),
							"Balloon CENTER uses cloned BOTH HANDS DOWN cue")
						_check(String(narrator.get("_pending_followup_cue")).is_empty(),
							"Balloon CENTER does not queue a second movement cue")
					else:
						_check(speaker.stream == narrator.call("_load_cue", target),
							"Balloon " + target + " starts with supplied MOVE recording")
						_check(String(narrator.get("_pending_followup_cue")) == "hands_down",
							"Balloon " + target + " queues cloned hands-down recording")
						speaker.finished.emit()
						_check(speaker.stream == narrator.call("_load_cue", "hands_down"),
							"Balloon " + target + " plays hands-down only after MOVE finishes")
				else:
					_check(speaker.stream == narrator.call("_load_cue", target),
						activity + " " + target + " starts with supplied MOVE recording")
					_check(String(narrator.get("_pending_followup_cue")) == "stay_" + target,
						activity + " " + target + " queues corresponding STAY recording")
					speaker.finished.emit()
					_check(speaker.stream == narrator.call("_load_cue", "stay_" + target),
						activity + " " + target + " plays STAY only after MOVE finishes")
				var remembered := (narrator.get("_played_stages") as Dictionary).size()
				screen.call("_set_stage_instruction")
				_check((narrator.get("_played_stages") as Dictionary).size() == remembered,
					activity + " " + target + " repeated pose refresh cannot restart voice")
				if activity == "Balloon Popping":
					_check((narrator.get("_played_stages") as Dictionary).has(
						"Balloon Popping:%s:default" % String(order[zone])),
						"Balloon " + target + " DOWN phase announced exactly once")
					_check(screen.call("_sample_matches_pose_phase", {
						"hand_observation_valid": true, "both_hands_down": true,
						"both_hands_up": false, "hand_up": false}),
						"Balloon " + target + " DOWN requires both observed lowered hands")
					_check(not screen.call("_sample_matches_pose_phase", {
						"hand_observation_valid": true, "both_hands_down": false,
						"both_hands_up": false, "hand_up": true}),
						"Balloon " + target + " DOWN rejects ambiguous/one-hand packets")
					screen.set("balloon_pose_phase", 1)
					screen.call("_set_stage_instruction")
					_check(speaker.stream == narrator.call("_load_cue", "raise_both_hands"),
						"Balloon " + target + " raises BOTH hands with the real supplied VOICE1 WAV")
					_check((narrator.get("_played_stages") as Dictionary).has(
						"Balloon Popping:%s:raised" % String(order[zone])),
						"Balloon " + target + " UP phase announced exactly once")
					_check(screen.call("_sample_matches_pose_phase", {
						"hand_observation_valid": true, "both_hands_down": false,
						"both_hands_up": true, "hand_up": true}),
						"Balloon " + target + " UP accepts two physically raised hands")
					_check(not screen.call("_sample_matches_pose_phase", {
						"hand_observation_valid": true, "both_hands_down": false,
						"both_hands_up": false, "hand_up": true}),
						"Balloon " + target + " UP rejects one-hand gesture")
					_check(not screen.call("_sample_matches_pose_phase", {
						"hand_observation_valid": false, "both_hands_down": false,
						"both_hands_up": true, "hand_up": true}),
						"Balloon " + target + " UP rejects unverified wrists")
					_check(String(narrator.get("_pending_followup_cue")).is_empty(),
						"Balloon raised-hand phase cannot replay an old STAY recording")
					var played := (narrator.get("_played_stages") as Dictionary).size()
					screen.call("_set_stage_instruction")
					_check((narrator.get("_played_stages") as Dictionary).size() == played
						and speaker.stream == narrator.call("_load_cue", "raise_both_hands"),
						"Balloon " + target + " repeated packets cannot restart bilateral cue")
		narrator.call("reset_for_new_attempt")
		screen.set("context", {"activity": "Human Plane"})
		screen.set("live_step", 0)
		screen.call("_set_stage_instruction")
		_check(speaker.stream == narrator.call("_load_cue", "t_pose"),
			"Human Plane uses proper horizontal T-pose recording, not raise-both-hands")
		narrator.call("play_stage", "Human Plane:success", "success")
		_check(speaker.stream == narrator.call("_load_cue", "success"),
			"Calibration success actually uses the supplied success WAV")
		_check(not narrator.call("play_stage", "Human Plane:success", "success"),
			"Success narration cannot repeat")
		# A crowd, an empty camera, or stale/no-source observations must not
		# advance a six-phase hold or cause fresh voice announcements. This is
		# a no-hardware safety smoke test; source-authenticated 3-second holds
		# are exercised by test_calibration_balloon_bilateral_20261029.gd.
		var pose := root.get_node_or_null("PoseService")
		_check(pose != null, "PoseService available for absent/crowd regression")
		if pose != null:
			pose.set_process(false)
			pose.set("worker_pid", -1) # No real worker and never terminate a process.
			pose.set("active", true)
			pose.set("player_x", 0.2)
			pose.set("last_pose_ms", Time.get_ticks_msec())
			narrator.call("reset_for_new_attempt")
			screen.set("context", {"activity": "Balloon Popping"})
			screen.set("live_step", 0)
			screen.set("balloon_pose_phase", 0)
			screen.call("_set_stage_instruction")
			var heard := (narrator.get("_played_stages") as Dictionary).size()
			for people in [0, 2, 3]:
				pose.set("current_status", {"state": "tracking", "pose": true,
					"people": people, "camera": true})
				screen.set("live_timer", 2.95)
				screen.call("_process", 3.5)
				_check(int(screen.get("live_step")) == 0
					and int(screen.get("balloon_pose_phase")) == 0,
					"Raw people=%d cannot skip LEFT DOWN even after >3s" % people)
				_check((narrator.get("_played_stages") as Dictionary).size() == heard,
					"Raw people=%d cannot reannounce or move voice stages" % people)
			pose.call("stop_camera")
			pose.set_process(true)
	screen.queue_free()
	await process_frame
	_finish()


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("VOICE1 REAL RECORDINGS QA: ", detail)


func _finish() -> void:
	print("VOICE1 CALIBRATION RECORDINGS: %s checks=%d failures=%d files=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), EXPECTED.size()
	])
	quit(0 if failures.is_empty() else 1)
