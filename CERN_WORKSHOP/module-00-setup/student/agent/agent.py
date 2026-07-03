import json
import logging
import os
import random
import re
import time
import socket
import ipaddress
import requests
import subprocess
import glob
import sys

# Configuration
SERVER_URL = os.getenv("DASHBOARD_URL", "http://192.168.1.100:8000/api/report")
DASHBOARD_API_TOKEN = os.getenv("DASHBOARD_API_TOKEN", "")
# Acknowledge plaintext transport explicitly. When the dashboard URL is http://
# the Bearer token is sent in clear; set DASHBOARD_INSECURE_HTTP=true to silence
# the warning, or point DASHBOARD_URL at the instructor's TLS proxy (https://).
INSECURE_HTTP_OK = os.getenv("DASHBOARD_INSECURE_HTTP", "false").lower() in ("true", "1", "yes")
INTERVAL = 30  # Seconds — happy-path interval between successful reports
BACKOFF_MAX = 300  # Cap on retry sleep when /api/report keeps failing
# Reject reveal payloads whose issued_at is older than this many seconds — a
# replay of a previously-captured reveal response is refused.
REVEAL_MAX_AGE = int(os.getenv("REVEAL_MAX_AGE", "300"))
# Optional override so the student_id is deterministic (the instructor mints a
# per-student token for exactly this id). Falls back to the sanitized FQDN.
STUDENT_ID_OVERRIDE = os.getenv("STUDENT_ID", "").strip()
# Default to three levels up from this script if not set
DEFAULT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))
WORKSHOP_ROOT = os.getenv("WORKSHOP_ROOT", DEFAULT_ROOT)
LEADERBOARD_OPT_IN = os.getenv("LEADERBOARD_OPT_IN", "false").lower() in ("true", "1", "yes")
# Where each module's validate.sh output is captured. request-help.sh reads the
# SAME path to attach the exact error the student is facing to a help request.
# Anchored on WORKSHOP_ROOT (the repo bind-mount) so it lands on the host — not
# on an image-internal path invisible to the host-side request-help.sh — and is
# identical whether the agent runs containerized or via systemd. Overridable
# with VALIDATION_OUTPUT_DIR; setup.sh points request-help.sh at the same dir.
VALIDATION_OUTPUT_DIR = os.getenv("VALIDATION_OUTPUT_DIR") or os.path.join(
    WORKSHOP_ROOT, ".capi-agent", "validation_output"
)


# --- Structured (JSON-line) logging --------------------------------
class _JsonFormatter(logging.Formatter):
    """One JSON object per log line so journalctl output is parseable."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": round(record.created, 3),
            "level": record.levelname,
            "msg": record.getMessage(),
            "logger": record.name,
        }
        for k in ("module_name", "status_code", "backoff", "module_count"):
            v = record.__dict__.get(k)
            if v is not None:
                payload[k] = v
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


_log_handler = logging.StreamHandler()
_log_handler.setFormatter(_JsonFormatter())
log = logging.getLogger("capi-agent")
log.setLevel(logging.INFO)
log.addHandler(_log_handler)
log.propagate = False

# Validation patterns (match server-side)
STUDENT_ID_RE = re.compile(r'^[a-zA-Z0-9_.@-]{1,64}$')
ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')


def strip_ansi(text):
    """Remove ANSI color codes from text."""
    return ANSI_RE.sub('', text)


def sanitize_hostname(raw_hostname):
    """Sanitize hostname to match server-side regex ^[a-zA-Z0-9_.@-]{1,64}$."""
    # Strip to allowed characters
    sanitized = re.sub(r'[^a-zA-Z0-9_.@-]', '_', raw_hostname)
    # Truncate to 64 characters
    sanitized = sanitized[:64]
    # Fall back if empty
    if not sanitized:
        sanitized = "unknown-student"
    return sanitized


def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    # Validate IP address
    try:
        ipaddress.ip_address(IP)
    except ValueError:
        IP = '127.0.0.1'
    return IP


DEFAULT_VALIDATE_TIMEOUT = 60  # seconds; overridable per-module via module.yaml timeout_seconds.

# Cache: { module_name: timeout_seconds } loaded once at startup.
_TIMEOUT_CACHE = {}


def _module_timeout(mod_path):
    """Read module.yaml's timeout_seconds (default 60). Cached for the lifetime of the process."""
    mod_name = os.path.basename(mod_path)
    if mod_name in _TIMEOUT_CACHE:
        return _TIMEOUT_CACHE[mod_name]
    timeout = DEFAULT_VALIDATE_TIMEOUT
    yaml_path = os.path.join(mod_path, "module.yaml")
    if os.path.isfile(yaml_path):
        try:
            import yaml
            with open(yaml_path) as f:
                meta = yaml.safe_load(f) or {}
            t = meta.get("timeout_seconds")
            if isinstance(t, int) and t > 0:
                timeout = t
        except Exception:
            pass
    _TIMEOUT_CACHE[mod_name] = timeout
    return timeout


