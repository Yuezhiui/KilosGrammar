# Preserved English tutorial WAV assets — independent QA (2026-10-29)

## Outcome after Spotlight removal request

The user requested removal of the Spotlight UI/scene and its embedded minigame nodes. The **18 generated English WAV files were not requested deleted and are preserved** at `res://assets/audio/tutorial_spotlight/`. These recordings are now retained assets. **This report does not claim that any of them play in Guided Tutorial**, because the Spotlight player and guide steps are being removed.

The asset-only test `tools/test_tutorial_voice_assets_20261029.gd` does not load or reference any minigame, gameplay wrapper, audio manager, or removed Spotlight resource. It is independent of the scene-removal timing.

**Godot 4.7.2 headless PASS: 327 checks, zero failures (18/18 expected recordings).** Checks include:

- Exactly 18 WAVs present with the original six filename suffixes (`prompt`, `movement`, `seconds`, `lives`, `score`, `pause`) for each of Catch the Word, Balloon Popping, and Human Plane, with no unexpected extra WAV.
- Every file is readable RIFF/WAVE with **uncompressed PCM16, mono, 24,000 Hz**, correct frame alignment and byte rate, and imported as a non-looping `AudioStreamWAV` in Godot.
- Full waveform inspection (every PCM sample) confirms real non-silent signal, distinct recordings, zero clipped samples, and RMS in the intended range.
- Durations range from **5.91 to 9.61 seconds**. Every clip is byte-distinct from its previous retired bilingual version by individually recorded SHA-256.

## Offline English language review

The 18 preserved WAVs were independently re-transcribed on October 29, 2026 using **Whisper base.pt cached locally** with CUDA and FFmpeg (no downloads). The ASR model identified **English (`en`) for all 18/18** and produced coherent English text for each recording, without detecting Filipino phrases.

| English recording | ASR | Indicative transcribed content |
| --- | --- | --- |
| catch_word_prompt | en | Look at the question at the top of the screen. Read it carefully. Then find the matching word on a falling apple. |
| catch_word_movement | en | Move your body left, center, or right to guide your basket. Catch the apple with the correct word. You've got this! |
| catch_word_seconds | en | In second mode you have 60 seconds. Catch as many correct words as you can before the timer reaches zero. |
| catch_word_lives | en | In live mode you start with three hearts. Catching a wrong apple costs one heart, so look carefully before you move. |
| catch_word_score | en | Every correct apple earns 100 points! A wrong answer never takes away points you have already earned. Keep trying! |
| catch_word_pause | en | Need a little break? Press pause to stop for a moment. Press resume when you're ready to play again. |
| balloon_popping_prompt | en | Read the grammar question on the screen. Look at each balloon, then choose the one with the word that answers the question. |
| balloon_popping_movement | en | Move your body to aim. Raise either hand to shoot once. Lower your hand, wait one and a half seconds, then raise it again. |
| balloon_popping_seconds | en | In seconds mode, you have 60 seconds. Pop as many balloons with correct answers as you can before time runs out. |
| balloon_popping_lives | en | In Lives Mode, you have three hearts. Popping a wrong balloon can cost one heart. Take your time and choose carefully! |
| balloon_popping_score | en | Each correct balloon adds 100 points! A wrong balloon never takes away the points you've already earned. Great work! |
| balloon_popping_pause | en | Want a quick rest? Press pause to take a break. Press resume when you're ready to pop more balloons. |
| human_plane_prompt | en | Read the question before your flight. Three word gates are coming towards you. Choose the correct word and fly through the center of its ring. |
| human_plane_movement | en | Spread both arms wide like airplane wings. Step left, center, or right to steer. Lower either arm to freeze your plane. Spread both arms again to keep flying! |
| human_plane_seconds | en | In seconds mode you have 60 seconds. Fly through as many correct rings as you can before the timer reaches zero. |
| human_plane_lives | en | In Lives Mode you start with three hearts. A wrong ring or a missed answer can cost one heart. Choose your gate carefully! |
| human_plane_score | en | Fly through the correct ring to earn 100 points. A wrong answer never removes your earned points. Keep your eyes on the next gate! |
| human_plane_pause | en | Need to rest your arms? Press pause for a quick break. Press resume when you're ready to fly again. |

**ASR limitation:** Whisper transcribed `catch_word_seconds` as “second mode” and `catch_word_lives` as “live mode”; this may be a final-consonant recognition error. Manual listening is still needed to certify each word, natural delivery, and complete absence of isolated Filipino words. The PCM Godot test proves audio preservation/format, not language correctness or in-game use.

## Re-run

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_tutorial_voice_assets_20261029.gd
```

QA work changed only `tools/test_tutorial_voice_assets_20261029.gd` and this report. No WAVs, manifests, production scenes/scripts, or Git state were changed.
