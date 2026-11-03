"""Regressions through the shipped Swift executable, using isolated homes only."""

import contextlib
import datetime
import json
import signal
import socket
import threading
import time
import urllib.request
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def real_cli():
    result = subprocess.run(["swift", "build"], cwd=ROOT, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stderr
    return ROOT / ".build/debug/leeway"


def test_finding_1_real_cli_installs_before_loading_policy(real_cli, tmp_path):
    profile = tmp_path / ".claude"
    profile.mkdir()
    policy = tmp_path / "invalid.toml"
    policy.write_text("invalid policy")
    env = {**os.environ, "HOME": str(tmp_path),
           "LEEWAY_INTEGRATIONS_EXECUTABLE": str(ROOT / "integrations/leeway-integrations")}
    args = [str(real_cli), "--home", str(tmp_path), "--policy", str(policy),
            "integrations", "install", "--profile", str(profile), "--provider", "claude"]
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert "SessionStart" in json.loads((profile / "settings.json").read_text())["hooks"]
    args[6] = "uninstall"
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert json.loads((profile / "settings.json").read_text()) == {}
    assert not (tmp_path / "Library/Application Support/leeway/history.sqlite").exists()


def test_finding_1_real_cli_preserves_installer_exit(real_cli, tmp_path):
    runtime = tmp_path / "runtime"
    runtime.write_text("#!/bin/sh\nexit 3\n")
    runtime.chmod(0o700)
    result = subprocess.run([str(real_cli), "--home", str(tmp_path), "integrations", "install"],
                            env={**os.environ, "LEEWAY_INTEGRATIONS_EXECUTABLE": str(runtime)},
                            capture_output=True, timeout=10)
    assert result.returncode == 3


def get_status(port, timeout=1):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/status", timeout=timeout) as response:
        return json.load(response)


def get_advice(port, **changes):
    query = {"repo": "/example", "role": "builder", "task_class": "integration", "agent": "codex", **changes}
    request = urllib.request.Request(f"http://127.0.0.1:{port}/v1/advise",
                                     data=json.dumps(query).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=1) as response:
        return json.load(response)


@contextlib.contextmanager
def running_server(real_cli, home, policy, env=None):
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    policy.write_text(f"port = {port}\n" + policy.read_text())
    with (home / "server.log").open("w+") as log:
        process = subprocess.Popen([str(real_cli), "--home", str(home), "--policy", str(policy), "serve"],
                                   env={**os.environ, **(env or {})}, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.DEVNULL, stderr=log)
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                log.seek(0)
                if "Leeway listening" in log.read():
                    break
                assert process.poll() is None, "server exited during startup"
                time.sleep(0.02)
            else:
                pytest.fail("server did not start")
            yield port, process
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)


def write_codex_reading(home, week=60):
    sessions = home / ".codex/sessions"
    sessions.mkdir(parents=True)
    stamp = datetime.datetime.now(datetime.timezone.utc)
    record = {"timestamp": stamp.isoformat().replace("+00:00", "Z"), "type": "event_msg",
              "payload": {"type": "token_count", "rate_limits": {
                  "primary": {"used_percent": 5, "window_minutes": 300, "resets_at": stamp.timestamp() + 3600},
                  "secondary": {"used_percent": week, "window_minutes": 10080, "resets_at": stamp.timestamp() + 86400}}}}
    older = json.loads(json.dumps(record))
    older["timestamp"] = (stamp - datetime.timedelta(hours=6)).isoformat().replace("+00:00", "Z")
    older["payload"]["rate_limits"]["secondary"]["used_percent"] = week - 1
    (sessions / "rollout-one.jsonl").write_text(json.dumps(older) + "\n" + json.dumps(record) + "\n")


def test_finding_4_running_server_reloads_valid_policy_and_retains_last_valid(real_cli, tmp_path):
    write_codex_reading(tmp_path)
    policy = tmp_path / "policy.toml"
    policy.write_text('poll_minutes = 15\n[[accounts]]\nid = "code"\nprovider = "codex"\n'
                      'config_dir = "~/.codex"\ntarget_low = 40\ntarget_high = 100\nover_target = "block"\n')
    with running_server(real_cli, tmp_path, policy) as (port, _):
        assert get_status(port)["accounts"][0]["target_high"] == 100
        assert get_advice(port)["verdict"] == "go"
        policy.write_text(policy.read_text().replace("target_high = 100", "target_high = 50"))
        assert get_status(port)["accounts"][0]["target_high"] == 50
        assert get_advice(port)["verdict"] == "deny"
        valid = policy.read_text()
        policy.write_text("invalid policy")
        assert get_status(port)["accounts"][0]["target_high"] == 50
        assert get_advice(port)["verdict"] == "deny"
        policy.write_text(valid + "enabled = false\n")
        assert get_status(port)["accounts"] == []


def test_finding_5_status_and_advice_remain_available_during_probe(real_cli, tmp_path):
    profile = tmp_path / ".claude"
    profile.mkdir()
    tools = tmp_path / "bin"
    tools.mkdir()
    started = tmp_path / "started"
    fake = tools / "claude"
    fake.write_text('#!/bin/sh\nif [ "$1" = auth ]; then printf "{}"; exit; fi\n'
                    'printf started > "$PROBE_STARTED"\nsleep 3\nprintf "{}"\n')
    fake.chmod(0o700)
    policy = tmp_path / "policy.toml"
    policy.write_text("")
    with running_server(real_cli, tmp_path, policy,
                        {"PATH": str(tools) + ":/usr/bin:/bin", "PROBE_STARTED": str(started)}) as (port, _):
        deadline = time.monotonic() + 3
        while not started.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert started.exists(), "fake probe did not run"
        assert get_status(port, timeout=0.7)["accounts"][0]["stale"]
        assert get_advice(port, agent="claude")["verdict"] == "go"


