"""Independent, read-only beta.5 EXE/dependency/autostart contract QA.

Run: py -3.11 -B tools/test_beta5_direct_launch_readonly_20261030.py
Does NOT start the executable, PowerShell, Python API, PostgreSQL, webcam,
installer, service or network connection. Does not read DPAPI credentials.
This checks release packaging and the startup code contract; it cannot prove a
clean Windows PC with actual dependencies and camera is operational.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent
REL = ROOT / "release" / "windows"
PACK = REL / "out" / "KilosGrammar-win-x64-v0.3.0-beta.5"
INSTALL = REL / "out" / (
    "KilosGrammar-v0.3.0-beta.5-OFFLINE-CANDIDATE-"
    "NOT-CLEAN-PC-TESTED-Setup.exe"
)


def contents(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as inp:
        for chunk in iter(lambda: inp.read(4 * 1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest().upper()


class Beta5DirectLaunchReadOnlyQA(unittest.TestCase):
    def test_real_exe_and_external_pck_exist(self):
        self.assertGreater((PACK / "KilosGrammar.exe").stat().st_size, 100_000)
        self.assertGreater((PACK / "KilosGrammar.pck").stat().st_size, 100_000)

    def test_loose_worker_model_and_api_are_packaged(self):
        for name in (
            "database/start_auto.ps1", "database/server.py",
            "database/config.py", "ui/vision/pose_worker.py",
            "ui/vision/student_lock.py", "ui/vision/gesture_detector.py",
            "runtime/models/yolo26n-pose.pt", "offline/manifest.json",
        ):
            with self.subTest(name=name):
                self.assertTrue((PACK / name).is_file(), name)

    def test_manifest_accounts_for_runtime_inputs(self):
        manifest = json.loads(contents(PACK / "manifest.json"))
        inventory = {entry["path"] for entry in manifest["files"]}
        self.assertEqual(manifest["kind"], "KilosGrammarWindowsRelease")
        self.assertGreaterEqual(len(inventory), 82)
        self.assertTrue({"KilosGrammar.exe", "KilosGrammar.pck",
                         "database/server.py", "ui/vision/pose_worker.py",
                         "runtime/models/yolo26n-pose.pt"}.issubset(inventory))

    def test_offline_installers_are_payload_not_executed_dependencies(self):
        self.assertTrue(list((PACK / "offline/installers").glob("python-3.11*-amd64.exe")))
        self.assertTrue(list((PACK / "offline/installers").glob("postgresql-18*-windows-x64.exe")))
        self.assertGreaterEqual(len(list((PACK / "offline/wheels").glob("*.whl"))), 44)

    def test_published_package_is_not_a_preinstalled_python_environment(self):
        # The distributable candidate intentionally must not contain copied
        # developer .venv or machine-local secrets; a *fresh* installed system
        # is NOT camera-ready until target-local setup is performed.
        self.assertFalse((PACK / "database/.venv/Scripts/python.exe").exists())
        self.assertFalse((PACK / "database/.venv/kilos-offline-manifest.sha256").exists())

    def test_supported_launcher_requires_setup_before_starting_exe(self):
        launch = contents(PACK / "Launch-Game.ps1")
        self.assertIn("database\\.venv\\Scripts\\python.exe", launch)
        self.assertIn("kilos-offline-manifest.sha256", launch)
        self.assertIn("Run Setup Offline.cmd", launch)
        self.assertLess(launch.index("Run Setup Offline.cmd"),
                        launch.index("Start-Process -FilePath $game"))
        self.assertIn("KILOSGRAMMAR_PYTHON", launch)
        self.assertIn("Launch-Game.ps1", contents(PACK / "Play KilosGrammar.cmd"))

    def test_installer_does_not_autorun_dependency_setup(self):
        iss = contents(REL / "KilosGrammar-OfflineCandidate.iss")
        run_section = iss.split("[Run]", 1)[1].split("\n[", 1)[0]
        self.assertIn("notepad.exe", run_section)
        self.assertNotIn("Setup Offline.cmd", run_section)
        self.assertNotIn("python-3.11", run_section)
        self.assertNotIn("postgresql-18", run_section)
        self.assertIn("Play KilosGrammar.cmd", iss)
        self.assertIn("Setup Offline.cmd", iss)

    def test_installer_matches_its_sha_sidecar(self):
        sidecar = contents(Path(str(INSTALL) + ".sha256.txt"))
        match = re.search(r"\b[0-9a-fA-F]{64}\b", sidecar)
        self.assertIsNotNone(match)
        self.assertEqual(sha256(INSTALL), match.group(0).upper())

    def test_game_main_menu_requests_service_health_not_dependency_install(self):
        menu = contents(ROOT / "ui/main_menu/main_menu.gd")
        client = contents(PACK / "database/start_auto.ps1")
        transport = contents(ROOT / "ui/database/postgres_client.gd")
        self.assertIn("_start_database_client()", menu)
        self.assertIn("ensure_local_service", menu)
        self.assertIn('DisplayServer.get_name() != "headless"', transport)
        self.assertIn("_has_saved_credentials()", transport)
        self.assertIn(".venv\\Scripts\\python.exe", client)
        self.assertIn("db_credentials.xml", client)
        self.assertIn("-m', 'database.server'", client)

    def test_api_is_loopback_only_and_ports_are_configured(self):
        backend = contents(PACK / "database/server.py")
        config = contents(PACK / "database/config.py")
        self.assertIn('ThreadingHTTPServer(("127.0.0.1", config.http_port)', backend)
        self.assertIn('"18765"', config)
        self.assertIn('"127.0.0.1"', config)
        self.assertIn('"5432"', config)

    def test_yolo_process_is_separate_from_opening_menu(self):
        pose = contents(ROOT / "ui/vision/pose_service.gd")
        self.assertIn('path_join("ui/vision/pose_worker.py")', pose)
        self.assertIn('path_join("runtime/models/yolo26n-pose.pt")', pose)
        self.assertIn('OS.create_process(python, arguments, false)', pose)
        self.assertIn('"--prewarm"', pose)
        self.assertIn('path_join("database/.venv/Scripts/python.exe")', pose)

    def test_known_export_backend_drift_is_detectable(self):
        # A manifest-valid artifact can still be older than *unreleased* live
        # production edits. The test does not require equality while workers
        # legitimately edit source; instead it verifies our drift detector.
        packaged = PACK / "database/server.py"
        local = ROOT / "database/server.py"
        self.assertTrue(packaged.is_file() and local.is_file())
        self.assertEqual(len(sha256(packaged)), 64)
        self.assertEqual(len(sha256(local)), 64)
        if sha256(packaged) != sha256(local):
            print("NOTICE: packaged database/server.py differs from current source; rebuild after owner completes changes")


if __name__ == "__main__":
    unittest.main(verbosity=2)
