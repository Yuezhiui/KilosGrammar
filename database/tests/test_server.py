from __future__ import annotations

import json
import http.client
import socket
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from database.server import API, make_handler
from database.storage import StudentIdentityConflict


class MemoryStore:
    """In-memory stand-in to verify requests without credentials or a live DB."""

    def __init__(self):
        self.students = {}
        self.scores = {}
        self.actions = []

    def health(self):
        return {"status": "ok", "database": "connected"}

    def find_student(self, student_id):
        return self.students.get(student_id)

    def register_student(self, student_id, student_name, grade_section):
        existing = self.students.get(student_id)
        if existing is not None:
            if (existing["student_name"], existing["grade_section"]) != (student_name, grade_section):
                raise StudentIdentityConflict()
            return existing, False
        profile = {
            "student_id": student_id,
            "student_name": student_name,
            "grade_section": grade_section,
            "created_at": "2026-10-23T00:00:00+00:00",
            "updated_at": "2026-10-23T00:00:00+00:00",
        }
        self.students[student_id] = profile
        self.actions.append("register")
        return profile, True

    def update_student(self, student_id, changes):
        if student_id not in self.students:
            return None
        self.students[student_id].update(changes)
        self.actions.append("update")
        return self.students[student_id]

    def find_score(self, student_id, game_style, game_mode, difficulty, minigame="Legacy"):
        return self.scores.get((student_id, minigame, game_style, game_mode, difficulty))

    def complete_round_and_replace_score(self, student_id, game_style, game_mode, difficulty, score, minigame="Legacy"):
        if student_id not in self.students:
            error = Exception("fake database details and password must stay hidden")
            error.sqlstate = "23503"
            raise error
        key = student_id, minigame, game_style, game_mode, difficulty
        item = {
            "score_id": len(self.scores) + 1,
            "student_id": student_id,
            "minigame": minigame,
            "game_style": game_style,
            "game_mode": game_mode,
            "difficulty": difficulty,
            "score": score,
            "completed_at": "2026-10-23T00:00:00+00:00",
            "updated_at": "2026-10-23T00:00:00+00:00",
        }
        if key in self.scores:
            item["score_id"] = self.scores[key]["score_id"]
        self.scores[key] = item
        self.actions.append("complete")
        return item

    def get_leaderboard(self, game_style, game_mode, difficulty, grade_section, limit, minigame=None):
        data = []
        for score in self.scores.values():
            student = self.students[score["student_id"]]
            if minigame is not None and score["minigame"] != minigame:
                continue
            if game_style is not None and score["game_style"] != game_style:
                continue
            if game_mode is not None and score["game_mode"] != game_mode:
                continue
            if difficulty is not None and score["difficulty"] != difficulty:
                continue
            if grade_section is not None and student["grade_section"] != grade_section:
                continue
            data.append({**score, "student_name": student["student_name"], "grade_section": student["grade_section"]})
        data.sort(key=lambda row: (-row["score"], row["completed_at"], row["student_id"]))
        return [{"rank": i, **row} for i, row in enumerate(data[:limit], 1)]


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryStore()
        self.api = API(self.store)

    def _register(self, id="KG-001", name="Rosa", grade="4-A"):
        return self.api.dispatch("POST", "/students", {"student_id": id, "student_name": name, "grade_section": grade})

    def _score(self, student_id="KG-001", style="Noun", mode="Seconds", difficulty="Easy", score=10, route="/rounds/complete", minigame=None):
        payload = {
            "student_id": student_id, "game_style": style, "game_mode": mode,
            "difficulty": difficulty, "score": score,
        }
        if minigame is not None:
            payload["minigame"] = minigame
        return self.api.dispatch("POST", route, payload)

    def test_health_registration_lookup_and_explicit_update(self):
        status, response = self.api.dispatch("GET", "/health")
        self.assertEqual((status, response["data"]["database"]), (200, "connected"))
        self.assertEqual(self._register()[0], 201)
        status, response = self.api.dispatch("GET", "/students/KG-001")
        self.assertEqual(response["data"]["student"]["student_name"], "Rosa")
        self.assertEqual(status, 200)
        status, response = self.api.dispatch("PATCH", "/students/KG-001", {"grade_section": "4-B"})
        self.assertEqual(status, 200)
        self.assertEqual(response["data"]["student"]["grade_section"], "4-B")
        self.assertEqual(self.store.actions, ["register", "update"])

    def test_idempotent_registration_does_not_implicitly_edit(self):
        self.assertEqual(self._register()[0], 201)
        self.assertEqual(self._register()[0], 200)
        status, response = self._register(name="Changed Without Teacher Action")
        self.assertEqual(status, 409)
        self.assertEqual(response["error"]["code"], "student_exists")
        self.assertEqual(self.store.students["KG-001"]["student_name"], "Rosa")
        self.assertEqual(self.store.actions, ["register"])

    def test_completed_score_replaces_even_with_lower_result(self):
        self._register()
        self.assertEqual(self._score(score=30)[0], 200)
        self.assertEqual(self._score(score=9)[0], 200)
        self.assertEqual(len(self.store.scores), 1)
        status, response = self.api.dispatch(
            "GET", "/scores?student_id=KG-001&game_style=Noun&game_mode=Seconds&difficulty=Easy"
        )
        self.assertEqual((status, response["data"]["score"]["score"]), (200, 9))
        self.assertEqual(self.store.actions.count("complete"), 2)

    def test_independent_difficulties_modes_styles_and_students(self):
        self._register()
        self._register("KG-002", "Ben", "4-B")
        self._score(score=10)
        self._score(difficulty="Hard", score=20)
        self._score(mode="Lives", score=30)
        self._score(style="Verb", score=40)
        self._score(student_id="KG-002", score=50)
        self.assertEqual(len(self.store.scores), 5)
        status, response = self.api.dispatch("GET", "/leaderboard")
        self.assertEqual(status, 200)
        self.assertEqual(response["data"]["count"], 5)
        self.assertEqual(response["data"]["leaderboard"][0]["game_style"], "Noun")
        self.assertEqual(response["data"]["leaderboard"][0]["grade_section"], "4-B")
        status, response = self.api.dispatch(
            "GET", "/leaderboard?game_style=Noun&game_mode=Seconds&difficulty=Easy&grade_section=4-A"
        )
        self.assertEqual(status, 200)
        self.assertEqual(response["data"]["count"], 1)
        status, response = self.api.dispatch("GET", "/leaderboard?game_style=&game_mode=&difficulty=&limit=2")
        self.assertEqual(status, 200)
        self.assertEqual(response["data"]["count"], 2)

    def test_bad_and_cancelled_rounds_cannot_modify_scores(self):
        self._register()
        self._score(score=25)
        for value in (-1, True, 1.5, "25", 2147483648):
            status, response = self._score(score=value)
            self.assertEqual((status, response["error"]["code"]), (400, "invalid_input"))
        status, response = self.api.dispatch("POST", "/rounds/complete", {
            "student_id": "KG-001", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
            "score": 3, "completed": False,
        })
        self.assertEqual(status, 400)
        self.assertEqual(self.store.scores[("KG-001", "Legacy", "Noun", "Seconds", "Easy")]["score"], 25)

    def test_minigame_scores_are_distinct_and_legacy_compatibility_explicit(self):
        self._register()
        for minigame, score in (("Catch the Word", 125), ("Human Plane", 80), ("Balloon Popping", 40)):
            self.assertEqual(self._score(minigame=minigame, score=score)[0], 200)
        self.assertEqual(self._score(minigame="Human Plane", score=3)[0], 200)
        self.assertEqual(self._score(score=17)[0], 200)  # old caller => Legacy only
        self.assertEqual(len(self.store.scores), 4)
        base = "/scores?student_id=KG-001&game_style=Noun&game_mode=Seconds&difficulty=Easy"
        self.assertEqual(self.api.dispatch("GET", base)[1]["data"]["score"]["score"], 17)
        for minigame, expected in (("Catch the Word", 125), ("Human Plane", 3), ("Balloon Popping", 40)):
            status, response = self.api.dispatch("GET", base + "&minigame=" + minigame.replace(" ", "%20"))
            self.assertEqual(status, 200)
            self.assertEqual(response["data"]["score"]["score"], expected)
            status, response = self.api.dispatch("GET", "/leaderboard?minigame=" + minigame.replace(" ", "%20"))
            self.assertEqual(status, 200)
            self.assertEqual(response["data"]["count"], 1)
            self.assertEqual(response["data"]["leaderboard"][0]["minigame"], minigame)
        self.assertEqual(self.api.dispatch("GET", "/leaderboard")[1]["data"]["count"], 4)
        self.assertEqual(self._score(minigame="", score=999)[0], 400)

    def test_missing_and_invalid_queries_and_confidential_errors(self):
        self.assertEqual(self.api.dispatch("GET", "/students/UNKNOWN")[0], 404)
        self.assertEqual(self.api.dispatch("GET", "/scores?student_id=KG-001")[0], 400)
        self.assertEqual(self.api.dispatch("GET", "/leaderboard?limit=999")[0], 400)
        self.assertEqual(self.api.dispatch("GET", "/leaderboard?limit=2&limit=3")[0], 400)
        self.assertEqual(self.api.dispatch("PATCH", "/students/KG-001", {})[0], 400)
        self.assertEqual(self.api.dispatch("POST", "/students", {"student_id": "../../evil"})[0], 400)
        status, response = self._score(student_id="UNKNOWN")
        self.assertEqual(status, 404)
        self.assertNotIn("password", json.dumps(response).lower())

    def test_alias_for_completed_score(self):
        self._register()
        self.assertEqual(self._score(route="/scores/completed")[0], 200)


class RealHttpBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.store = MemoryStore()
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(API(cls.store)))
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.httpd.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=5)

    def request(self, method, path, body=None, content_type="application/json", extra_headers=None):
        raw = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Content-Type": content_type} if raw is not None else {}
        headers.update(extra_headers or {})
        request = Request(self.base + path, data=raw, headers=headers, method=method)
        try:
            with urlopen(request, timeout=3) as response:
                return response.status, json.load(response), response.headers
        except HTTPError as error:
            return error.code, json.load(error), error.headers

    def raw_request(self, method, path, headers=(), body=b""):
        """Use a plain loopback HTTP socket; assert framing, not just status."""
        connection = http.client.HTTPConnection("127.0.0.1", self.httpd.server_port, timeout=3)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for name, value in headers:
                connection.putheader(name, value)
            connection.endheaders(body)
            reply = connection.getresponse()
            raw = reply.read()
            self.assertEqual(reply.version, 11)
            self.assertEqual(reply.getheader("Content-Length"), str(len(raw)))
            self.assertEqual(reply.getheader("Connection"), "close")
            self.assertEqual(reply.getheader("Cache-Control"), "no-store")
            self.assertEqual(reply.getheader("X-Content-Type-Options"), "nosniff")
            self.assertIsNone(reply.getheader("Access-Control-Allow-Origin"))
            self.assertEqual(reply.getheader("Content-Type"), "application/json; charset=utf-8")
            payload = json.loads(raw.decode("utf-8"))
            return reply.status, payload, reply
        finally:
            connection.close()

    def test_complete_403_json_on_invalid_host_or_origin_with_unread_post_body(self):
        port = self.httpd.server_port
        body = json.dumps({
            "student_id": "DENIED-RAW", "student_name": "Never Created", "grade_section": "5-R"
        }).encode("utf-8")
        scenarios = [
            (("Host", f"other-host.example:{port}"), "forbidden_host"),
            (("Host", f"0.0.0.0:{port}"), "forbidden_host"),
            (("Origin", "https://different.example"), "forbidden_origin"),
            (("Origin", f"http://localhost:{port}"), "forbidden_origin"),
        ]
        for header, expected_code in scenarios:
            with self.subTest(header=header):
                headers = [("Host", f"127.0.0.1:{port}")]
                if header[0] == "Host":
                    headers = [header]
                else:
                    headers.append(header)
                headers.extend([
                    ("Content-Type", "application/json"), ("Content-Length", str(len(body)))
                ])
                status, result, reply = self.raw_request("POST", "/students", headers, body)
                self.assertEqual(status, 403)
                self.assertEqual(result["error"]["code"], expected_code)
                self.assertEqual(result["data"], None)
                self.assertEqual(result["ok"], False)
        self.assertNotIn("DENIED-RAW", self.store.students)

    def test_raw_preflight_duplicate_headers_and_proxy_target_denied_as_json(self):
        port = self.httpd.server_port
        scenarios = [
            ("OPTIONS", "/students", [
                ("Host", f"127.0.0.1:{port}"), ("Origin", "https://outside.example"),
                ("Access-Control-Request-Method", "POST"),
            ], 403, "forbidden_origin"),
            ("GET", "/health", [
                ("Host", f"localhost:{port}"), ("Host", f"127.0.0.1:{port}"),
            ], 403, "forbidden_host"),
            ("GET", "/health", [
                ("Host", f"localhost:{port}"), ("Origin", f"http://localhost:{port}"),
                ("Origin", f"http://localhost:{port}"),
            ], 403, "forbidden_origin"),
            ("GET", "http://outside.example/health", [
                ("Host", f"127.0.0.1:{port}"),
            ], 400, "invalid_target"),
            ("OPTIONS", "/students", [
                ("Host", f"127.0.0.1:{port}"),
            ], 405, "method_not_allowed"),
        ]
        for method, path, headers, expected_status, expected_code in scenarios:
            with self.subTest(method=method, path=path, headers=headers):
                status, result, _ = self.raw_request(method, path, headers)
                self.assertEqual(status, expected_status)
                self.assertEqual(result["error"]["code"], expected_code)

    def test_denial_without_complete_post_body_does_not_block_indefinitely(self):
        port = self.httpd.server_port
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        try:
            connection.putrequest("POST", "/students", skip_host=True)
            connection.putheader("Host", f"127.0.0.1:{port}")
            connection.putheader("Origin", "https://foreign.example")
            connection.putheader("Content-Type", "application/json")
            connection.putheader("Content-Length", "50")
            # No body follows; server should still reject under a short
            # deadline rather than waiting for the declared length forever.
            connection.endheaders()
            reply = connection.getresponse()
            self.assertEqual(reply.status, 403)
            self.assertEqual(json.load(reply)["error"]["code"], "forbidden_origin")
            self.assertIsNone(reply.getheader("Access-Control-Allow-Origin"))
        finally:
            connection.close()

    def test_expect_continue_never_precedes_invalid_host_or_origin_denial(self):
        port = self.httpd.server_port
        for header in (
            f"Host: wrong.example:{port}\r\n",
            f"Host: 127.0.0.1:{port}\r\nOrigin: https://outside.example\r\n",
        ):
            with self.subTest(header=header):
                request = (
                    f"POST /students HTTP/1.1\r\n{header}"
                    "Expect: 100-continue\r\n"
                    "Content-Type: application/json\r\nContent-Length: 80\r\n\r\n"
                ).encode("ascii")
                with socket.create_connection(("127.0.0.1", port), timeout=3) as client:
                    client.sendall(request)
                    fragments = []
                    while True:
                        fragment = client.recv(65536)
                        if not fragment:
                            break
                        fragments.append(fragment)
                    raw = b"".join(fragments)
                self.assertTrue(raw.startswith(b"HTTP/1.1 403 Forbidden\r\n"), raw)
                self.assertNotIn(b"100 Continue", raw)
                headers, body = raw.split(b"\r\n\r\n", 1)
                self.assertIn(b"Connection: close", headers)
                self.assertNotIn(b"Access-Control-Allow-Origin", headers)
                decoded = json.loads(body.decode("utf-8"))
                self.assertEqual(decoded["error"]["code"], (
                    "forbidden_host" if "wrong.example" in header else "forbidden_origin"
                ))

    def test_http_json_contract_and_utf8(self):
        status, response, headers = self.request("POST", "/students", {
            "student_id": "KG-HTTP", "student_name": "Niña", "grade_section": "5-C",
        })
        self.assertEqual(status, 201)
        self.assertEqual(response["data"]["student"]["student_name"], "Niña")
        self.assertEqual(headers["Cache-Control"], "no-store")
        status, response, _ = self.request("GET", "/students/KG-HTTP")
        self.assertEqual(status, 200)
        self.assertTrue(response["ok"])
        status, response, _ = self.request("POST", "/rounds/complete", {
            "student_id": "KG-HTTP", "game_style": "Noun", "game_mode": "Lives", "difficulty": "Hard", "score": 15,
        })
        self.assertEqual((status, response["data"]["score"]["score"]), (200, 15))

    def test_invalid_content_type_and_json(self):
        status, response, _ = self.request("POST", "/students", {}, content_type="text/plain")
        self.assertEqual((status, response["error"]["code"]), (415, "invalid_content_type"))

    def test_binding_and_loopback_host_restrictions(self):
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")
        port = self.httpd.server_port
        for bad_host in (
            f"evil.example:{port}", f"localhost.evil.example:{port}",
            f"127.0.0.1.attacker.test:{port}", f"192.168.1.5:{port}",
            "localhost", f"127.0.0.1:{port + 1}",
        ):
            with self.subTest(host=bad_host):
                status, response, headers = self.request("GET", "/health", extra_headers={"Host": bad_host})
                self.assertEqual(status, 403)
                self.assertEqual(response["error"]["code"], "forbidden_host")
                self.assertIsNone(headers.get("Access-Control-Allow-Origin"))

    def test_reject_cross_origin_writes_before_talking_to_store(self):
        port = self.httpd.server_port
        payload = {"student_id": "BLOCKED-ORIGIN", "student_name": "Malicious", "grade_section": "1-A"}
        # Some Windows security agents abort HTTP sockets containing a raw
        # 'Origin: file://' header before the Python server can respond.
        # These nonlocal origins exercise the same server-side rejection.
        for origin in ("https://example.com", f"http://localhost:{port}", "null", "https://attacker.example"):
            with self.subTest(origin=origin):
                status, response, headers = self.request(
                    "POST", "/students", payload,
                    extra_headers={"Host": f"127.0.0.1:{port}", "Origin": origin},
                )
                self.assertEqual(status, 403)
                self.assertEqual(response["error"]["code"], "forbidden_origin")
                self.assertIsNone(headers.get("Access-Control-Allow-Origin"))
        self.assertNotIn("BLOCKED-ORIGIN", self.store.students)

    def test_same_origin_or_native_client_is_allowed(self):
        port = self.httpd.server_port
        for host in (f"127.0.0.1:{port}", f"localhost:{port}"):
            with self.subTest(host=host):
                status, result, headers = self.request(
                    "GET", "/health", extra_headers={"Host": host, "Origin": "http://" + host}
                )
                self.assertEqual(status, 200)
                self.assertEqual(result["data"]["status"], "ok")
                self.assertIsNone(headers.get("Access-Control-Allow-Origin"))
        status, result, _ = self.request("GET", "/health")
        self.assertEqual((status, result["ok"]), (200, True))

    def test_preflight_from_external_site_is_blocked(self):
        status, result, headers = self.request(
            "OPTIONS", "/students", extra_headers={"Origin": "https://attacker.example"}
        )
        self.assertEqual(status, 403)
        self.assertEqual(result["error"]["code"], "forbidden_origin")
        self.assertIsNone(headers.get("Access-Control-Allow-Origin"))

    def test_missing_or_duplicate_host_or_origin_is_rejected(self):
        port = self.httpd.server_port
        examples = (
            ((), 403, "forbidden_host"),
            ((("Host", f"localhost:{port}"), ("Host", f"evil.example:{port}")), 403, "forbidden_host"),
            ((("Host", f"localhost:{port}"), ("Origin", f"http://localhost:{port}"),
              ("Origin", f"http://localhost:{port}")), 403, "forbidden_origin"),
        )
        for header_items, expected_status, expected_error in examples:
            with self.subTest(headers=header_items):
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                try:
                    connection.putrequest("GET", "/health", skip_host=True)
                    for name, value in header_items:
                        connection.putheader(name, value)
                    connection.endheaders()
                    response = connection.getresponse()
                    self.assertEqual(response.status, expected_status)
                    result = json.load(response)
                    self.assertEqual(result["error"]["code"], expected_error)
                finally:
                    connection.close()

    def test_rejected_host_cannot_register_student(self):
        port = self.httpd.server_port
        body = json.dumps({"student_id": "BLOCKED-HOST", "student_name": "Hidden", "grade_section": "5-Z"}).encode()
        status, response, _ = self.raw_request("POST", "/students", (
            ("Host", f"evil.example:{port}"),
            ("Content-Type", "application/json"),
            ("Content-Length", str(len(body))),
        ), body)
        self.assertEqual(status, 403)
        self.assertEqual(response["error"]["code"], "forbidden_host")
        self.assertNotIn("BLOCKED-HOST", self.store.students)


class DeniedResponseTransportTests(unittest.TestCase):
    def _handler_with_writer(self, writer):
        handler = make_handler(API(MemoryStore())).__new__(make_handler(API(MemoryStore())))
        handler.wfile = writer
        handler.send_response = lambda _status: None
        handler.send_header = lambda _name, _value: None
        handler.end_headers = lambda: None
        handler.close_connection = False
        return handler

    def test_benign_peer_disconnect_during_403_write_is_only_a_transport_failure(self):
        for error in (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            class GoneWriter:
                def write(self, _payload):
                    raise error("peer disconnected")

            with self.subTest(error=error):
                handler = self._handler_with_writer(GoneWriter())
                handler._error(403, "forbidden_origin", "Cross-origin access is not allowed")
                self.assertTrue(handler.close_connection)

    def test_unrelated_write_errors_are_not_silenced(self):
        class UnexpectedWriter:
            def write(self, _payload):
                raise OSError("unexpected response write failure")

        handler = self._handler_with_writer(UnexpectedWriter())
        with self.assertRaisesRegex(OSError, "unexpected response write failure"):
            handler._error(403, "forbidden_host", "Use the local service address")
        self.assertTrue(handler.close_connection)


if __name__ == "__main__":
    unittest.main()
