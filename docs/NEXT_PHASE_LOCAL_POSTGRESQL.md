# KilosGrammar — Next milestone: local PostgreSQL

**Status:** planned, **not integrated**. This document specifies the next
development phase after GUI review. No database credentials or live data are
stored by the current frontend screens.

## Player identity

`students` has one stable `student_id`, plus editable `student_name` and
`grade_section`. A teacher can enter a new ID to register a student, or an
existing ID to load the registered name and grade/section. The UI must clear
stale name/grade immediately when changing IDs. Update existing identity only
after an explicit teacher action. Do not identify students by names alone.

## Latest completed score

`student_scores` has exactly one **current** score for each
`(student_id, game_style, game_mode, difficulty)` combination. A new **completed**
round REPLACES that score even when it is lower. Different styles, modes,
difficulties, and students always remain separate. Do not overwrite on
cancelled or failed sessions.

Schema outline (future migration, **do not execute against an existing DB
without reviewing tables/backups**):

```sql
CREATE TABLE IF NOT EXISTS students (
    student_id TEXT PRIMARY KEY,
    student_name TEXT NOT NULL,
    grade_section TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS student_scores (
    score_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_id TEXT NOT NULL REFERENCES students(student_id),
    game_style TEXT NOT NULL,
    game_mode TEXT NOT NULL,
    difficulty TEXT NOT NULL,
    score INTEGER NOT NULL CHECK (score >= 0),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (student_id, game_style, game_mode, difficulty)
);
```

Use a transaction at **round completion** and a parameterized `INSERT ... ON
CONFLICT (student_id, game_style, game_mode, difficulty) DO UPDATE` to replace
the current score. Query leaderboards after filtering by grammar style,
Quiz/Activity game mode, and Easy/Normal/Hard difficulty, ordered by score
descending. An optional separate `game_sessions` history table can record
attempts without affecting the latest-score uniqueness rule.

## App boundary

Expose a small typed interface with methods such as:

- `find_student(student_id)`
- `register_student(student_id, student_name, grade_section)`
- `update_student(...)` after explicit confirmation
- `find_score(student_id, game_style, game_mode, difficulty)`
- `complete_round_and_replace_score(...)` transactionally
- `get_leaderboard(game_style, game_mode, difficulty, grade_section)`

The Godot GUI should communicate only with this database service. Avoid
blocking Godot's 60-FPS render loop with synchronous database operations.
Keep PostgreSQL **local only** with parameterized queries and credentials
outside Git and source code; do not add Supabase, Firebase, or cloud sync.

## Acceptance cases

1. Same ID / style / mode / difficulty: score `10` then `20` becomes `20`.
2. Same ID / style / mode, different difficulty: both scores coexist.
3. Same ID / style / difficulty, different Quiz/Activity mode: coexist.
4. Different Student IDs: data must never mix.
5. Aborted replacement: previous completed score remains untouched.
6. Restart the application: registered profiles and completed scores persist.

**After the database milestone:** connect real YOLO26n-Pose webcam tracking,
per-player calibration/verification of LEFT/CENTER/RIGHT, and the movement
tutorial/gameplay input bridge. Until then, camera and calibration panels
must remain explicitly marked as previews.