@pytest.mark.parametrize("body", [False, True])
def test_finding_9_trickled_requests_expire_and_release_all_workers(real_cli, tmp_path, body):
    policy = tmp_path / "policy.toml"
    policy.write_text("")
    with running_server(real_cli, tmp_path, policy) as (port, _):
        clients = []
        stop = threading.Event()
        try:
            for _ in range(16):
                client = socket.create_connection(("127.0.0.1", port), timeout=1)
                if body:
                    client.sendall(f"POST /v1/advise HTTP/1.1\r\nHost: localhost:{port}\r\nContent-Length: 100\r\n\r\n".encode())
                else:
                    client.sendall(b"G")
                clients.append(client)

            def trickle():
                while not stop.wait(0.15):
                    for client in clients:
                        try:
                            client.sendall(b"x")
                        except OSError:
                            pass

            thread = threading.Thread(target=trickle, daemon=True)
            thread.start()
            # Beyond the advertised two-second request bound, all slots must be free.
            time.sleep(2.4)
            assert get_status(port, timeout=0.7)["schema_version"] == 3
        finally:
            stop.set()
            for client in clients:
                client.close()
            if "thread" in locals():
                thread.join(timeout=1)


def test_finding_9_excess_connections_are_closed_without_waiting(real_cli, tmp_path):
    policy = tmp_path / "policy.toml"
    policy.write_text("")
    with running_server(real_cli, tmp_path, policy) as (port, _):
        clients = []
        try:
            for _ in range(16):
                client = socket.create_connection(("127.0.0.1", port), timeout=1)
                client.sendall(b"G")
                clients.append(client)
            with socket.create_connection(("127.0.0.1", port), timeout=0.5) as extra:
                try:
                    assert extra.recv(1) == b""
                except ConnectionResetError:
                    pass
        finally:
            for client in clients:
                client.close()


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


@pytest.mark.parametrize("termination", [signal.SIGTERM, signal.SIGINT])
def test_finding_10_server_shutdown_terminates_probe_group(real_cli, tmp_path, termination):
    (tmp_path / ".claude").mkdir()
    tools = tmp_path / "bin"
    tools.mkdir()
    pid_file = tmp_path / "probe-pids"
    fake = tools / "claude"
    fake.write_text('#!/bin/sh\nif [ "$1" = auth ]; then printf "{}"; exit; fi\n'
                    'trap "" TERM\nsleep 60 &\nprintf "%s %s" "$$" "$!" > "$PROBE_PIDS"\nwait\n')
    fake.chmod(0o700)
    policy = tmp_path / "policy.toml"
    policy.write_text("")
    pids = []
    try:
        with running_server(real_cli, tmp_path, policy,
                            {"PATH": str(tools) + ":/usr/bin:/bin", "PROBE_PIDS": str(pid_file)}) as (_, process):
            deadline = time.monotonic() + 3
            while not pid_file.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            assert pid_file.exists(), "fake probe did not run"
            pids = [int(value) for value in pid_file.read_text().split()]
            assert len(pids) == 2
            process.send_signal(termination)
            process.wait(timeout=3)
            deadline = time.monotonic() + 2
            while any(process_exists(pid) for pid in pids) and time.monotonic() < deadline:
                time.sleep(0.02)
            assert all(not process_exists(pid) for pid in pids), "probe survived server shutdown"
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_status_client_accepts_real_status_schema_3(real_cli, tmp_path):
    from leeway_hooks.client import Advisor

    policy = tmp_path / "policy.toml"
    policy.write_text("")
    with running_server(real_cli, tmp_path, policy) as (port, _):
        assert Advisor(f"http://127.0.0.1:{port}").status()["schema_version"] == 3


@pytest.mark.parametrize("used,start,remaining,status,forecast", [
    (13, 12, 6 * 86400, "on_target", 91),
    (95, 94, 31 * 3600, "over", 116),
])
def test_advice_uses_status_forecast_not_next_round(real_cli, tmp_path, used, start, remaining, status, forecast):
    sessions = tmp_path / ".codex/sessions"
    sessions.mkdir(parents=True)
    stamp = datetime.datetime.now(datetime.timezone.utc)
    resets = stamp.timestamp() + remaining
    rows = []
    for age, pct in [(6 * 3600, start), (0, used)]:
        at = stamp - datetime.timedelta(seconds=age)
        rows.append(json.dumps({"timestamp": at.isoformat(), "type": "event_msg", "payload": {
            "type": "token_count", "rate_limits": {"secondary": {
                "used_percent": pct, "window_minutes": 10080, "resets_at": resets}}}}))
    (sessions / "rollout-forecast.jsonl").write_text("\n".join(rows))
    policy = tmp_path / "policy.toml"
    policy.write_text("")
    with running_server(real_cli, tmp_path, policy) as (port, _):
        deadline = time.monotonic() + 3
        while True:
            account = get_status(port)["accounts"][0]
            if account["seven_day"]["pct"] == used:
                break
            assert time.monotonic() < deadline, account
            time.sleep(0.01)
        assert account["status"] == status
        assert round(account["forecast"]["range_high"]) == forecast
        assert account["forecast"]["next_round_pct"] == used + 1
        advice = get_advice(port)
        assert advice["verdict"] == ("wait" if status == "over" else "go")
        if status == "over":
            assert f"forecast at {forecast}%" in advice["reason"]
