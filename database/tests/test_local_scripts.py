"""Windows startup behavior tests, without credentials or PostgreSQL writes."""

from __future__ import annotations

import ast
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AUTO = ROOT / "database" / "start_auto.ps1"
CONFIGURE = ROOT / "database" / "configure_local.ps1"
GAME_SETUP = ROOT / "database" / "setup_from_game.ps1"


@unittest.skipUnless(sys.platform == "win32" and shutil.which("powershell.exe"), "Windows PowerShell required")
class LocalScriptsTests(unittest.TestCase):
    @staticmethod
    def _unused_local_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return sock.getsockname()[1]

    def _run_powershell(self, source: str, timeout: int = 12) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", source],
            text=True, capture_output=True, timeout=timeout, cwd=ROOT, check=False,
        )

    def test_windows_scripts_parse_cleanly(self):
        source = (
            "$errors = @(); "
            "[System.Management.Automation.Language.Parser]::ParseFile('database/configure_local.ps1', "
            "[ref]$null, [ref]$errors) | Out-Null; "
            "[System.Management.Automation.Language.Parser]::ParseFile('database/start_auto.ps1', "
            "[ref]$null, [ref]$errors) | Out-Null; "
            "[System.Management.Automation.Language.Parser]::ParseFile('database/setup_from_game.ps1', "
            "[ref]$null, [ref]$errors) | Out-Null; "
            "if ($errors.Count -gt 0) { exit 1 }; exit 0"
        )
        result = self._run_powershell(source)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_existing_ready_service_does_not_require_credentials(self):
        class FakeReadyAPI(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != "/health":
                    self.send_response(404)
                    self.end_headers()
                    return
                raw = json.dumps({"ok": True, "data": {"status": "ok", "database": "connected"}}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), FakeReadyAPI)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            source = f"& '{AUTO}' -HttpPort {server.server_port}; exit $LASTEXITCODE"
            # `$LASTEXITCODE` isn't always set by a called PowerShell script
            # that uses `exit 0`, so its true process return value is checked.
            result = self._run_powershell(source)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("already ready", result.stdout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_port_occupied_by_unhealthy_service_fails_without_starting_child(self):
        class UnhealthyAPI(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(503)
                self.end_headers()

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), UnhealthyAPI)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            source = f"& '{AUTO}' -HttpPort {server.server_port}"
            result = self._run_powershell(source)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("health check failed", result.stdout + result.stderr)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_game_launches_visible_interactive_wizard_without_secrets_in_argv(self):
        # Replace only Start-Process with a local PowerShell function. This
        # exercises the real script path without launching any GUI or database.
        # Force a no-credentials branch without deleting any actual user file.
        source = r"""
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    if ($LiteralPath -like '*db_credentials.xml') { return $false }
    return Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Start-Process {
    [CmdletBinding()]
    param([string]$FilePath, [string[]]$ArgumentList,
          [string]$WorkingDirectory, [string]$WindowStyle)
    $global:MockWizardExe = $FilePath
    $global:MockWizardArgs = ($ArgumentList -join ' ')
    $global:MockWizardStyle = $WindowStyle
}
& 'REPLACE_PATH' -HttpPort REPLACE_PORT
if (-not $global:MockWizardExe) { throw 'Wizard was not launched' }
Write-Output ('WIZARD_EXE=' + $global:MockWizardExe)
Write-Output ('WIZARD_ARGS=' + $global:MockWizardArgs)
Write-Output ('WIZARD_STYLE=' + $global:MockWizardStyle)
""".replace("REPLACE_PATH", str(GAME_SETUP).replace("'", "''")).replace("REPLACE_PORT", str(self._unused_local_port()))
        result = self._run_powershell(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("WIZARD_EXE=", result.stdout)
        self.assertIn("powershell.exe", result.stdout.lower())
        self.assertIn("-NoExit", result.stdout)
        self.assertIn("-InteractiveSession", result.stdout)
        self.assertIn("-File", result.stdout)
        self.assertIn("WIZARD_STYLE=Normal", result.stdout)
        self.assertNotIn("KILOS_DB_PASSWORD", result.stdout)
        self.assertNotIn("KILOS_ADMIN_PASSWORD", result.stdout)

    def test_interactive_mode_can_report_healthy_service_without_prompt(self):
        class HealthyServer(BaseHTTPRequestHandler):
            def do_GET(self):
                raw = json.dumps({"ok": True, "data": {"status": "ok", "database": "connected"}}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, *_args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), HealthyServer)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            args = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                    str(GAME_SETUP), "-InteractiveSession", "-HttpPort", str(server.server_port)]
            result = subprocess.run(args, text=True, capture_output=True, timeout=10, cwd=ROOT, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("already online", result.stdout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_fresh_user_offered_generated_password_creation_with_consent(self):
        # Test the real wizard control flow against throwaway stub scripts.
        # No password, HTTP server, PostgreSQL account or database is touched.
        for selected_option, expected_mode in (("2", "CREATE_RANDOM"), ("3", "REPAIR_RANDOM")):
            with self.subTest(selected_option=selected_option):
                self._test_game_setup_mode(selected_option, expected_mode)

    def _test_game_setup_mode(self, selected_option: str, expected_mode: str):
        with tempfile.TemporaryDirectory(prefix="kilos_game_setup_") as root:
            folder = Path(root) / "database"
            (folder / ".venv" / "Scripts").mkdir(parents=True)
            (folder / ".venv" / "Scripts" / "python.exe").write_bytes(b"")
            fake_wizard = folder / "setup_from_game.ps1"
            fake_wizard.write_text(GAME_SETUP.read_text(encoding="utf-8"), encoding="utf-8")
            fake_config = folder / "configure_local.ps1"
            fake_config.write_text(
                "param([switch]$InitializeNewDatabase,[switch]$RepairNewAppCredentials,"
                "[switch]$GenerateAppPassword,[switch]$Migrate)\n"
                "$state = if ($InitializeNewDatabase -and $GenerateAppPassword) { 'CREATE_RANDOM' } "
                "elseif ($RepairNewAppCredentials -and $GenerateAppPassword) { 'REPAIR_RANDOM' } "
                "elseif ($Migrate) { 'MIGRATE' } else { 'LOGIN' }\n"
                "Add-Content -LiteralPath $env:KILOS_FAKE_SETUP_MARKER -Value $state\n"
                "exit 1\n",
                encoding="utf-8",
            )
            (folder / "start_auto.ps1").write_text("exit 1\n", encoding="utf-8")
            marker = Path(root) / "selected_mode.txt"
            environment = os.environ.copy()
            environment["KILOS_FAKE_SETUP_MARKER"] = str(marker)
            script_path = str(fake_wizard).replace("'", "''")
            source = r"""
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    if ($LiteralPath -like '*db_credentials.xml') { return $false }
    return Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
$global:FakeChoices = New-Object System.Collections.Queue
$global:FakeChoices.Enqueue('REPLACE_CHOICE')
$global:FakeChoices.Enqueue('Q')
function Read-Host {
    param([string]$Prompt)
    if ($global:FakeChoices.Count -eq 0) { throw 'Unexpected extra prompt' }
    return [string]$global:FakeChoices.Dequeue()
}
& 'REPLACE_PATH' -InteractiveSession -HttpPort REPLACE_PORT
""".replace("REPLACE_PATH", script_path).replace("REPLACE_CHOICE", selected_option).replace("REPLACE_PORT", str(self._unused_local_port()))
            result = subprocess.run(
                ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", source],
                text=True, capture_output=True, timeout=12, cwd=ROOT, env=environment, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(marker.exists(), result.stdout + result.stderr)
            self.assertEqual(marker.read_text(encoding="utf-8").strip(), expected_mode, result.stdout + result.stderr)
            if expected_mode == "CREATE_RANDOM":
                self.assertIn("generated application password", result.stdout.lower())
            else:
                self.assertIn("credential recovery", result.stdout.lower())

    def test_embedded_python_is_valid_and_avoids_native_argv_double_quote_issue(self):
        # Windows PowerShell 5.1 strips bare embedded double quotes in Python
        # -c arguments; this broke the first live bootstrap after DB creation.
        source = CONFIGURE.read_text(encoding="utf-8")
        snippets = re.findall(r"\$([a-zA-Z]+Source)\s*=\s*@'\n(.*?)\n'@", source, re.S)
        self.assertEqual({name for name, _ in snippets}, {"checkSource", "bootstrapSource", "repairSource"})
        for name, snippet in snippets:
            with self.subTest(source=name):
                ast.parse(snippet)
                self.assertNotIn('"', snippet, "Use single-quoted Python -c source in Windows PowerShell 5.1")


if __name__ == "__main__":
    unittest.main()