def check_modules():
    results = {}
    # Find all module directories relative to WORKSHOP_ROOT
    search_path = os.path.join(WORKSHOP_ROOT, "module-*")
    modules = sorted(glob.glob(search_path))

    os.makedirs(VALIDATION_OUTPUT_DIR, exist_ok=True)

    for mod_path in modules:
        mod_name = os.path.basename(mod_path)

        # Exclude module-00-setup (setup module, not a learning module)
        if mod_name.startswith("module-00"):
            continue

        # Skip modules shipped disabled (module.yaml enabled:false → .disabled marker).
        # Disabled modules are neither validated nor reported, keeping the agent
        # denominator identical to the dashboard's discover_modules() filter.
        if os.path.isfile(os.path.join(mod_path, ".disabled")):
            continue

        validate_script = os.path.join(mod_path, "validate.sh")

        if os.path.isfile(validate_script):
            # Run the validation script
            try:
                result = subprocess.run(
                    ["/bin/bash", validate_script],
                    capture_output=True,
                    text=True,
                    timeout=_module_timeout(mod_path),
                    cwd=mod_path
                )
                rc = result.returncode
                if rc == 0:
                    results[mod_name] = "OK"
                elif rc == 100:
                    results[mod_name] = "PENDING"
                elif rc == 101:
                    results[mod_name] = "IN_PROGRESS"
                else:
                    results[mod_name] = "FAIL"

                # Save validation output (combined stdout+stderr)
                output = strip_ansi((result.stdout or "") + (result.stderr or ""))[:1000]
                try:
                    with open(os.path.join(VALIDATION_OUTPUT_DIR, f"{mod_name}.txt"), "w") as f:
                        f.write(output)
                except OSError:
                    pass
            except subprocess.TimeoutExpired:
                results[mod_name] = "ERROR"
                try:
                    with open(os.path.join(VALIDATION_OUTPUT_DIR, f"{mod_name}.txt"), "w") as f:
                        f.write(f"Validation timed out after {_module_timeout(mod_path)} seconds")
                except OSError:
                    pass
            except Exception:
                results[mod_name] = "ERROR"
        else:
            results[mod_name] = "PENDING"

    return results


def get_module_title(mod_path):
    """Read title from module.yaml if available."""
    yaml_path = os.path.join(mod_path, "module.yaml")
    if os.path.isfile(yaml_path):
        try:
            import yaml
            with open(yaml_path) as f:
                meta = yaml.safe_load(f)
            return meta.get("title", "")
        except Exception:
            pass
    return ""


def print_progress(modules_status):
    """Print a formatted progress summary to the console."""
    ok_count = sum(1 for v in modules_status.values() if v == "OK")
    total = len(modules_status)
    print(f"\nProgress: {ok_count}/{total} modules OK")
    for mod_name in sorted(modules_status.keys()):
        status = modules_status[mod_name]
        if status == "OK":
            icon = "PASS"
        elif status in ("FAIL", "ERROR"):
            icon = "FAIL"
        elif status == "IN_PROGRESS":
            icon = "WORK"
        else:
            icon = "...."
        title = get_module_title(os.path.join(WORKSHOP_ROOT, mod_name))
        suffix = f" — {title}" if title else ""
        print(f"  [{icon}] {mod_name}{suffix}")
    print()


