extends Control
## Two-player, one-camera neutral auto-calibration. UI nodes are editor authored.
## Does NOT use the single-player CENTER/LEFT/RIGHT pose guide sequence.
signal requested(target: String, payload: Dictionary)

const TARGET_HOLD := 3.0
const MIN_SAMPLES := 8
const MAX_SOURCE_GAP := 0.7
const MAX_NEUTRAL_SPREAD := 0.095
const DESIGN_SIZE := Vector2(1280, 720)

@onready var stage: Control = $Stage
@onready var video1: TextureRect = $Stage/PlayerOne/LiveCamera
@onready var video2: TextureRect = $Stage/PlayerTwo/LiveCamera
@onready var count1: Label = $Stage/PlayerOne/Countdown
@onready var count2: Label = $Stage/PlayerTwo/Countdown
@onready var status1: Label = $Stage/PlayerOne/Status
@onready var status2: Label = $Stage/PlayerTwo/Status
@onready var back_button: Button = $Stage/BackButton
@onready var distance_note: Label = $Stage/DistanceNote

var context: Dictionary = {}
var player_state: Array[Dictionary] = [{}, {}]
var source_time := -1.0
var complete := false
var complete_elapsed := 0.0
var preview_center_x: Array[float] = [0.25, 0.75]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.pressed.connect(_back)
	PoseService.set_multiplayer_mode(true)
	PoseService.begin_new_multiplayer_calibration()
	PoseService.status_updated.connect(_on_pose)
	PoseService.preview_updated.connect(_on_preview)
	resized.connect(_fit_stage)
	_fit_stage()
	_reset_holds()
	PoseService.start_camera()
	# A single ordinary RGB webcam cannot prove accurate meters without a
	# camera/floor calibration. Never display fabricated live depth figures.
	distance_note.text = "TWO PLAYERS • CAMERA TEST RANGE: 2.5–4.0 m (MEASURE FLOOR DISTANCE)"
	set_process(true)


func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)
	context["player_mode"] = "Multiplayer"
	context["activity"] = "Catch the Word"


func _fit_stage() -> void:
	var ratio: float = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * ratio
	stage.position = (size - DESIGN_SIZE * ratio) * .5


func _reset_holds() -> void:
	player_state = []
	for _i in range(2):
		player_state.append({"ready": false, "timer": 0.0, "count": 0,
			"samples": [], "last_source": -1.0})
	count1.text = "3"
	count2.text = "3"
	status1.text = "STAND COMFORTABLY"
	status2.text = "STAND COMFORTABLY"


func _on_pose(data: Dictionary) -> void:
	if complete or String(data.get("mode", "")) != "multiplayer" \
			or String(data.get("state", "")) != "tracking" \
			or not bool(data.get("camera", false)):
		return
	var timestamp: Variant = data.get("camera_source_timestamp", null)
	var players: Variant = data.get("players", [])
	if not (timestamp is float or timestamp is int) or not is_finite(float(timestamp)) \
			or not (players is Array) or players.size() != 2:
		return
	var source := float(timestamp)
	if source <= source_time:
		return
	source_time = source
	for index in range(2):
		var state: Dictionary = player_state[index]
		if bool(state["ready"]):
			continue
		var player: Variant = players[index]
		var live := player is Dictionary and bool(player.get("active", false))
		var raw_x: Variant = player.get("x", -1) if player is Dictionary else -1
		live = live and (raw_x is float or raw_x is int) \
			and is_finite(float(raw_x)) and float(raw_x) >= 0.04 and float(raw_x) <= 0.96
		var elapsed: float = source - float(state["last_source"])
		if not live or elapsed > MAX_SOURCE_GAP or elapsed <= 0.0:
			state["timer"] = 0.0
			state["count"] = 0
			state["samples"] = []
			state["last_source"] = source
			continue
		var x: float = float(raw_x)
		var samples: Array = state["samples"]
		if not samples.is_empty() and absf(x - float(samples[0])) > MAX_NEUTRAL_SPREAD:
			state["timer"] = 0.0
			state["count"] = 0
			state["samples"] = []
			state["last_source"] = source
			continue
		samples.append(x)
		state["count"] = int(state["count"]) + 1
		state["timer"] = float(state["timer"]) + minf(elapsed, .3)
		state["last_source"] = source
		if float(state["timer"]) < TARGET_HOLD or int(state["count"]) < MIN_SAMPLES:
			continue
		samples.sort()
		var neutral: float = float(samples[samples.size() / 2])
		var deviations: Array[float] = []
		for sample in samples:
			deviations.append(absf(float(sample) - neutral))
		deviations.sort()
		var noise: float = deviations[deviations.size() / 2]
		if PoseService.multiplayer_set_center(index, neutral, noise):
			state["ready"] = true


