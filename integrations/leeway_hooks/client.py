"""Bounded loopback HTTP access to the quota service."""

from __future__ import annotations

import json
from http.client import HTTPConnection, HTTPException
from pathlib import Path
from urllib.parse import urlsplit

DEFAULT_URL = "http://127.0.0.1:8799"
TIMEOUT_SECONDS = 1
MAX_RESPONSE_BYTES = 1024 * 1024


class Advisor:
    """Read advice over HTTP without proxies, redirects or external hosts."""

    def __init__(self, url: str = DEFAULT_URL):
        """Validate a plain HTTP loopback origin; raise ValueError otherwise."""
        parts = urlsplit(url)
        if (parts.scheme != "http" or parts.hostname != "127.0.0.1" or parts.username
                or parts.password or parts.path not in {"", "/"} or parts.query or parts.fragment):
            raise ValueError("quota advisor must be an HTTP origin on 127.0.0.1")
        self._port = parts.port if parts.port is not None else 8799
        if not 1 <= self._port <= 65535:
            raise ValueError("quota advisor port must be from 1 to 65535")

    def advise(self, request: dict) -> dict:
        """POST a versioned advice request; raise ValueError for malformed advice."""
        result = self._request("POST", "/v1/advise", request)
        validate_advice(result)
        return result

    def status(self) -> dict:
        """GET the current status snapshot without triggering any local probe."""
        result = self._request("GET", "/v1/status")
        _version(result, versions=(1, 2, 3))
        if not isinstance(result.get("accounts"), list):
            raise ValueError("invalid quota accounts")
        return result

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        connection = HTTPConnection("127.0.0.1", self._port, timeout=TIMEOUT_SECONDS)
        try:
            data = json.dumps(body).encode() if body is not None else None
            connection.request(method, path, body=data, headers={"Content-Type": "application/json"})
            response = connection.getresponse()
            raw = response.read(MAX_RESPONSE_BYTES + 1)
            if response.status != 200 or len(raw) > MAX_RESPONSE_BYTES:
                raise ValueError("quota advisor returned an unsuccessful or oversized response")
            result = json.loads(raw)
            if not isinstance(result, dict):
                raise ValueError("quota advisor response must be an object")
            return result
        except HTTPException as error:
            raise OSError("quota advisor HTTP failure") from error
        finally:
            connection.close()


def _version(value: dict, versions: tuple[int, ...] = (1,)) -> None:
    if type(value.get("schema_version")) is not int or value["schema_version"] not in versions:
        raise ValueError("unsupported quota schema version")


def validate_advice(value: dict) -> None:
    """Validate v1 advice, including empty routing fields on deny and wait responses."""
    _version(value)
    if value.get("verdict") not in {"go", "switch", "wait", "deny"}:
        raise ValueError("invalid quota verdict")
    for key in ("agent", "account", "model", "effort", "config_dir", "reason"):
        if not isinstance(value.get(key), str):
            raise ValueError(f"invalid quota {key}")
    if not value["reason"] or "retry_at" not in value:
        raise ValueError("invalid quota reason or retry_at")
    if value["retry_at"] is not None and not isinstance(value["retry_at"], str):
        raise ValueError("invalid quota retry_at")
    if value["agent"] not in {"claude", "codex", ""}:
        raise ValueError("invalid quota agent")
    if value["verdict"] in {"go", "switch"}:
        if value["agent"] == "" or not value["account"] or not Path(value["config_dir"]).is_absolute():
            raise ValueError("invalid quota route")
        if value["agent"] == "claude" and not value["model"]:
            raise ValueError("invalid quota model")
