# KilosGrammar — safe demo leaderboard + CSV export/delete/import QA

**Status (30 October 2026):** Following an approved `database/start_auto.ps1` launch, the local API at `http://127.0.0.1:18765` returned `database: connected`, `recovery_pending: 0`. A teacher-authorized **read-only complete database export** confirmed **0 pre-existing students and 0 scores**, and read-only lookup confirmed all seven proposed demo IDs were unused. A complete timestamped **pre-import backup** was written and SHA-256 verified before any mutation. Exactly **7 synthetic DEMO profiles and 18 synthetic completed-score records** were then imported once through the **authenticated `POST /data/import` API**, never raw SQL. Live leaderboard read-back and the full post-import CSV export verified **18 ranked scores, seven total demo profiles including one profile-only record, all three games, all topics, both modes and all difficulties**; the original pre-import totals remained untouched. **No live DELETE was executed.** All results describe the database **at verification time only**; recheck before any later destructive action.

## Prepared fixtures

| File | Import format | What it contains |
| --- | --- | --- |
| `kilosgrammar_demo_scores_20261030.csv` | Current **8 columns** | **7 entirely fake DEMO student profiles, 18 completed-score rows** across Catch the Word, Balloon Popping, Human Plane; Noun/Pronoun/Verb/Adjective/Adverb; Easy/Normal/Hard; Seconds/Lives. Six profiles have 3 score rows each, and `DEMO-KG-20261030-P` is intentionally profile-only. |
| `kilosgrammar_demo_legacy_profile_only_20261030.csv` | Historical **7 columns** | One different, entirely fake profile with **no score**; tests old-format import without inventing a minigame. |

The canonical 8-column header is exactly:

```csv
student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score
```

The legacy 7-column header is exactly:

```csv
student_id,student_name,grade_section,game_style,game_mode,difficulty,score
```

The 7-column legacy format cannot identify which of the three current minigames produced a score; scored rows are labeled `Legacy` by the server. **Use the 8-column file for the three-game demo.** Scores are nonnegative multiples of **100**, matching the currently implemented per-correct-answer award in each game. They are **synthetic test data** compatible with the current scoring rules, **not actual human gameplay results**.

Repository copies: `docs/examples/`. Copies were created without overwriting existing files in:

```text
C:\Users\Yue\Downloads\kilosgrammar_demo_scores_20261030.csv
C:\Users\Yue\Downloads\kilosgrammar_demo_legacy_profile_only_20261030.csv
```

## Live seeding, recovery and backup evidence

The earlier service-offline state was resolved by the approved preconfigured launcher; its `/health` endpoint confirmed the configured schema and working connection. The teacher authorization token is the **existing per-Windows-user capability file provided by the game**. Neither this token nor PostgreSQL credentials were printed or saved in the repo. The teacher-authorized `GET /data/export` established **0 students / 0 scores** before import (an empty leaderboard alone would not have established that). All seven `/students/DEMO-KG-20261030-*` lookups returned 404, so no IDs were overwritten.