func _process(delta: float) -> void:
	for index in range(2):
		var state: Dictionary = player_state[index]
		var label: Label = count1 if index == 0 else count2
		var status: Label = status1 if index == 0 else status2
		if bool(state["ready"]):
			label.text = "✓"
			status.text = "READY • CENTER SAVED"
			continue
		label.text = str(clampi(ceili(TARGET_HOLD - float(state["timer"])), 1, 3))
		status.text = "HOLD STILL • AUTO-CENTERING" if PoseService.has_multiplayer_pose(index) \
			else "STEP INTO CAMERA VIEW"
	if not PoseService.has_multiplayer_calibration():
		complete_elapsed = 0.0
		return
	if not PoseService.has_multiplayer_pose(0) or not PoseService.has_multiplayer_pose(1):
		complete_elapsed = 0.0
		return
	complete_elapsed += maxf(delta, 0.0)
	if complete_elapsed < .45 or complete:
		return
	complete = true
	var next_context := context.duplicate(true)
	next_context["player_mode"] = "Multiplayer"
	next_context["activity"] = "Catch the Word"
	next_context["camera_live"] = true
	next_context["calibration_measured"] = true
	next_context["calibration_live"] = true
	next_context["multiplayer_calibration"] = true
	next_context["start_countdown"] = true
	requested.emit("gameplay", next_context)


func _on_preview(texture: Texture2D) -> void:
	if texture == null:
		video1.texture = null
		video2.texture = null
		return
	var picture: Image = texture.get_image()
	if picture == null or picture.is_empty():
		return
	var width := picture.get_width()
	var height := picture.get_height()
	var roi_width := mini(width, roundi(float(width) * .58))
	var roi_height := mini(height, roundi(float(height) * .80))
	for index in range(2):
		var center_x: float = .25 if index == 0 else .75
		if PoseService.has_multiplayer_pose(index):
			center_x = float(PoseService.multiplayer_status[index].get("x", center_x))
		elif bool(player_state[index].get("ready", false)):
			center_x = float(PoseService.multiplayer_calibration[index].get("center", center_x))
		# Smooth the VISUAL crop only. It cannot change a saved gameplay
		# neutral or move the wooden frame, and avoids a jumpy camera preview
		# when YOLO torso X flickers between adjacent pixels.
		preview_center_x[index] = lerpf(preview_center_x[index], center_x, .28)
		var left := clampi(roundi(preview_center_x[index] * width) - roi_width / 2, 0, width - roi_width)
		var top := clampi(roundi(.5 * height) - roi_height / 2, 0, height - roi_height)
		var crop: Image = picture.get_region(Rect2i(left, top, roi_width, roi_height))
		if index == 0:
			if video1.texture is ImageTexture \
					and video1.texture.get_width() == roi_width \
					and video1.texture.get_height() == roi_height:
				(video1.texture as ImageTexture).update(crop)
			else:
				video1.texture = ImageTexture.create_from_image(crop)
		else:
			if video2.texture is ImageTexture \
					and video2.texture.get_width() == roi_width \
					and video2.texture.get_height() == roi_height:
				(video2.texture as ImageTexture).update(crop)
			else:
				video2.texture = ImageTexture.create_from_image(crop)


func _back() -> void:
	PoseService.stop_camera()
	requested.emit("student_setup", context.duplicate(true))


func _exit_tree() -> void:
	if PoseService.status_updated.is_connected(_on_pose):
		PoseService.status_updated.disconnect(_on_pose)
	if PoseService.preview_updated.is_connected(_on_preview):
		PoseService.preview_updated.disconnect(_on_preview)
