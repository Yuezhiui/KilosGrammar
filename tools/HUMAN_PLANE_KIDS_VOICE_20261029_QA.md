# Human Plane recorded children's voice audit — 2026-10-29

The reported symptom: a correct noun gate in Human Plane makes no audible
children's praise, unlike Catch the Word.

## Exact playback chain

- Human Plane (ui/minigames/human_plane/human_plane.gd) creates KidsVoice in
  _ready/_initialize_voice_feedback. Its _advance_gate_step crosses the
  answer line and calls _resolve_at_answer_line; selected_was_correct calls
  _play_voice_feedback(true) -> KidsVoice.play_correct(). Wrong and missed
  events similarly call play_wrong() and play_missed().
- Catch the Word uses the very same KidsVoice helper and voice banks; there is
  no separate voice recording subsystem to copy into Human Plane.
- Shared helper (ui/shared/kids_voice_feedback.gd) owns one AudioStreamPlayer
  at volume 0 dB on KilosSFX, reusing it for all events. It starts recording
  playback for display-backed Godot sessions; headless mode binds the stream
  but deliberately does not call play(). New scores stop/replace old voices.
- GameAudio (ui/shared/game_audio.gd) creates KilosMusic and KilosSFX buses,
  both routed to Master, and ducks gameplay music by 11 dB while a voice is
  heard. Settings persist Master and Effects gain in user://kilos_settings.cfg
  and must retain user control over mute/volume.

## Audio assets

The 39 existing children WAV files under assets/audio/kids_voice are genuine
24 kHz, mono, 16-bit PCM recordings. Independently decoded and measured with
Python wave/audioop on Windows: all 39 are non-silent; RMS amplitudes range
from 1252 to 3738 (16-bit PCM units). Even the lowest-amplitude correct
recording 06_Thats_correct.wav has RMS 1252 and peak amplitude 9591.

## QA and reproduction

tools/test_human_plane_kids_voice_20261029.gd mounts the actual Human Plane
PackedScene, obtains authentic GrammarBank Noun words and valid indices,
positions the plane relative to real editor-authored ring and airplane
hitboxes, then calls _update_gate_wave(1.0 / 60.0) until crossing automatically
invokes scoring. The test never invokes the voice helper or AudioStreamPlayer
play manually.

It checks three distinct scoring situations: correct gate -> +100 and recorded
praise WAV; incorrect gate -> 0 points and encouragement WAV; no gate touched
-> missed coaching WAV. It also verifies exactly one attempt/sound resource
per crossing; no replay on subsequent ticks; one child player, KilosSFX ->
Master routing, unmuted test bus, valid WAV duration, native actual playing
flag, and stop/release at pause/teardown. It also starts the actual GameAudio
soundtrack manager at GO, verifies the soundtrack WAV is loaded and the
background music is ducked by 11 dB whenever praise or coaching plays.
An audio mixer callback gets at least 180 milliseconds to produce samples;
the test requires actual peak amplitude stronger than -75 dB on KilosSFX,
not merely a .playing flag. The regular Play Gameplay wrapper is audited
read-only: it mounts the same Human Plane PackedScene and starts music at GO.
A full GUI run with saved Settings remains necessary to check speakers.

Run in Windows PowerShell from /kilos-grammar:

    & 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_kids_voice_20261029.gd
    & 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-driver opengl3 --script res://tools/test_human_plane_kids_voice_20261029.gd

## Actual results and limits

FINAL on the current parseable flight scene:
**PASS 74/74 headless**, **PASS 86/86 native Windows OpenGL 3.3/NVIDIA
RTX 3050** (two independent native runs, both 86/86), exit code 0 with no
SCRIPT ERROR. In both native runs the real answer-line scoring event started
HumanPlaneVoicePlayer.playing=true for correct, wrong and missed cases.
Examples: a real correct-praise 10_Super_job.wav clip (1.52 seconds) peaked
at -23.57 dB on KilosSFX and 11_You_nailed_it.wav (1.68 seconds) peaked
at -46.90 dB; these are genuine non-silent audio buffers read from Godot's
live mixer, not synthetic or manually triggered stream playbacks. Wrong and
missed sample peaks also exceeded the -75 dB threshold.
KilosSFX was unmuted, 0 dB and routed to unmuted Master, output device
reported Default. With GameAudio active, gameplay music volume was verified
at -11 dB during voice feedback, and voice output stayed active.

Audio caveat: the standalone test's persistent GameAudio manager reported
is_gameplay_active=true with its soundtrack WAV loaded, but the soundtrack
AudioStreamPlayer.playing flag was false at the instant of these quick
script-driven rounds. This is not evidence that the full routed game music
is audible; verify through normal GUI Play when checking real speakers.
The tests confirm mixer samples from children voices, not measured acoustic
output of a physical classroom speaker.

During simultaneous flight-wave edits, Human Plane temporarily failed
to parse (unexpected indent at human_plane.gd lines 551 and 592). The
edits are owned by worker19 and were communicated to prime. A separate
attempt to preload the full Gameplay wrapper in a standalone SceneTree
--script harness could not compile its project autoload PoseService global,
so that optional wrapper check was removed. No false wrapper pass is claimed.
Those loading issues are not evidence of a voice-path defect. The final
focused test was rerun successfully after the flight-wave source parsed again.

No change was needed in the shared KidsVoice helper, since the actual real
scoring case already successfully bound, started and mixed recorded WAVs.
Changing that shared component without a reproduced failure risks breaking
Catch and Balloon. If the live classroom symptom persists despite these
passes, capture the live GUI scene's selected_was_correct, score,
HumanPlaneVoicePlayer.stream path, playing flag, KilosSFX/Master gain,
audio output device and mixer peak at the same answer-line moment. Check
Settings Effects and Master sliders and speaker device in the actual session,
then fix the specific difference from the passing isolated test.
