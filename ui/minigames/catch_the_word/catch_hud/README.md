# Catch the Word — Current PNG HUD and audio

The live scene is `res://ui/minigames/catch_the_word/catch_word.tscn`, with layout and round
logic in `catch_word.gd`. The PNG assets are **already installed and imported**;
the UI is made from independently positioned images, not a screenshot.

Current active HUD art in `res://Components/Gameplay/Catch the Word/HUD/generated/`:

| Resource | Current use |
| --- | --- |
| `title_board.png` | Wooden title with baked `CATCH THE WORD`; a single live grammar question sits in its strip |
| `timer_badge.png` | Blue timer in Seconds mode |
| `pause_badge.png` | Gold pause button |
| `score_board.png` | Wooden `SCORE` heading baked into art, with one live score number |
| `replacement/lives_state_3.png` | Complete three-heart panel in Lives mode |
| `replacement/lives_state_2.png` | Complete two-heart panel in Lives mode |
| `replacement/lives_state_1.png` | Complete one-heart panel in Lives mode |
| `character/word_apple.png` | Glossy falling word apples only |

**The old cream objective banner is not in the current gameplay HUD.**
`objective_banner.png`, older SVG variants, and generated replacement character
art may still exist as unused historical resources. Do not reactivate them
without an explicit new design decision. Correct/wrong catch feedback plays
the user's existing MP3s from `res://assets/audio/catch_voice/` through one
reused `CatchVoicePlayer`. Completed low-scoring Catch rounds play the existing
`Better Luck.mp3` in the Results panel (or the standalone preview dialog),
not in the gameplay scene that is immediately freed on navigation.

The approved character art remains `Components/Gameplay/Catch the Word/Characters/<CHARACTER> BODY.png`
and `Components/Gameplay/Catch the Word/Characters/<CHARACTER> BASKET.png` for Boy, Girl, Grandma, and
Grandpa. Each collected basket apple uses `res://Components/Gameplay/Catch the Word/Items/Apple.png`; only
three labeled caught apples are kept visible. City, Forest, and Mountain maps
remain separate selectable assets under `Components/Gameplay/Catch the Word/Maps/`.

To validate the current state, use Godot 4.7.2 scripts such as
`res://tools/test_catch_clean_hud.gd`, `test_catch_png_assets.gd`,
`test_catch_round_end_audio.gd`, and `test_catch_spawn_hud_safety.gd`.
For genuine rendered captures, run the graphical (not `--headless`)
`res://tools/capture_catch_clean_hud.gd` script. For a standalone fullscreen
preview use `tools/run_catch_fullscreen.ps1`.
