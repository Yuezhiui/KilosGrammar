-- FORWARD-ONLY MANUAL MIGRATION. Back up the existing PostgreSQL database and
-- review this entire file before executing --apply-minigame. DO NOT run it as
-- part of normal game startup. Existing score values/IDs/timestamps survive.
-- Activity for historical rows is UNKNOWN; label them 'Legacy', never infer
-- Catch / Balloon Popping / Human Plane from the grammar-topic column.
-- Run the complete script in ONE PostgreSQL transaction (database.migrate).

DO $preconditions$
BEGIN
    IF to_regclass('students') IS NULL OR to_regclass('student_scores') IS NULL THEN
        RAISE EXCEPTION 'Initial 001 schema must exist before minigame migration';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'student_scores'
          AND column_name = 'minigame' AND data_type <> 'text'
    ) THEN
        RAISE EXCEPTION 'Existing minigame column is not TEXT; manual review required';
    END IF;
END
$preconditions$;

ALTER TABLE student_scores
    ADD COLUMN IF NOT EXISTS minigame TEXT NOT NULL DEFAULT 'Legacy';

-- The former uniqueness constraint combined unrelated minigames. Introduce
-- new uniqueness FIRST, then remove only that specifically named old key.
DO $constraints$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'student_scores'::regclass
          AND conname = 'uq_student_scores_minigame_identity'
    ) THEN
        EXECUTE 'ALTER TABLE student_scores '
             || 'ADD CONSTRAINT uq_student_scores_minigame_identity '
             || 'UNIQUE (student_id, minigame, game_style, game_mode, difficulty)';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'student_scores'::regclass
          AND conname = 'student_scores_student_id_game_style_game_mode_difficulty_key'
    ) THEN
        EXECUTE 'ALTER TABLE student_scores '
             || 'DROP CONSTRAINT student_scores_student_id_game_style_game_mode_difficulty_key';
    END IF;
END
$constraints$;

-- Keep the existing index and add the new activity-qualified lookup index.
CREATE INDEX IF NOT EXISTS idx_student_scores_minigame_leaderboard
    ON student_scores (minigame, game_style, game_mode, difficulty, score DESC);
