"""Student agent — reveal freshness + signature verification.

Run with: pytest module-00-setup/student/agent/test_agent.py
"""
import hashlib
import hmac
import os
import sys
from pathlib import Path

import pytest

# requests is imported at agent.py module scope; skip cleanly if unavailable.
pytest.importorskip("requests")

# Fix the token BEFORE importing agent (it is read at import time).
os.environ.setdefault("DASHBOARD_API_TOKEN", "per-student-token-for-alice")
sys.path.insert(0, str(Path(__file__).resolve().parent))

import agent  # noqa: E402


def _sign(token: str, student_id: str, module: str, level: str, issued_at: int) -> str:
    msg = f"{student_id}|{module}|{level}|{issued_at}".encode()
    return hmac.new(token.encode(), msg, hashlib.sha256).hexdigest()


# --- freshness / replay ----------------------------------------------------


def test_reveal_is_fresh_accepts_recent():
    assert agent._reveal_is_fresh(1000, now=1000)
    assert agent._reveal_is_fresh(1000, now=1000 + agent.REVEAL_MAX_AGE)


def test_reveal_is_fresh_rejects_stale():
    assert not agent._reveal_is_fresh(1000, now=1000 + agent.REVEAL_MAX_AGE + 1)


def test_reveal_is_fresh_rejects_garbage():
    assert not agent._reveal_is_fresh("not-a-number")
    assert not agent._reveal_is_fresh(None)


# --- signature verification ------------------------------------------------


def test_valid_signature_accepted():
    token = agent.DASHBOARD_API_TOKEN
    body = {
        "module": "module-01-introduction",
        "level": "hints",
        "issued_at": 1234,
        "sig": _sign(token, "alice", "module-01-introduction", "hints", 1234),
    }
    assert agent._verify_reveal_signature("alice", body)


def test_forged_signature_rejected():
    body = {
        "module": "module-01-introduction",
        "level": "hints",
        "issued_at": 1234,
        "sig": _sign("wrong-key", "alice", "module-01-introduction", "hints", 1234),
    }
    assert not agent._verify_reveal_signature("alice", body)


def test_missing_fields_rejected():
    assert not agent._verify_reveal_signature("alice", {"sig": "x"})
