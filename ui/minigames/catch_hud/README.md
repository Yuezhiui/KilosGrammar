# Catch the Word · Layered HUD

## Actual reference PNG art

The genuine image-generated bitmap assets are delivered in the conversation as
KilosGrammar_Catch_Actual_Generated_PNGs.zip. The workspace image-saving tool
could not transfer images directly, so extract that ZIP into the kilos-grammar
project root. It provides six independent HUD images under
ui/minigames/catch_hud/generated/: title_board.png, objective_banner.png,
lives_badge.png, timer_badge.png, pause_badge.png, score_board.png.

The generated/character/ folder contains boy_body.png,
boy_basket_hands.png, and word_apple.png as three separate transparent images.
Godot automatically switches from the fallback SVG HUD to the genuine PNG HUD
when all six HUD PNGs have been imported. The new Boy body and basket are used
only when both corresponding PNGs are installed. Girl, Grandma, and Grandpa
retain their separate original body/basket artwork; all three maps remain
separate selectable backgrounds.

The title and SCORE words are baked into the generated images, so gameplay
hides their duplicate GDScript labels when the PNG skin is active. Score
numbers, dynamic grammar questions, lives hearts, and the Seconds timer remain
live UI elements. No gameplay mechanics need changes to use the new artwork.

When the ZIP is not extracted, the previous SVG skin stays playable. Open the
Godot editor after copying PNGs so their textures are imported, then run
res://tools/test_catch_hud_ui.gd headlessly to validate the reference skin.

The gameplay HUD is assembled from individual imported SVG images and editable Godot labels. These images are **not** one flattened screenshot: each plaque can be moved, replaced, or resized independently in the Godot scene ui/minigames/catch_word.tscn.

| Asset | Purpose |
| --- | --- |
| title_board.svg | Wooden title and grammar question frame |
| objective_banner.svg | Cream-colored instruction frame |
| timer_badge.svg | Blue 60-second timer frame |
| lives_badge.svg | Wooden hearts display frame |
| pause_badge.svg | Gold pause control frame |
| score_board.svg | Wooden star-and-score panel |
| topics/noun.svg | Noun lesson icon |
| topics/pronoun.svg | Pronoun lesson icon |
| topics/verb.svg | Verb lesson icon |
| topics/adjective.svg | Adjective lesson icon |
| topics/adverb.svg | Adverb lesson icon |

**Dynamic data stays in Godot**, not in these assets: timer, lives, prompt, objective text, score, and feedback change as the game plays. The same HUD works for all five grammar topics and both teacher-selected game modes.

The character art is independently layered in CatchTheWord/CharacterRig:

1. Body uses WordCatcherCharacters/<character> BODY.png.
2. CollectedWords renders up to three collected apples using Components/Apple.png and separate live word labels.
3. Basket uses WordCatcherCharacters/<character> BASKET.png; the basket and hands draw **in front of** the collected apples.

This lets a character move with the basket while keeping the apples visible at the rim. All four available characters (Boy, Girl, Grandma, Grandpa) use the same layer structure. Backgrounds remain independent textures (City, Forest, Mountain), and falling word apples are individual animated nodes.

To capture actual rendered examples rather than a mockup, run Godot with this command:

    Godot --path . --rendering-method gl_compatibility --script res://tools/capture_catch_hud_variants.gd

Screenshots are written to res://showcase/catch_word_hud/. This command requires a graphical renderer, not --headless.
