"""Real loopback HTTP tests for the advisor wire contract."""

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from leeway_hooks import client


@pytest.fixture
def service():
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append((self.path, body))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({"schema_version": 1, "account": "current", "verdict": "go", "agent": "claude", "model": "sonnet",
                                        "effort": "", "config_dir": "/profile",
                                        "reason": "available", "retry_at": None}).encode())

        def do_GET(self):
            calls.append((self.path, None))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps({"schema_version": 3, "generated_at": "now", "accounts": [
                {"id": "current", "provider": "claude", "config_dir": "/profile", "aliases": []},
                {"id": "code", "provider": "codex", "config_dir": "/profile", "aliases": []}], "history": {}}).encode())

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_port}", calls
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)


def test_client_posts_advise_and_reads_status(service):
    url, calls = service
    advisor = client.Advisor(url)
    data = {"repo": "/repo", "role": "builder", "task_class": "mechanical", "agent": "claude"}
    assert advisor.advise(data)["model"] == "sonnet"
    assert advisor.status()["schema_version"] == 3
    assert calls == [("/v1/advise", data), ("/v1/status", None)]


@pytest.mark.parametrize("url", ["https://127.0.0.1:8799", "http://example.com", "http://127.0.0.1:8799/path", "http://user:pass@127.0.0.1:8799"])
def test_client_rejects_non_loopback_or_ambiguous_urls(url):
    with pytest.raises(ValueError):
        client.Advisor(url)


def test_deny_response_needs_reason_but_not_a_usable_route():
    client.validate_advice({"schema_version": 1, "account": "", "verdict": "deny", "agent": "", "model": "",
                            "effort": "", "config_dir": "", "reason": "no quota", "retry_at": None})


@pytest.mark.parametrize("changes", [{"verdict": "unknown"}, {"agent": "other"}, {"model": ""}, {"retry_at": 42}])
def test_invalid_go_advice_is_rejected(changes):
    response = {"schema_version": 1, "account": "current", "verdict": "go", "agent": "claude", "model": "sonnet", "effort": "medium",
                "config_dir": "/profile", "reason": "available", "retry_at": None}
    response.update(changes)
    with pytest.raises(ValueError):
        client.validate_advice(response)



def test_v1_accepts_empty_effort_and_codex_model():
    client.validate_advice({"schema_version": 1, "account": "code", "verdict": "go", "agent": "codex",
                            "model": "", "effort": "", "config_dir": "/profile", "reason": "available",
                            "retry_at": None})


@pytest.mark.parametrize("version", [None, 2, True, "1"])
def test_v1_rejects_unknown_or_missing_schema_version(version):
    with pytest.raises(ValueError):
        client.validate_advice({"schema_version": version, "account": "current", "verdict": "go",
                                "agent": "claude", "model": "balanced", "effort": "", "config_dir": "/profile",
                                "reason": "available", "retry_at": None})


@pytest.mark.parametrize("url", ["http://127.0.0.1:0", "http://127.0.0.1:65536",
                                 "http://127.0.0.1:bad", "http://127.0.0.1:8799?x=1",
                                 "http://127.0.0.1:8799/#fragment"])
def test_client_rejects_invalid_ports_and_extra_url_components(url):
    with pytest.raises(ValueError):
        client.Advisor(url)


@pytest.mark.parametrize("status,raw", [(302, b'{}'), (500, b'{}'), (200, b'[]'),
                                       (200, b'{bad'), (200, b'x' * (client.MAX_RESPONSE_BYTES + 1))])
def test_client_rejects_redirects_errors_invalid_json_and_oversized_bodies(status, raw):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(status)
            self.send_header("Location", "http://example.invalid/")
            self.end_headers()
            self.wfile.write(raw)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with pytest.raises(ValueError):
            client.Advisor(f"http://127.0.0.1:{server.server_port}").status()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
