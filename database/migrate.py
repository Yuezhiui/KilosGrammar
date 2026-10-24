"""Opt-in schema creation: python -m database.migrate --apply."""

from __future__ import annotations

import argparse
from pathlib import Path

from .config import Config


MIGRATION = Path(__file__).with_name("migrations") / "001_initial.sql"
MINIGAME_MIGRATION = Path(__file__).with_name("migrations") / "002_add_minigame.sql"


def main() -> None:
    parser = argparse.ArgumentParser(description="Review and opt into KILOS GRAMMAR schema creation")
    parser.add_argument("--apply", action="store_true", help="Explicitly run the idempotent schema SQL")
    parser.add_argument(
        "--apply-minigame", action="store_true",
        help="Explicitly apply reviewed 002 forward-only minigame migration (back up database first)",
    )
    args = parser.parse_args()
    if args.apply and args.apply_minigame:
        parser.error("Apply one migration at a time, in order. --apply and --apply-minigame are separate operations.")
    if not args.apply and not args.apply_minigame:
        print(f"Review {MIGRATION} and {MINIGAME_MIGRATION}, and back up the database first.")
        print("Run 001 when needed: python -m database.migrate --apply")
        print("Then explicitly run 002: python -m database.migrate --apply-minigame")
        return

    import psycopg

    settings = Config.from_env()
    selected_migration = MINIGAME_MIGRATION if args.apply_minigame else MIGRATION
    # The connection context commits on success and rolls back on any failure.
    with psycopg.connect(**settings.connection_kwargs()) as connection:
        connection.execute(selected_migration.read_text(encoding="utf-8"))
    print(f"KILOS GRAMMAR schema migration {selected_migration.name} applied.")


if __name__ == "__main__":
    main()