# --- Pull-based reveal client (E.3) -------------------------------
#
# Per (student, module), poll GET /api/reveal/<student>/<module>. On a
# 200 response with a level we haven't already cached, write the
# markdown to challenges/<level>.md and append an "ACCESS GRANTED"
# banner to the module README. State is kept in
# ~/.capi-agent/reveals.json so we don't re-write on every poll.

_REVEAL_STATE_DIR = os.path.expanduser("~/.capi-agent")
_REVEAL_STATE_FILE = os.path.join(_REVEAL_STATE_DIR, "reveals.json")


def _load_reveal_state() -> dict:
    try:
        with open(_REVEAL_STATE_FILE) as f:
            return json.load(f) or {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def _save_reveal_state(state: dict) -> None:
    try:
        os.makedirs(_REVEAL_STATE_DIR, exist_ok=True)
        with open(_REVEAL_STATE_FILE, "w") as f:
            json.dump(state, f)
    except OSError as e:
        log.warning("could not persist reveal state: %s", e)


def _reveal_is_fresh(issued_at, now=None) -> bool:
    """True if the reveal was issued within REVEAL_MAX_AGE seconds.

    Rejects replays of a captured reveal response (and malformed timestamps).
    """
    now = time.time() if now is None else now
    try:
        return abs(now - int(issued_at)) <= REVEAL_MAX_AGE
    except (TypeError, ValueError):
        return False


def _verify_reveal_signature(student_id: str, body: dict) -> bool:
    """HMAC verify the response so a peer can't forge a reveal.

    The key is this agent's DASHBOARD_API_TOKEN, which is the per-student
    token HMAC(master, student_id). A reveal signed for another student
    therefore fails to verify here.
    """
    import hashlib
    import hmac
    try:
        expected = body.get("sig", "")
        msg = f"{student_id}|{body['module']}|{body['level']}|{body['issued_at']}".encode()
    except KeyError:
        return False
    actual = hmac.new(DASHBOARD_API_TOKEN.encode(), msg, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, actual)


def _apply_reveal(module_name: str, level: str, content: str) -> None:
    """Write challenges/<level>.md + append a banner to README.md.

    Mirrors the side-effects of the legacy reveal-solution.sh.
    """
    mod_dir = os.path.join(WORKSHOP_ROOT, module_name)
    challenges = os.path.join(mod_dir, "challenges")
    os.makedirs(challenges, exist_ok=True)
    target = os.path.join(challenges, f"{level}.md")
    try:
        with open(target, "w") as f:
            f.write(content)
    except OSError as e:
        log.warning("could not write %s: %s", target, e)
        return

    readme = os.path.join(mod_dir, "README.md")
    banner = (
        f"\n\n---\n\n> **ACCESS GRANTED**: `challenges/{level}.md` has been "
        f"unlocked. Open it for the worked solution.\n"
    )
    try:
        with open(readme, "a") as f:
            f.write(banner)
    except OSError as e:
        log.warning("could not append banner to %s: %s", readme, e)


def poll_reveals(hostname: str, base_url: str, headers: dict, modules_status: dict) -> None:
    """For every module currently in flight, ask the dashboard if there's
    a hints/solution grant waiting. Cached so we don't re-write on every
    cycle.
    """
    state = _load_reveal_state()
    changed = False
    # Only poll modules the student is actively working — saves N round-trips.
    for module_name, status in modules_status.items():
        if status == "OK":
            continue  # student already done; no help needed
        already = state.get(module_name)
        if already == "solution":
            continue  # already at top tier
        try:
            resp = requests.get(
                f"{base_url}/api/reveal/{hostname}/{module_name}",
                headers=headers,
                timeout=10,
            )
        except requests.exceptions.RequestException as e:
            log.warning(
                "reveal poll failed: %s",
                e,
                extra={"module_name": module_name},
            )
            continue
        if resp.status_code in (404, 423):
            continue  # no grant / still in delay window
        if resp.status_code != 200:
            log.warning("unexpected reveal status %s", resp.status_code, extra={"module_name": module_name})
            continue
        try:
            body = resp.json()
        except ValueError:
            log.warning("reveal response was not JSON", extra={"module_name": module_name})
            continue
        if not _reveal_is_fresh(body.get("issued_at")):
            log.warning("reveal too old — refusing to apply (possible replay)", extra={"module_name": module_name})
            continue
        if not _verify_reveal_signature(hostname, body):
            log.warning("reveal signature invalid — refusing to apply", extra={"module_name": module_name})
            continue
        level = body.get("level")
        if level not in ("hints", "solution"):
            continue
        if already == level:
            continue  # already wrote this exact level
        # NB: do NOT pass extra={"msg": ...} — 'msg' is a reserved LogRecord
        # attribute and collides ("Attempt to overwrite 'msg'"), which used to
        # crash the whole reveal poll before any hint was applied.
        log.info("applying reveal (level=%s)", level, extra={"module_name": module_name})
        _apply_reveal(module_name, level, body.get("content", ""))
        state[module_name] = level
        changed = True

    if changed:
        _save_reveal_state(state)


def _next_backoff(current: float) -> float:
    """Exponential backoff with jitter, capped at BACKOFF_MAX.

    First failure → ~30s (unchanged from happy-path interval), each
    subsequent failure doubles up to 300s. Jitter (0..5s) avoids
    thundering-herd resync of N student agents.
    """
    nxt = INTERVAL if current < INTERVAL else min(current * 2, BACKOFF_MAX)
    return nxt + random.uniform(0, 5)


def main():
    if not DASHBOARD_API_TOKEN:
        log.warning("DASHBOARD_API_TOKEN not set — reports will fail authentication")

    if SERVER_URL.startswith("http://") and not INSECURE_HTTP_OK:
        log.warning(
            "DASHBOARD_URL uses plaintext http:// — the Bearer token is sent in "
            "the clear and can be sniffed on the lab network. Point DASHBOARD_URL "
            "at the instructor's TLS proxy (https://) or set "
            "DASHBOARD_INSECURE_HTTP=true to acknowledge this."
        )

    hostname = STUDENT_ID_OVERRIDE or sanitize_hostname(socket.getfqdn())
    ip_addr = get_ip()
    log.info("Agent starting (id=%s, ip=%s, server=%s)", hostname, ip_addr, SERVER_URL)

    headers = {"Authorization": f"Bearer {DASHBOARD_API_TOKEN}"}

    # Derive base URL from SERVER_URL (strip /api/report)
    base_url = SERVER_URL
    if base_url.endswith("/api/report"):
        base_url = base_url[: -len("/api/report")]

    leaderboard_opt_in_sent = False
    sleep_for = INTERVAL  # happy-path interval, grows on failure

    while True:
        success = False
        try:
            modules_status = check_modules()
            payload = {
                "student_id": hostname,
                "ip_address": ip_addr,
                "modules": modules_status,
            }

            resp = requests.post(SERVER_URL, json=payload, headers=headers, timeout=10)
            log.info(
                "report sent",
                extra={"status_code": resp.status_code, "module_count": len(modules_status)},
            )
            print_progress(modules_status)
            success = resp.status_code == 200

            # Pull any pending reveals (E.3). Best-effort; failures here
            # don't affect the success state of the report itself.
            if success:
                try:
                    poll_reveals(hostname, base_url, headers, modules_status)
                except Exception:
                    log.exception("reveal polling crashed")

            # Send leaderboard opt-in once after first successful report
            if success and not leaderboard_opt_in_sent:
                try:
                    opt_resp = requests.post(
                        f"{base_url}/api/leaderboard/opt-in",
                        json={"student_id": hostname, "opt_in": LEADERBOARD_OPT_IN},
                        headers=headers,
                        timeout=10,
                    )
                    log.info(
                        "leaderboard opt-in sent (opt_in=%s)",
                        LEADERBOARD_OPT_IN,
                        extra={"status_code": opt_resp.status_code},
                    )
                    leaderboard_opt_in_sent = True
                except requests.exceptions.RequestException as e:
                    log.warning("leaderboard opt-in failed (non-fatal): %s", e)

        except requests.exceptions.RequestException as e:
            log.warning("report failed: %s", e, extra={"backoff": round(sleep_for, 1)})
        except Exception:
            log.exception("unexpected error in report loop")

        if success:
            sleep_for = INTERVAL
        else:
            sleep_for = _next_backoff(sleep_for)

        time.sleep(sleep_for)


if __name__ == "__main__":
    main()
