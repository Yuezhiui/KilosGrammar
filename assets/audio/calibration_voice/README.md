# KILOS GRAMMAR calibration narration — supplied VOICE1 WAV recordings

**2026-10-29:** Imported all eleven user-supplied recordings from
`C:\Users\Yue\Downloads\VOICE1`. Each WAV was copied without re-encoding and
verified byte-for-byte by SHA-256. The sources remain in Downloads.

| Imported WAV | Recording supplied | Calibration usage |
| --- | --- | --- |
| `center.wav` | `01_Move_to_the_Center.wav` | Catch/Balloon: CENTER movement |
| `stay_center.wav` | `02_Stay_to_the_Center.wav` | Catch/Balloon: CENTER follow-up |
| `left.wav` | `03_Move_To_The_Left.wav` | Catch/Balloon: LEFT movement |
| `stay_left.wav` | `04_Stay_to_the_Left.wav` | Catch/Balloon: LEFT follow-up |
| `right.wav` | `05_Move_To_The_Right.wav` | Catch/Balloon: RIGHT movement |
| `stay_right.wav` | `06_Stay_to_the_Right.wav` | Catch/Balloon: RIGHT follow-up |
| `t_pose.wav` | `02_Stand_in_the_center_Hold_a_T_p.wav` | Human Plane: CENTER T-pose |
| `raise_left_hand.wav` | `03_Raise_Left_Hand.wav` | Supplied optional one-hand cue; **not used for Balloon calibration** |
| `raise_right_hand.wav` | `04_Raise_Right_Hand.wav` | Supplied optional one-hand cue; **not used for Balloon calibration** |
| `raise_both_hands.wav` | `01_Raise_both_Hand.wav` | Balloon: BOTH hands UP phase at LEFT, CENTER and RIGHT |
| `success.wav` | `01_Calibration_Successful.wav` | Once after genuine calibration success |

All eleven WAVs use 24 kHz mono 16-bit uncompressed PCM.

## Playback behavior

Catch the Word announces MOVE and then STAY for CENTER → RIGHT → LEFT.
Balloon Popping follows CENTER → RIGHT → LEFT, with two separate
source-verified 3-second postures at **each** position: BOTH hands DOWN,
then BOTH hands UP. CENTER's DOWN phase plays `hands_down.wav`; at RIGHT and
LEFT, the MOVE recording is followed by `hands_down.wav`. Each UP phase
plays the supplied `raise_both_hands.wav`.
**One raised hand never satisfies Balloon calibration**, but the *separate
actual Balloon Popping gameplay shooting gesture* still accepts one-hand
raising edges and retains its cooldown. Human Plane uses its CENTER T-pose
recording during its own 3-second stationary hold, then presents short LEFT
and RIGHT movement demonstrations with the two new `plane_` cues.
Every activity announces the supplied success cue once, after genuine holds.

The seven older optional cue names (`center`, `right`, `left`, `hands_down`,
`raise_hand`, `t_pose`, `success`) are retained for compatibility in
`ui/vision/calibration/calibration_voice.gd`. The original VOICE1 folder
did **not** contain a generic `hands_down.wav` or `raise_hand.wav`.
`raise_hand.wav` remains absent, since raising both hands already has an
accurate supplied recording.

## Offline voice-clone additions — 2026-10-30

Three additional cues were synthesized *once* with the user's local OmniVoice
model and `C:\Users\Yue\Documents\OMNI VOICE\input\Clone.wav` reference,
using the existing English narration style. The zero-shot clone workflow
and the local cached `k2-fsa/OmniVoice` weights were used; `input.txt`,
`Clone.wav`, and the eleven original VOICE1 recordings were left unchanged.

| New WAV | Spoken instruction | Cue key |
| --- | --- | --- |
| `hands_down.wav` | “Lower both hands.” | `hands_down` |
| `plane_left.wav` | “Tilt your arms to the left.” | `plane_left` |
| `plane_right.wav` | “Tilt your arms to the right.” | `plane_right` |

These are separately mapped as `CLONED_CUE_FILES`; do not treat them as
user-recorded VOICE1 audio. Each file is 24 kHz mono, 16-bit PCM WAV and
loads through the same one-shot Settings-controlled audio player. The
calibration can remain silent when a file is unavailable, and pose freshness,
single-person checks, physical holds, and the GO gate are independent of audio.

The helper uses exactly one `AudioStreamPlayer` on the Settings-controlled
`KilosSFX` bus. A single instruction is heard per real stage/phase, queued
follow-ups stop if the stage changes, and no audio restarts on YOLO pose flicker.
No speech synthesis runs during gameplay or calibration: only the three
pre-generated cloned cues and existing recorded assets are loaded.

The WAVs are instructions only. They cannot count as pose measurements, unlock
holds or authorize GO. The actual 3-second physical holds and current raw
YOLO single-person source verification remain mandatory.