The durable pre-import backup is held **outside the project**, in `%LOCALAPPDATA%\KilosGrammar\backups\` as:

```text
KilosGrammar_PRE_IMPORT_FULL_BACKUP_20261030_075701_8584318_62b5c29a.csv
```

It contains the original complete database export (canonical header only, **0 student records / 0 score records**) and was verified after a CreateNew write. The live API then confirmed `students_created=7`, `students_existing=0`, `scores_created=18`, `scores_updated=0`. Subsequent live reads verified **18 leaderboard entries** (six per minigame, nine per mode, six per difficulty, five grammar topics, maximum 600 and minimum 0), with the profile-only DEMO ID excluded. A new teacher-authorized full export had exactly **7 profiles, 18 score records, 19 CSV data lines** and an identical set of canonical data fields to the sample. It was saved to Downloads under a fresh CreateNew filename and SHA-256 verified:

```text
C:\Users\Yue\Downloads\KilosGrammar_LIVE_DEMO_FULL_EXPORT_20261030_075839_6056277_07a70daf.csv
```

The **live full export is the complete restore artifact** for the 7/18 demo data. The original sample file is also import-compatible, but it is not a substitute for exporting a database that may have gained other records later.

The API `GET /leaderboard` returns at most 500 scored **entries**, not the number of student profiles, and an empty leaderboard alone cannot prove there are no existing unscored profiles. Only a securely authorized *read-only full export* (which reports both `students` and `scores`) or approved read-only SQL count can establish that. **Never delete based only on a blank leaderboard.**

## Manual UI test on a dedicated demo-only database

1. **Confirm the target** is a separate approved disposable demo database with no real student records. Do not switch an existing classroom database to a demo environment without an administrator-approved setup/backup. Start an *already configured* local API through the normal school-approved launcher and confirm `/health` reports `database: connected`. If unavailable, stop; don't try raw SQL or initialize/upgrade a real database.
2. **Before importing, export the ENTIRE target database** with the Leaderboard's **EXPORT CSV** to Downloads, choosing a new backup filename. Confirm the export success dialog reports the expected student and score counts, verify the CSV exists, is nonempty, and store a second protected backup copy. A backup contains names, IDs, and scores: never publish it in the repo.
3. **Never press DELETE ALL DATA on a database containing real/unknown records**, even if the leaderboard currently shows zero rows. The button deletes *all* profiles and *all* scores, not just `DEMO-` rows. If existing data is found, run only non-destructive import/export verification after teacher authorization, or use a completely separate disposable demo database for the delete step.
4. **The seven demo profiles and eighteen scores are already present in the live app database** as of the verification above. Do not repeat initial import to make them appear. If testing a separate fresh demo-only database later, open **Leaderboard → IMPORT CSV**, choose `C:\Users\Yue\Downloads\kilosgrammar_demo_scores_20261030.csv`, inspect the filename review, and confirm. A fresh target should report 7 new students / 18 scores; reimporting identical records should change none. If any `DEMO-` ID exists with a different identity, stop: do not override it.
5. Open/refresh the **live** Leaderboard with the three visible dropdowns set to **ALL**. Expect **18 ranked completed-score entries** (top score `600`) and **no entry** for `DEMO-KG-20261030-P`, which has no score. Selecting a topic, game mode or difficulty narrows only the visible rows. Imported data is synthetic and does not claim a camera round was played.
6. **EXPORT CSV** to a *new, unique* Downloads file; after success verify the canonical **8-column** header and all **19 data rows** (18 score records + one profile-only record), representing **7 profiles**. Distinguish the canonical backup from the optional *filtered view* CSV: only the canonical database export is intended for complete restoration.
7. **Only if the target is disposable and still free of real/unknown data, the complete freshly exported backup is safely verified, and the teacher consciously approves destructive QA:** use the two-stage **DELETE ALL DATA** confirmation. If the target still contains only this demo, expect 7 students and 18 scores deleted. If counts differ or other students have since registered, **do not delete**. **This step was tested in memory only and has NOT been executed against any PostgreSQL database.**
8. **IMPORT CSV** from the exact exported backup file—not a different filtered or legacy CSV—and verify the original **7 profiles / 18 scores**, ranking and filters return. Re-importing an identical file should be idempotent. Keep the protected backup until the teacher confirms all expected records are restored.

For a mixed database containing other genuine data, import of the 8-column demo may be safe after checking IDs and teacher approval, **but never use Delete All to remove only the demo data**: the current UI does not provide per-student deletion. Use a separate demo-only database for the destructive step.

## Isolated regression evidence (no live records)

```powershell
python -m unittest database.tests.test_demo_csv_roundtrip_20261030 -v
python -m unittest discover -s database/tests -p 'test_*.py' -q
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_postgres_csv_delete_integration.gd
```

The dedicated Python fixture uses the **actual** API import/export/delete handlers, an admin challenge and an in-memory test-only store, *not a live deletion*. It creates one extra **fake pre-existing profile+score**, imports the 7 demo profiles/18 scores (total **8 profiles/19 scores**), verifies sorted/filtered leaderboard results, exports **all data** including the prior record, performs a **mock-only** delete, restores the complete export, checks exact ranked scores, and verifies a repeated import is idempotent. The mock's 8/19 totals are intentional; the user-visible standalone 8-column fixture has 7/18 totals.

### Troubleshooting

- **Local API offline:** check its already-configured local launcher/service; a running PostgreSQL Windows service alone is insufficient.
- **Empty leaderboard after successful import:** reopen the board, reset filters to ALL, confirm backend reports `database: connected`, and check admin import success rather than assuming the records were destroyed.
- **Student profiles exist but scores absent:** profile-only CSV rows and API registrations do not appear in ranked score results; only score rows do.
- **CSV import refused:** verify exact eight-column header, file under the UI's 1 MB limit, each repeated student ID has the identical name/grade, game fields are all present together, and 100-point game scores are numeric.
- **Missing rows after export:** check the teacher selected **EXPORT CSV** (full database), not the separate filtered-score export, and that the server completed successfully. Never trust a truncated/incomplete backup.

**Safety invariant:** never run live `DELETE ALL DATA` to test whether import works. Only a fully disposable teacher-approved demo database may be used for destructive validation, and its backup must be verified first.
