"""Read-only beta.5 leaderboard admin-token diagnosis.

Tests use fake stores and ephemeral sockets only. No installed PostgreSQL,
live API port, actual Windows token, CSV data or destructive HTTP actions.
"""

from __future__ import annotations

import json
import os
import socket
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from database.server import API, ExclusiveLoopbackHTTPServer, _create_admin_token, make_handler


class ZeroMutationStore:
    """An auth probe must never access student records or issue writes."""

    def __init__(self):
        self.calls: list[str] = []

    def get_leaderboard(self, *_args, **_kwargs):
        self.calls.append("leaderboard")
        return []

    def export_snapshot(self):
        raise AssertionError("unexpected student-profile export")

    def import_snapshot(self, *_args):
        raise AssertionError("unexpected data import")

    def delete_all(self):
        raise AssertionError("unexpected deletion")


class TokenBoundaryTests(unittest.TestCase):
    def test_stable_local_token_survives_same_user_api_restart(self):
        store = ZeroMutationStore()
        with tempfile.TemporaryDirectory(prefix="kg_admin_isolated_") as folder:
            with patch.dict(os.environ, {"LOCALAPPDATA": folder}):
                old_token = _create_admin_token()
                old_api = API(store, admin_token=old_token)
                new_token = _create_admin_token()
                current_file_token = (Path(folder) / "KilosGrammar" / "admin_api_token.txt").read_text()
                self.assertEqual(new_token, current_file_token)
                self.assertEqual(old_token, new_token,
                                 "a restarted API must not rotate token away from existing listener")

                # This fake unknown GET is authenticated yet invokes NO database
                # operation. Expected successful auth is *404 unknown route*.
                probe = "/data/authorization-probe-does-not-exist"
                accepted, result = old_api.dispatch("GET", probe, admin_token=old_token)
                self.assertEqual((accepted, result["error"]["code"]), (404, "not_found"))
                new_api = API(store, admin_token=new_token)
                self.assertEqual(new_api.dispatch("GET", probe, admin_token=current_file_token)[0], 404)
                self.assertEqual(store.calls, [])

    def test_mismatched_stale_token_is_a_403_not_an_os_privilege_problem(self):
        store = ZeroMutationStore()
        old_api = API(store, admin_token="process-1-mock-token")
        current_file_token = "process-2-mock-token"
        probe = "/data/authorization-probe-does-not-exist"
        status, result = old_api.dispatch("GET", probe, admin_token=current_file_token)
        self.assertEqual((status, result["error"]["code"]), (403, "admin_authorization_required"))
        self.assertEqual(store.calls, [])

    def test_existing_api_can_resync_from_valid_same_user_token_file(self):
        store = ZeroMutationStore()
        with tempfile.TemporaryDirectory(prefix="kg_admin_resync_") as folder:
            file = Path(folder) / "admin_api_token.txt"
            original = "original-mock-token-" + ("x" * 28)
            replacement = "replacement-mock-token-" + ("y" * 28)
            file.write_text(original, encoding="ascii")
            api = API(store, admin_token=original)
            api._admin_token_file = file
            probe = "/data/authorization-probe-does-not-exist"
            self.assertEqual(api.dispatch("GET", probe, admin_token=original)[0], 404)
            file.write_text(replacement, encoding="ascii")
            self.assertEqual(api.dispatch("GET", probe, admin_token=replacement)[0], 404)
            self.assertEqual(api.dispatch("GET", probe, admin_token=original)[0], 403)
            self.assertEqual(store.calls, [])

    def test_admin_auth_is_a_local_token_not_windows_elevation(self):
        store = ZeroMutationStore()
        api = API(store, admin_token="private-mock-token")
        probe = "/data/authorization-probe-does-not-exist"
        status, response = api.dispatch("GET", probe)
        self.assertEqual((status, response["error"]["code"]), (403, "admin_authorization_required"))
        status, response = api.dispatch("GET", probe, admin_token="wrong-token")
        self.assertEqual((status, response["error"]["code"]), (403, "admin_authorization_required"))
        status, response = api.dispatch("GET", probe, admin_token="private-mock-token")
        self.assertEqual((status, response["error"]["code"]), (404, "not_found"))
        status, response = api.dispatch("GET", "/leaderboard")
        self.assertEqual((status, response["data"]["count"]), (200, 0))
        self.assertEqual(store.calls, ["leaderboard"])

    def test_http_header_on_nonexistent_readonly_data_path(self):
        store = ZeroMutationStore()
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(API(store, admin_token="mock-key")))
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            endpoint = f"http://127.0.0.1:{httpd.server_port}/data/authorization-probe-does-not-exist"
            for token, expected in ((None, 403), ("wrong", 403), ("mock-key", 404)):
                with self.subTest(token="none" if token is None else "supplied"):
                    headers = {"X-Kilos-Admin-Token": token} if token is not None else {}
                    try:
                        with urlopen(Request(endpoint, headers=headers), timeout=2) as response:
                            actual = response.status
                    except HTTPError as error:
                        actual = error.code
                    self.assertEqual(actual, expected)
            self.assertEqual(store.calls, [])
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=3)


class ServerPortExclusivityTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows bind behavior; verified on Windows beta runtime")
    def test_stdlib_threading_http_server_can_duplicate_bound_windows_loopback_port(self):
        # Characterization of the current production ThreadingHTTPServer:
        # SO_REUSEADDR allows two live local servers to hold the same port.
        first = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(API(ZeroMutationStore(), "a")))
        second = None
        try:
            second = ThreadingHTTPServer(("127.0.0.1", first.server_port),
                                         make_handler(API(ZeroMutationStore(), "b")))
            self.assertEqual(first.server_port, second.server_port)
            self.assertTrue(first.socket.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR))
        finally:
            if second is not None:
                second.server_close()
            first.server_close()

    @unittest.skipUnless(os.name == "nt" and hasattr(socket, "SO_EXCLUSIVEADDRUSE"),
                         "Windows exclusive socket option required")
    def test_proposed_exclusive_bind_prevents_second_server(self):
        # Proposed production fix demonstrated entirely in this test class.
        # No mutation to server.py or currently listening port 18765.
        class ExclusiveHttpServer(ThreadingHTTPServer):
            allow_reuse_address = False

            def server_bind(self):
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
                super().server_bind()

        first = ExclusiveHttpServer(("127.0.0.1", 0),
                                    make_handler(API(ZeroMutationStore(), "a")))
        try:
            with self.assertRaises(OSError):
                duplicate = ThreadingHTTPServer(("127.0.0.1", first.server_port),
                                                make_handler(API(ZeroMutationStore(), "b")))
                duplicate.server_close()
        finally:
            first.server_close()

    @unittest.skipUnless(os.name == "nt", "Production Windows-only exclusive bind")
    def test_actual_patched_server_rejects_duplicate_loopback_listener(self):
        first = ExclusiveLoopbackHTTPServer(("127.0.0.1", 0),
                                            make_handler(API(ZeroMutationStore(), "a")))
        try:
            with self.assertRaises(OSError):
                duplicate = ExclusiveLoopbackHTTPServer(("127.0.0.1", first.server_port),
                                                         make_handler(API(ZeroMutationStore(), "b")))
                duplicate.server_close()
            # Also refuse a legacy caller trying SO_REUSEADDR against exclusive.
            with self.assertRaises(OSError):
                duplicate = ThreadingHTTPServer(("127.0.0.1", first.server_port),
                                                make_handler(API(ZeroMutationStore(), "legacy")))
                duplicate.server_close()
        finally:
            first.server_close()


if __name__ == "__main__":
    unittest.main()
