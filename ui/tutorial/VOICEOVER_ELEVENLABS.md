# KilosGrammar — ElevenLabs Guided Tutorial Recording Sheet

> **Historical recording reference:** The user removed the Spotlight UI
> on 29 October 2026. The shared scene described below no longer exists.
> The 18 English WAV recordings remain archived in
> `res://assets/audio/tutorial_spotlight/`, but they are **not currently
> played by the Guided Tutorial**. This text documents the old narration
> workflow and should not be treated as current Godot editor instructions.

The interactive Spotlight scene (`res://ui/tutorial/spotlight/spotlight_overlay.tscn`)
works **without** recordings: the visible instructions and controls remain
functional. Record **one sentence group per audio file** so the guide can
replay/skip narration without jumping through a long combined track.

## Voice direction

- Audience: elementary school students (Grades 1–6).
- Voice: warm, welcoming, clear English; a natural Filipino-English accent is
  welcome. Keep it encouraging, not shouted or excessively cartoonish.
- Moderate pace, short pauses between sentences, no baked-in backing music or
  applause. Avoid naming on-screen answers unless that is the fixed practice
  example: real quiz content varies from round to round.
- Recommended file format: `.ogg` (Vorbis) or `.mp3`, one file per line below.
  Copy imports into a dedicated `res://` directory rather than referencing the
  original Downloads directory. Do not embed filenames in unrelated GDScript.
- **Seconds and Lives are different selectable modes in the existing game.**
  Record both variants, but play only the clip matching the active mode.

## Recordings

| Suggested filename | Spoken narration |
| --- | --- |
| `01_welcome.ogg` | “Hello, little learner! Welcome to Kilos Grammar! Let’s learn with our whole body!” |
| `02_game_goal.ogg` | “Look at the question. Your job is to choose the word that answers it correctly.” |
| `03_correct_word.ogg` | “Look at the words on the screen. Read carefully! Find the word that matches the question.” |
| `04_catch_word.ogg` | “Move your basket under the correct word to catch it. Avoid the wrong words!” |
| `05_balloon.ogg` | “Look for the balloon with the correct answer. Aim and pop that balloon!” |
| `06_plane.ogg` | “Guide the airplane into the gate with the correct answer.” |
| `07_player.ogg` | “This is your character. Your body movement helps guide it across the screen.” |
| `08_move_left.ogg` | “Now, try moving to the left.” |
| `09_move_center.ogg` | “Great! Return to the center.” |
| `10_move_right.ogg` | “Excellent! Try moving to the right.” |
| `11_score.ogg` | “This is your score! Correct answers earn points. Let's see how many you can collect!” |
| `12_seconds.ogg` | “This is the timer. In this round, you have sixty seconds to find as many correct answers as you can.” |
| `13_lives.ogg` | “These are your three lives. Be careful! When you lose all your lives, the round ends.” |
| `14_pause.ogg` | “Need a break? Use the pause button to stop the game, then resume when you're ready.” |
| `15_practice.ogg` | “Let's try one together. Follow the arrow to the correct answer!” |
| `16_success.ogg` | “Fantastic job! You've learned the controls!” |
| `17_ready.ogg` | “Remember: read the question, move to the correct answer, and have fun learning!” |
| `18_go.ogg` | “Three, two, one, go!” |

The example in the screenshot uses **PATIENTLY** as an adverb. For a fixed
demonstration answer only, you can separately record:

> “Patiently is an adverb because it tells us how someone does something.”

Do not use that line for randomized questions that have a different target.

## Exact Spotlight audio keys (copy these names for production clips)

The Spotlight driver uses five instructional steps per activity. The mode
step chooses **either** `_seconds` **or** `_lives`; the game does not narrate
both at once. To auto-match the step audio, create these specifically named
clips (instead of using the generic rehearsal names above):

| Audio step key / suggested OGG filename | Narration content |
| --- | --- |
| `catch_word_prompt` | Read the question and catch only a correct falling word. |
| `catch_word_movement` | This is your basket and character. Move left, center and right to catch the correct word. |
| `catch_word_seconds` | In Seconds mode, answer as many questions as you can before sixty seconds run out. |
| `catch_word_lives` | In Lives mode, protect your three lives; mistakes can end the round. |
| `catch_word_score` | The score increases when you catch correct answers. |
| `catch_word_pause` | Press Pause whenever you need to stop the action. |
| `balloon_popping_prompt` | Read the question, identify the correct balloon, and pop it. |
| `balloon_popping_movement` | Move to aim the launcher and raise your hands to fire. |
| `balloon_popping_seconds` | In Seconds mode, keep answering before sixty seconds run out. |
| `balloon_popping_lives` | In Lives mode, avoid wrong answers and protect your three lives. |
| `balloon_popping_score` | Pop the right balloon to increase your score. |
| `balloon_popping_pause` | Pause the game whenever you need a break. |
| `human_plane_prompt` | Read the question and fly through the gate with the correct answer. |
| `human_plane_movement` | Move your body left, center, or right to guide your airplane. |
| `human_plane_seconds` | In Seconds mode, answer before the sixty-second timer finishes. |
| `human_plane_lives` | In Lives mode, be careful: you have three lives. |
| `human_plane_score` | Choose the right gate to increase your score. |
| `human_plane_pause` | Press Pause if you need a break. |

Use `<audio step key>.ogg` for the exact filename (for example,
`catch_word_score.ogg`). These are short direction notes you can polish in
ElevenLabs; avoid including the word “mode” in your recorded audio if the mode
is clear in the on-screen caption.

## Asset and interface checklist

1. Export each clip individually from ElevenLabs and import into Godot.
2. Select the Spotlight scene in the **2D** editor to change image textures,
   arrow direction, position, captions, and panel design visually.
3. Attach voice streams using the Spotlight voice slots / audio mapping documented
   in that scene. An absent clip must never block the Next or Skip actions.
4. Verify Replay Voice only restarts the *current* caption's clip and does not
   overlap narration from earlier steps. Test mute and volume settings.
5. Always keep the caption legible: some pupils will play with audio muted.

**Recording note:** `03_correct_word` deliberately avoids saying an exact
answer: answers and topics vary by game and difficulty. A dynamic TTS pipeline
would be a separate feature and is not required for offline classrooms.
