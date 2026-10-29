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
Balloon Popping instead follows LEFT → CENTER → RIGHT, with two separate
source-verified 3-second postures at **each** position: BOTH hands DOWN,
then BOTH hands UP. The DOWN phase plays the appropriate MOVE and then STAY
recordings; the UP phase plays the supplied `raise_both_hands.wav`.
**One raised hand never satisfies Balloon calibration**, but the *separate
actual Balloon Popping gameplay shooting gesture* still accepts one-hand
raising edges and retains its cooldown. Human Plane uses its CENTER T-pose
recording during its own 3-second stationary hold.
Every activity announces the supplied success cue once, after genuine holds.

The seven older optional cue names (`center`, `right`, `left`, `hands_down`,
`raise_hand`, `t_pose`, `success`) are retained for compatibility in
`ui/vision/calibration_voice.gd`. The user **did not provide** generic
`hands_down.wav` or `raise_hand.wav` recordings; neither missing cue is used
by the current calibration instructions. Do not mislabel a hand-raising file
as hands-down speech.

The helper uses exactly one `AudioStreamPlayer` on the Settings-controlled
`KilosSFX` bus. A single instruction is heard per real stage/phase, queued
follow-ups stop if the stage changes, and no audio restarts on YOLO pose flicker.
No TTS, synthetic speech, or gameplay feedback file is substituted.

The WAVs are instructions only. They cannot count as pose measurements, unlock
holds or authorize GO. The actual 3-second physical holds and current raw
YOLO single-person source verification remain mandatory.
