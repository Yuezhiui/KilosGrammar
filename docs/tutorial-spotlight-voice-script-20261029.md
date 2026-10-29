# KILOS GRAMMAR — Final English Guided Tutorial Voice Script

**Status:** Final recording copy, 29 October 2026. **Language:** English only, with friendly, clear delivery for Grades 1–6.

The GuidedSpotlight appears after camera calibration and before gameplay. Each minigame has five steps in this order: **Question → Movement → active Game Mode → Score → Pause**. The mode step uses **either Seconds or Lives**, never both. Each game therefore needs **six WAV recordings (18 total)**, but plays only five in one tutorial session.

The WAV filename stem exactly matches the `step_id` expected by `ui/tutorial/spotlight/spotlight_overlay.gd`. The source-of-truth machine-readable copy is `tools/tutorial_voice/voice_lines.json`. Keep these recordings and their captions consistent.

## Catch the Word

1. **`catch_word_prompt.wav`** (`prompt`): “Look at the question at the top of the screen. Read it carefully, then find the matching word on a falling apple.”
2. **`catch_word_movement.wav`** (`movement`): “Move your body left, center, or right to guide your basket. Catch the apple with the correct word. You've got this!”
3. **`catch_word_seconds.wav`** (`seconds`): “In Seconds mode, you have sixty seconds. Catch as many correct words as you can before the timer reaches zero!”
4. **`catch_word_lives.wav`** (`lives`): “In Lives mode, you start with three hearts. Catching a wrong apple costs one heart, so look carefully before you move.”
5. **`catch_word_score.wav`** (`score`): “Every correct apple earns one hundred points! A wrong answer never takes away points you have already earned. Keep trying!”
6. **`catch_word_pause.wav`** (`pause`): “Need a little break? Press Pause to stop for a moment. Press Resume when you're ready to play again!”

## Balloon Popping

1. **`balloon_popping_prompt.wav`** (`prompt`): “Read the grammar question on the screen. Look at each balloon, then choose the one with the word that answers the question.”
2. **`balloon_popping_movement.wav`** (`movement`): “Move your body to aim. Raise either hand to shoot once. Lower your hand, wait one and a half seconds, then raise it again!”
3. **`balloon_popping_seconds.wav`** (`seconds`): “In Seconds mode, you have sixty seconds. Pop as many balloons with correct answers as you can before time runs out!”
4. **`balloon_popping_lives.wav`** (`lives`): “In Lives mode, you have three hearts. Popping a wrong balloon can cost one heart. Take your time and choose carefully!”
5. **`balloon_popping_score.wav`** (`score`): “Each correct balloon adds one hundred points! A wrong balloon never takes away the points you've already earned. Great work!”
6. **`balloon_popping_pause.wav`** (`pause`): “Want a quick rest? Press Pause to take a break. Press Resume when you're ready to pop more balloons!”

## Human Plane

1. **`human_plane_prompt.wav`** (`prompt`): “Read the question before your flight. Three word gates are coming toward you. Choose the correct word and fly through the center of its ring!”
2. **`human_plane_movement.wav`** (`movement`): “Spread both arms wide like airplane wings. Step left, center, or right to steer. Lower either arm to freeze your plane. Spread both arms again to keep flying!”
3. **`human_plane_seconds.wav`** (`seconds`): “In Seconds mode, you have sixty seconds. Fly through as many correct rings as you can before the timer reaches zero!”
4. **`human_plane_lives.wav`** (`lives`): “In Lives mode, you start with three hearts. A wrong ring or a missed answer can cost one heart. Choose your gate carefully!”
5. **`human_plane_score.wav`** (`score`): “Fly through the correct ring to earn one hundred points! A wrong answer never removes your earned points. Keep your eyes on the next gate!”
6. **`human_plane_pause.wav`** (`pause`): “Need to rest your arms? Press Pause for a quick break. Press Resume when you're ready to fly again!”

## Recording and integration notes

- **Delivery:** Speak in a warm, cheerful children's voice, with natural English pronunciation and easy pacing. Leave a little room between sentences for clear listening. Aim for roughly **6–15 seconds per clip**. Keep the longer movement directions unhurried.
- **Numbers:** Say **“sixty seconds”** for the **60-second** round, **“three hearts”** for **3 lives**, **“one hundred points”** for **+100** per correct answer, and **“one and a half seconds”** for the **1.5-second** Balloon Popping cooldown.
- **Catch movement:** Body movement to left, center, or right guides the basket under the correct falling word.
- **Balloon movement:** Raise either hand for one shot, lower it to rearm, and allow a 1.5-second delay before the next shot.
- **Plane movement:** Spread **both arms** wide and move your body left, center, or right. Lowering **either** arm freezes horizontal movement. Spreading both arms again resumes movement without recalibration.
- **Scoring:** Every correct answer adds 100 points. Wrong answers do not deduct points already earned, although incorrect attempts can cost a heart in Lives mode.
- **Export:** Create one actual WAV per JSON entry under `res://assets/audio/tutorial_spotlight/`, preserving the exact filenames. Use the user-authorized local children's voice sample from `C:\Users\Yue\Documents\OMNI VOICE` for synthesis. Keep the original voice sample outside the Godot project.
- **Playback:** Play a clip once when its spotlight step appears. **Replay Voice** repeats only the current step. Avoid overlapping narration during Next, Back, Skip, and regular gameplay. Captions stay available when a WAV is missing.
