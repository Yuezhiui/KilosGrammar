extends SceneTree

## Independent inventory and audio-format QA for 18 preserved English WAVs.
## This deliberately tests the files themselves. Tutorial Spotlight was
## retired and these files are intentionally kept for possible later reuse.
## Godot 4.7.2 (after import):
##   --headless --path . --script res://tools/test_tutorial_voice_assets_20261029.gd

const AUDIO_ROOT := "res://assets/audio/tutorial_spotlight/"
const GAMES := ["catch_word", "balloon_popping", "human_plane"]
const STEPS := ["prompt", "movement", "seconds", "lives", "score", "pause"]
# Hashes from the removed bilingual batch, recorded prior to the full-English
# regeneration. Any surviving old recording is a genuine regression.
const RETIRED_BILINGUAL_SHA256 := {
	"balloon_popping_lives": "DEAD0D08E81B5E8CB9223FE0CA72929EAFA0AA4382DF5A01670E3274C9B2F7C4",
	"balloon_popping_movement": "7F48D95A80D15AC43BAF2022DFB246FA0DFDCF308A481363B946DB9666E179D2",
	"balloon_popping_pause": "0DDADC3CDECF9C3A6A0988D4862AD3E3A9D43E3BD8F21456CE86B9C3FB18E203",
	"balloon_popping_prompt": "C0BD9D331F92E3CE94A10FC39BF35F1F741E439CCC2E3BEEA0E1F5E74C291724",
	"balloon_popping_score": "5D9D6D1F7FB4F0924E51DC11079B8786244FB9C909F15E8A4B44F8DD1FBBAD5D",
	"balloon_popping_seconds": "7261F929F61AA906F29735D287186C4BA99D113AE6E96B2F4FB79954C732F13C",
	"catch_word_lives": "536E97CD46E41E4829814949C0407865C443AAE452ED0603A4270026E15EE020",
	"catch_word_movement": "F32F54147F10274963127E30169C31ABBCC4B3FFC83E4DCA186C9D6AA9503F2C",
	"catch_word_pause": "6D17647D674F3C29174676330D2B82B6D8877E225707B809BDF17B0030890541",
	"catch_word_prompt": "27BC4317EAF91CE9B5DDEF70125B0B5DC2278B6FCE42FA9DFA55971AC6B7CA6A",
	"catch_word_score": "23C9F11EB34FD14E7F2CD7B10D0F5AE6B5D2CBC19108283012EA2F37C85CEA59",
	"catch_word_seconds": "7D6C195437098790FE8FF86A4770D3DB11C3E1963AE82CF989E9C135D5B34F6B",
	"human_plane_lives": "922D1DE0B57BEE30340B3D4A2127FBCA6C3980256E409630D02A4703F45D9FEE",
	"human_plane_movement": "DE8693B04E0927B5A9ECC224B3E8A5F4DB0DDC5AB217AE6228FE6D30652A62C0",
	"human_plane_pause": "B553E40F4D969742A2E8D85405D004704A5C98AD41562B87078D6207B716EAD1",
	"human_plane_prompt": "4F464744196FE80FDE017FBE090C16D5287981087882407188B1F6BD986CC9F",
	"human_plane_score": "1A16AF2A2DD784BE01BFBC04896E25D6EB83686603042FD0DE1919C88B8EB685",
	"human_plane_seconds": "995E62EA2949F8E2F7C17EB3315C7A2CD5DC96D6A9494EFCDE8155F64A83EFFC",
}

var checks := 0
var failures: Array[String] = []
var hashes: Dictionary = {}
var found_clips := 0
var min_duration := INF
var max_duration := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DirAccess.dir_exists_absolute(AUDIO_ROOT),
		"preserved English audio folder is still available")
	if not DirAccess.dir_exists_absolute(AUDIO_ROOT):
		_finish()
		return
	var found := PackedStringArray()
	for filename in DirAccess.get_files_at(AUDIO_ROOT):
		if String(filename).to_lower().ends_with(".wav"):
			found.append(String(filename))
	_check(found.size() == 18, "exactly 18 preserved WAVs (found %d)" % found.size())
	for game in GAMES:
		for step in STEPS:
			var id: String = game + "_" + step
			var filename: String = id + ".wav"
			_check(found.has(filename), "required English WAV filename exists: " + filename)
			var path: String = AUDIO_ROOT + filename
			if not FileAccess.file_exists(path):
				continue
			_check_file(id, path)
	_check(found_clips == 18, "all 18 WAVs were readable and inspected")
	if found_clips > 0:
		print("ENGLISH WAV inventory: found=", found_clips,
			" duration_range=", snappedf(min_duration, 0.01), "-",
			snappedf(max_duration, 0.01), " s")
	_finish()


