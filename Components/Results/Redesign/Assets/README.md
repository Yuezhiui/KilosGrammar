# Game-over scoring artwork

These are the original, unmodified transparent PNGs supplied for the three KilosGrammar minigames. The first eight came from `C:\Users\Yue\Downloads\SCORE`; the ROUND artwork was supplied separately afterwards. Use the game-specific banner based on the completed minigame, and overlay live score/student/round values with Godot labels.

| Asset | Dimensions | Supplied source | Role |
| --- | --- | --- | --- |
| `game_over_catch_the_word.png` | 2171 x 724 | `1ab6ca12-a745-4469-aac9-e78472b576c1.png` | Catch the Word banner |
| `game_over_balloon_popping.png` | 2048 x 682 | `99437821-0d5c-4435-9e5f-0399f415516d.png` | Balloon Popping banner |
| `game_over_human_plane.png` | 2048 x 682 | `download.png` | Human Plane banner |
| `panel_final_score.png` | 2164 x 727 | `79212a33-ce05-4920-9d09-7d1dc0b26f04.png` | Cream/yellow score panel; add dynamic text |
| `panel_student_tall.png` | 1729 x 910 | `ad67ee27-0fbe-47cc-9a82-1ecc393bf9a5.png` | Student detail panel with three empty rows |
| `panel_student_wide.png` | 2170 x 725 | `ce828ec1-77dc-453e-a795-deeb911651fd.png` | Alternative student detail panel with three empty rows and larger transparent side margins |
| `panel_round.png` | 1793 x 921 | `C:\Users\Yue\Downloads\download.png` (separate upload) | Exact supplied green ROUND title + gold/cream frame with three blank rows; live labels overlay each row |
| `button_retry.png` | 2131 x 610 | `c055d31f-d205-4c4a-8cc5-39ac237fac50.png` | Purple retry button |
| `button_main_menu.png` | 2131 x 610 | `236b1ca3-1d85-41c9-bffc-64269d37a6d4.png` | Blue main menu button |

Reuse the existing background at `res://Components/Credits/Redesign/background1.png` instead of duplicating it. `ui/secondary/results/results.tscn` uses one editor-authored `GameCard` TextureRect with `panel_round.png` and three editable, data-bound row labels. The earlier custom-drawn RoundCard/RoundRow/RoundHeader StyleBox replacements were retired when the dedicated ROUND artwork arrived.
