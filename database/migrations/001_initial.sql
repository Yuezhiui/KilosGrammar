-- Review the target database and backup any existing data before applying.
-- Transactional when run with database.migrate; never drops or truncates data.
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

CREATE INDEX IF NOT EXISTS idx_student_scores_leaderboard
    ON student_scores (game_style, game_mode, difficulty, score DESC);