func _check_file(id: String, path: String) -> void:
	var info := _inspect_pcm_wav(path)
	if not _check(not info.is_empty(), id + ": valid complete RIFF/WAVE with fmt and data"):
		return
	found_clips += 1
	_check(int(info["format_tag"]) == 1, id + ": linear uncompressed PCM format")
	_check(int(info["channels"]) == 1, id + ": mono (one channel)")
	_check(int(info["sample_rate"]) == 24000, id + ": exact 24,000 Hz rate")
	_check(int(info["bits_per_sample"]) == 16, id + ": exact 16-bit PCM")
	_check(int(info["block_align"]) == 2 and int(info["byte_rate"]) == 48000,
		id + ": PCM frame alignment/byte rate are consistent")
	_check(int(info["data_bytes"]) > 20000 and int(info["data_bytes"]) % 2 == 0,
		id + ": substantial, whole-sample audio data")
	var duration := float(info["duration"])
	min_duration = minf(min_duration, duration)
	max_duration = maxf(max_duration, duration)
	_check(duration >= 1.0 and duration <= 30.0,
		id + ": natural narration duration 1-30 seconds (actual %.2f)" % duration)
	_check(int(info["active_samples"]) > 1000 and int(info["distinct_samples"]) > 25,
		id + ": actual varied non-silent signal, not filler")
	var rms := float(info["rms"])
	_check(rms >= 0.003 and rms <= 0.65,
		id + ": audible undistorted RMS volume (%.1f dBFS)" %
			linear_to_db(maxf(rms, 0.000001)))
	_check(int(info["clipped_samples"]) == 0,
		id + ": zero clipped integer samples")
	var digest := FileAccess.get_sha256(path).to_upper()
	_check(not hashes.has(digest), id + ": unique recording, no copied WAV content")
	hashes[digest] = id
	_check(digest != String(RETIRED_BILINGUAL_SHA256.get(id, "")),
		id + ": differs from obsolete bilingual recording")
	_check(ResourceLoader.exists(path), id + ": can be loaded as an offline Godot resource")
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStreamWAV
		_check(stream != null, id + ": Godot imports as AudioStreamWAV")
		if stream != null:
			_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
				id + ": imported narration does not loop")
			_check(absf(stream.get_length() - duration) <= 0.3,
				id + ": imported duration matches source WAV")
	print("PRESERVED ENGLISH WAV ", id,
		" duration=", snappedf(duration, 0.01), "s",
		" channels=", info["channels"],
		" sample_rate=", info["sample_rate"],
		" bits=", info["bits_per_sample"],
		" rms_dbfs=", snappedf(linear_to_db(maxf(rms, 0.000001)), 0.1),
		" peak=", info["peak"],
		" clipped=", info["clipped_samples"])


func _inspect_pcm_wav(path: String) -> Dictionary:
	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null or reader.get_length() < 44:
		return {}
	reader.big_endian = false
	if reader.get_buffer(4).get_string_from_ascii() != "RIFF":
		return {}
	var riff_data_length := int(reader.get_32())
	if reader.get_buffer(4).get_string_from_ascii() != "WAVE":
		return {}
	if riff_data_length < 36 or riff_data_length + 8 > reader.get_length():
		return {}
	var fmt := {}
	var data_start := -1
	var data_bytes := 0
	while reader.get_position() + 8 <= riff_data_length + 8:
		var chunk := reader.get_buffer(4).get_string_from_ascii()
		var chunk_length := int(reader.get_32())
		var start := reader.get_position()
		if chunk_length < 0 or start + chunk_length > riff_data_length + 8:
			return {}
		if chunk == "fmt " and chunk_length >= 16:
			fmt = {
				"format_tag": reader.get_16(),
				"channels": reader.get_16(),
				"sample_rate": reader.get_32(),
				"byte_rate": reader.get_32(),
				"block_align": reader.get_16(),
				"bits_per_sample": reader.get_16(),
			}
		elif chunk == "data":
			data_start = start
			data_bytes = chunk_length
		reader.seek(start + chunk_length + (chunk_length % 2))
	if fmt.is_empty() or data_start < 0:
		return {}
	var align := int(fmt["block_align"])
	var rate := int(fmt["sample_rate"])
	if align <= 0 or rate <= 0:
		return {}
	fmt["data_bytes"] = data_bytes
	fmt["duration"] = float(data_bytes) / float(rate * align)
	fmt["active_samples"] = 0
	fmt["distinct_samples"] = 0
	fmt["rms"] = 0.0
	fmt["clipped_samples"] = 0
	fmt["peak"] = 0
	if int(fmt["format_tag"]) != 1 or int(fmt["bits_per_sample"]) != 16:
		return fmt
	reader.seek(data_start)
	var pcm := reader.get_buffer(data_bytes)
	var count := int(pcm.size() / 2)
	if count <= 0:
		return fmt
	var sum_sq := 0.0
	var unique := {}
	var active := 0
	var clipped := 0
	var peak := 0
	var stride := maxi(1, int(count / 1500))
	for i in range(count):
		var index := i * 2
		var sample := int(pcm[index]) | (int(pcm[index + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var abs_sample := absi(sample)
		peak = maxi(peak, abs_sample)
		sum_sq += float(sample) * float(sample)
		if abs_sample >= 32760:
			clipped += 1
		if abs_sample >= 64:
			active += 1
		if i % stride == 0:
			unique[sample] = true
	fmt["active_samples"] = active
	fmt["distinct_samples"] = unique.size()
	fmt["rms"] = sqrt(sum_sq / float(count)) / 32768.0
	fmt["clipped_samples"] = clipped
	fmt["peak"] = peak
	return fmt


func _check(ok: bool, name: String) -> bool:
	checks += 1
	if not ok:
		failures.append(name)
		printerr("TUTORIAL ENGLISH WAV QA FAIL: ", name)
	return ok


func _finish() -> void:
	print("TUTORIAL ENGLISH WAV ASSETS: %s (%d checks, %d failures; %d/%d expected files)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
			found_clips, GAMES.size() * STEPS.size()])
	quit(0 if failures.is_empty() else 1)
