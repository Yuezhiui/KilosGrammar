"""Static safety contract for the teacher-approved existing-score upgrade.

No real database, passwords, backups, migrations or network connections.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
UPGRADE = (ROOT / "database" / "upgrade_existing_scores.ps1").read_text(encoding="utf-8")
WIZARD = (ROOT / "database" / "setup_from_game.ps1").read_text(encoding="utf-8")
MIGRATION = (ROOT / "database" / "migrations" / "002_add_minigame.sql").read_text(encoding="utf-8")


class ExistingScoreUpgradeSafety(unittest.TestCase):
    def test_backup_verified_before_any_migration(self):
        self.assertLess(UPGRADE.index("& $pgDump"), UPGRADE.index("& $pgRestore --list"))
        self.assertLess(UPGRADE.index("& $pgRestore --list"), UPGRADE.index("Read-Host 'Type MIGRATE"))
        self.assertLess(UPGRADE.index("Read-Host 'Type MIGRATE"), UPGRADE.index("--apply-minigame"))

    def test_upgrade_is_never_automatic(self):
        self.assertIn("if ($CheckOnly)", UPGRADE)
        self.assertIn("-cne 'MIGRATE'", UPGRADE)
        self.assertIn("$migrationStarted = $true", UPGRADE)
        self.assertIn("$inspectionResult -ne 'LEGACY_001'", UPGRADE)
        self.assertNotIn("--apply-minigame", WIZARD)
        self.assertIn("& $upgradeScript", WIZARD)
        self.assertIn("'5' { $requestedMode = 'UPGRADE' }", WIZARD)

    def test_old_data_is_preserved_by_migration(self):
        self.assertIn("DEFAULT 'Legacy'", MIGRATION)
        self.assertIn("uq_student_scores_minigame_identity", MIGRATION)
        self.assertNotIn("TRUNCATE TABLE", MIGRATION.upper())
        self.assertNotIn("DELETE FROM", MIGRATION.upper())
        self.assertNotIn("DROP TABLE", MIGRATION.upper())


if __name__ == "__main__":
    unittest.main()
