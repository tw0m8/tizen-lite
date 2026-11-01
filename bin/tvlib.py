"""tvlib — compact access to the Samsung TV (`tv` CLI backend).

Every function returns a small dict on purpose: this exists to keep output —
and therefore context — tiny. More evidence only when a caller raises `chars`.

TV work goes through the ~1 s polling agent (`tv-agent`); `root()` is the slow
(~15-20 s) fallback for when the agent is down.
"""
from __future__ import annotations

import base64
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
from pathlib import Path

AGENT = "/usr/local/bin/tv-agent"
ROOT = "/usr/local/bin/tv-root"
APPLY = "/usr/local/bin/tv-root-apply"
FWCHECK = "/usr/local/bin/tv-fw-check"
STATUS_JSON = Path("/run/tv-root/status.json")

def _settings(path: str | None = None) -> dict:
    """Read the same KEY=VALUE file the watchdog sources.

    Precedence everywhere below: environment > /etc/default/tv-root > placeholder.
    A hardcoded address here would silently point the whole CLI at the wrong TV.
    """
    cfg: dict[str, str] = {}
    env_file = path or os.environ.get("TV_ROOT_SETTINGS") or "/etc/default/tv-root"
    try:
        with open(env_file, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                cfg[key.strip()] = val.strip().strip('"').strip("'")
    except OSError:
        pass
    return cfg


_CFG = _settings()
TV_IP = os.environ.get("TV_HOST") or _CFG.get("TV_HOST") or "192.0.2.10"
TV_MAC = os.environ.get("TV_MAC") or _CFG.get("TV_MAC") or "aa:bb:cc:dd:ee:ff"
# DNS rewrite backend (optional feature): point these at your own resolver.
AGH_YAML = Path(
    os.environ.get("TV_AGH_YAML")
    or _CFG.get("TV_AGH_YAML")
    or "/etc/adguardhome/AdGuardHome.yaml"
)
AGH_CONTAINER = os.environ.get("TV_AGH_CONTAINER") or _CFG.get("TV_AGH_CONTAINER") or "adguardhome"

DBS = {
    "pkgmgr": "/opt/dbspace/.pkgmgr_parser.db",
    "appsvc": "/opt/dbspace/user/5001/.appsvc.db",
}

LOGS = {
    "install": "/var/log/appfw/app-installers/installation-history.log",
    "install-log": "/var/log/appfw/app-installers/app-installers.log",
    "install-fail": "/var/log/appfw/app-installers/tpkbackend-failed.log",
    "fota": "/var/log/appfw/app-installers/fota.log",
    "alarm": "/var/log/appfw/alarmmgr_log/alarmmgr.log",
    "migration": "/var/log/appfw/app-installers/package_migration.log",
}

MAX_CHARS = 1500

# The agent loop is single-threaded: one blocking command stalls every later
# call. Refuse these instead of wedging the TV.
_BLOCKING = [
    (re.compile(r"^\s*dlogutil\s*$"), "bare dlogutil streams forever; use 'tv log dlog N'"),
    (re.compile(r"\btail\s+-[a-zA-Z]*f\b"), "tail -f never returns; use 'tv log file <alias> N'"),
    (re.compile(r"\bjournalctl\s+-[a-zA-Z]*f\b"), "journalctl -f never returns"),
    (re.compile(r"\b(logcat|watch)\b"), "streaming command; not allowed through the agent"),
]


def _clip(text: str, limit: int = MAX_CHARS) -> str:
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    return text[:limit] + "\n[... %d more chars]" % (len(text) - limit)


def _run(argv: list[str], timeout: int) -> tuple[int, str]:
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return 124, "[timeout after %ss]" % timeout
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def _unsafe(cmd: str) -> str | None:
    for rx, why in _BLOCKING:
        if rx.search(cmd):
            return why
    return None


# --------------------------------------------------------------------------
# TV-side verbs (polling agent)
# --------------------------------------------------------------------------

def run(cmd: str, timeout_s: int = 45, chars: int = MAX_CHARS, force: bool = False) -> dict:
    """Run a shell command on the TV as root (~1 s)."""
    if not force:
        why = _unsafe(cmd)
        if why:
            return {"rc": 2, "error": why, "cmd": cmd}
    rc, out = _run([AGENT, "-t", str(timeout_s), cmd], timeout_s + 15)
    return {"rc": rc, "out": _clip(out, chars)}


def root(cmd: str, timeout_s: int = 120, chars: int = MAX_CHARS) -> dict:
    """Fallback: one volatile root acquisition per call (~15-20 s)."""
    rc, out = _run([ROOT, cmd], timeout_s)
    if "stdout:" in out:
        out = out.split("stdout:", 1)[1]
    return {"rc": rc, "out": _clip(out, chars)}


def agent_state() -> dict:
    rc, out = _run([AGENT, "--status"], 20)
    try:
        return json.loads(out)
    except Exception:
        return {"alive": None, "raw": _clip(out, 200)}


def sql(db: str, query: str, limit: int = 40) -> dict:
    """Run SQL against the TV databases (base64-staged, so quoting never bites).

    `db` is either a known alias (pkgmgr, appsvc) or an absolute path ending in
    .db. It reaches a shell on the TV as root, so anything else is refused
    instead of being interpolated into the command line.
    """
    path = DBS.get(db)
    if path is None:
        if not re.fullmatch(r"/[A-Za-z0-9_./-]{1,120}\.db", db or ""):
            return {"rc": 2, "rows": [], "error": "db must be one of: %s - or an absolute path ending in .db"
                    % ", ".join(sorted(DBS))}
        path = db
    payload = base64.b64encode(query.encode()).decode()
    cmd = (
        "echo %s | base64 -d > /tmp/.tvsql.$$; "
        "sqlite3 -separator '|' %s < /tmp/.tvsql.$$ 2>&1 | head -%d"
        % (payload, shlex.quote(path), int(limit))
    )
    rc, out = _run([AGENT, "-t", "30", cmd], 60)
    return {"rc": rc, "rows": _clip(out, 3000).splitlines()}


def status() -> dict:
    """Power, root state, memory, running apps, home app, agent health."""
    facts = run(
        "echo UP=$(cut -d. -f1 /proc/uptime); "
        "echo MEM=$(free -m | awk 'NR==2{print $7}'); "
        "echo APPS=$(app_launcher -S 2>/dev/null | sed 's/^[[:space:]]*//' "
        "| awk '/\\(/ && !/^app/ {n++} END {print n+0}'); "
        "echo HOME=$(sqlite3 /opt/dbspace/user/5001/.appsvc.db "
        "\"SELECT pkg_name FROM appsvc WHERE operation='http://tizen.org/appcontrol/operation/main'\")",
        timeout_s=25,
    )
    parsed = {}
    for line in facts.get("out", "").splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            parsed[k.strip()] = v.strip()
    wd = {}
    try:
        wd = json.loads(STATUS_JSON.read_text())
    except Exception:
        pass
    return {
        "power": wd.get("power"),
        "root_ok": wd.get("root_verified"),
        "agent_alive": agent_state().get("alive"),
        "uptime_s": parsed.get("UP"),
        "mem_avail_mb": parsed.get("MEM"),
        "running_apps": parsed.get("APPS"),
        "home_app": parsed.get("HOME"),
    }


def apps(filt: str = "") -> dict:
    """Running apps (id + pid), optional substring filter."""
    rc, out = _run([AGENT, "-t", "20", "app_launcher -S 2>/dev/null"], 40)
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if "(" not in line or line.startswith("app"):
            continue
        ident, _, pid = line.rpartition("(")
        ident = ident.strip()
        if filt and filt.lower() not in ident.lower():
            continue
        rows.append({"app": ident, "pid": pid.rstrip(")")})
    return {"count": len(rows), "apps": rows[:40]}


def app_control(action: str, app_id: str) -> dict:
    """launch or kill an app by id."""
    flag = {"launch": "-s", "kill": "-k"}.get(action)
    if not flag:
        return {"error": "action must be launch or kill"}
    pre = "-u 5001 " if action == "launch" else ""
    return run("app_launcher %s%s %s" % (pre, flag, shlex.quote(app_id)), timeout_s=25)


def apply_state(groups: str = "", dry_run: bool = False) -> dict:
    """Re-apply managed TV state (home/memory/privacy/ota/voice)."""
    argv = [APPLY]
    if groups:
        argv += ["--only", groups]
    if dry_run:
        argv.append("--dry-run")
    rc, out = _run(argv, 360)
    if "stdout:" in out:
        out = out.split("stdout:", 1)[1]
    items = [l.strip() for l in out.splitlines() if l.strip() and "|" in l]
    return {"rc": rc, "items": items[-25:]}


def agent_action(action: str) -> dict:
    """status | start | reset for the polling loop on the TV."""
    if action == "status":
        return agent_state()
    if action == "start":
        rc, out = _run(["/usr/local/bin/tv-agent-start"], 300)
        return {"rc": rc, "out": _clip(out, 300)}
    if action == "reset":
        rc, out = _run([AGENT, "--reset"], 30)
        return {"rc": rc, "out": _clip(out, 200)}
    return {"error": "action must be status, start or reset"}


# --------------------------------------------------------------------------
# Logging — journald inactive, dlog reads empty on this build; files are real
# --------------------------------------------------------------------------

def log_file(alias: str, lines: int = 40) -> dict:
    path = LOGS.get(alias, alias)
    rc, out = _run([AGENT, "-t", "25", "tail -n %d %s 2>&1" % (int(lines), shlex.quote(path))], 45)
    return {"path": path, "rc": rc, "lines": _clip(out, 3000).splitlines()}


def log_dlog(lines: int = 40, tag: str = "") -> dict:
    """Tizen dlog via bounded `dlogutil -t N`. Empty ring on this build."""
    cmd = "dlogutil -t %d 2>&1" % int(lines)
    if tag:
        cmd += " | grep -i %s" % shlex.quote(tag)
    rc, out = _run([AGENT, "-t", "25", cmd], 45)
    kept = [
        l for l in out.splitlines()
        if l.strip() and not re.match(r"^(Start|Version|Build|Dlog|Command|argc|Exit|/dev/log)", l)
    ]
    return {
        "source": "dlog",
        "count": len(kept),
        "lines": kept[-40:],
        "note": "ring is empty here (plog=0, enable_apps=0); expect nothing unless logging is enabled",
    }


def log_aliases() -> dict:
    return {"aliases": sorted(LOGS)}


# --------------------------------------------------------------------------
# Boot / startup surface
# --------------------------------------------------------------------------

def boot_list() -> dict:
    """Enabled units, onboot app count, startup pref, home app.

    systemctl is slow here (~10 s per query), so the unit list is fetched once.
    """
    cmd = (
        "U=$(systemctl list-unit-files --state=enabled --no-pager 2>/dev/null); "
        "echo ENABLED_COUNT=$(echo \"$U\" | grep -c service); "
        "echo ENABLED=$(echo \"$U\" | awk '{print $1}' | tr '\\n' ' '); "
        "echo ONBOOT_COUNT=$(sqlite3 /opt/dbspace/.pkgmgr_parser.db \"SELECT count(*) FROM package_app_info WHERE app_onboot='true'\"); "
        "echo STARTUP=$(vconftool get db/appfw/startup_appid 2>/dev/null | head -1); "
        "echo HOME=$(sqlite3 /opt/dbspace/user/5001/.appsvc.db "
        "\"SELECT pkg_name FROM appsvc WHERE operation='http://tizen.org/appcontrol/operation/main'\")"
    )
    rc, out = _run([AGENT, "-t", "90", cmd], 120)
    parsed = {}
    for line in out.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            parsed[k.strip()] = v.strip()
    return {
        "enabled_units": parsed.get("ENABLED_COUNT"),
        "units": (parsed.get("ENABLED") or "")[:600],
        "onboot_apps": parsed.get("ONBOOT_COUNT"),
        "startup_app": parsed.get("STARTUP"),
        "home_app": parsed.get("HOME"),
    }


def set_startup(app_id: str) -> dict:
    cmd = ("vconftool set -f -t string db/appfw/startup_appid %s 2>&1; "
           "vconftool get db/appfw/startup_appid 2>&1 | head -1" % shlex.quote(app_id))
    return run(cmd, timeout_s=25)


def set_onboot(app_id: str, on: bool) -> dict:
    val = "true" if on else "false"
    safe_id = app_id.replace("'", "''")
    q = ("UPDATE package_app_info SET app_onboot='%s' WHERE app_id='%s'; "
         "SELECT app_id || '|' || app_onboot FROM package_app_info WHERE app_id='%s';" % (val, safe_id, safe_id))
    return sql("pkgmgr", q, 5)


# --------------------------------------------------------------------------
# Services, vconf
# --------------------------------------------------------------------------

def svc(action: str, unit: str) -> dict:
    u = shlex.quote(unit)
    if action == "status":
        cmd = ("systemctl is-active %s 2>&1; systemctl status %s --no-pager 2>&1 | head -4 | cut -c1-120"
               % (u, u))
    elif action in ("start", "stop", "restart"):
        cmd = "systemctl %s %s 2>&1; sleep 1; systemctl is-active %s 2>&1" % (action, u, u)
    elif action == "mask":
        # mask alone leaves a running unit alive; stop it too
        # Some Samsung units ignore SIGTERM and sit in "deactivating" forever,
        # so escalate to SIGKILL instead of reporting a half-stopped service.
        cmd = ("systemctl mask --runtime %s >/dev/null 2>&1; systemctl stop %s >/dev/null 2>&1; "
               "sleep 2; st=$(systemctl is-active %s 2>&1); "
               "case \"$st\" in deactivating|active) systemctl kill -s KILL %s >/dev/null 2>&1; "
               "sleep 1; st=$(systemctl is-active %s 2>&1);; esac; echo $st"
               % (u, u, u, u, u))
    elif action == "unmask":
        cmd = "systemctl unmask --runtime %s 2>&1" % u
    else:
        return {"error": "action must be status|start|stop|restart|mask|unmask"}
    return run(cmd, timeout_s=30)


def vconf_get(key: str) -> dict:
    return run("vconftool get %s 2>&1 | head -2" % shlex.quote(key), timeout_s=20)


def vconf_set(key: str, value: str, vtype: str = "string") -> dict:
    cmd = ("vconftool set -f -t %s %s %s 2>&1; vconftool get %s 2>&1 | head -1"
           % (shlex.quote(vtype), shlex.quote(key), shlex.quote(value), shlex.quote(key)))
    return run(cmd, timeout_s=25)


# --------------------------------------------------------------------------
# Host-side verbs — this machine, not the TV
# --------------------------------------------------------------------------

def tv_power() -> dict:
    rc, out = _run(["curl", "-s", "-m", "4", "http://%s:8001/api/v2/" % TV_IP], 20)
    try:
        dev = json.loads(out).get("device", {})
        return {"power": dev.get("PowerState"), "model": dev.get("modelName"),
                "developer_ip": dev.get("developerIP")}
    except Exception:
        return {"power": "unreachable", "note": "off, standby, or screen off (8001 only answers lit)"}


def tv_wake(mac: str = TV_MAC, wait_s: int = 60) -> dict:
    import time
    if tv_power().get("power") == "on":
        return {"woke": False, "reason": "already on"}
    if mac.strip().lower() in ("", "aa:bb:cc:dd:ee:ff"):
        return {"woke": False, "error": "no MAC configured", "hint": "set TV_MAC in /etc/default/tv-root"}
    try:
        parts = [int(x, 16) for x in mac.split(":")]
        if len(parts) != 6:
            raise ValueError
    except ValueError:
        return {"woke": False, "error": "malformed MAC: %s" % mac}
    packet = bytes([255] * 6 + parts * 16)
    for port in (9, 7):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.sendto(packet, ("255.255.255.255", port))
            s.close()
        except Exception:
            pass
    deadline = time.time() + wait_s
    while time.time() < deadline:
        time.sleep(5)
        if tv_power().get("power") == "on":
            return {"woke": True, "mac": mac}
    return {"woke": False, "reason": "no answer within %ss" % wait_s}


def sdb(action: str, arg: str = "") -> dict:
    SDB = shutil.which("sdb") or "/usr/local/bin/sdb"
    if not Path(SDB).exists():
        return {"error": "sdb not found", "hint": "install the Tizen SDK or put sdb on PATH", "action": action}
    if action == "devices":
        rc, out = _run([SDB, "devices"], 30)
    elif action == "connect":
        target = arg or "%s:26101" % TV_IP
        _run([SDB, "kill-server"], 20)
        _run([SDB, "start-server"], 20)
        rc, out = _run([SDB, "connect", target], 40)
    elif action == "capability":
        rc, out = _run([SDB, "-s", "%s:26101" % TV_IP, "capability"], 30)
    else:
        return {"error": "action must be devices|connect|capability"}
    return {"rc": rc, "out": _clip(out, 800)}


def dns(action: str, name: str = "", answer: str = "") -> dict:
    """AdGuard rewrites. The container saves its config on shutdown, so edit while stopped."""
    try:
        text = AGH_YAML.read_text()
    except OSError:
        return {"error": "no DNS resolver config at %s" % AGH_YAML,
                "hint": "this verb is optional; set TV_AGH_YAML in /etc/default/tv-root or skip it",
                "action": action}
    current = re.findall(r"- domain: (\S+)\n\s+answer: (\S+)", text)
    if action == "list":
        return {"rewrites": [{"domain": d, "answer": a} for d, a in current]}
    if action == "add":
        if not name or not answer:
            return {"error": "add needs <name> <answer>"}
        if any(d == name for d, _ in current):
            return {"error": "rewrite already exists", "domain": name}
        entry = "    - domain: %s\n      answer: %s\n      enabled: true\n" % (name, answer)
        text = text.replace("  rewrites:\n", "  rewrites:\n" + entry, 1)
    elif action == "remove":
        new = re.sub(r"\s+- domain: %s\n\s+answer: \S+\n\s+enabled: true" % re.escape(name), "", text, count=1)
        if new == text:
            return {"error": "no such rewrite", "domain": name}
        text = new
    else:
        return {"error": "action must be list|add|remove"}
    try:
        _run(["docker", "stop", AGH_CONTAINER], 60)
        AGH_YAML.write_text(text)
    except OSError as exc:
        return {"error": "could not write %s: %s" % (AGH_YAML, exc)}
    finally:
        _run(["docker", "start", AGH_CONTAINER], 60)
    return {"ok": True, "action": action, "domain": name, "answer": answer}


def firmware() -> dict:
    if not Path(FWCHECK).exists():
        return {"error": "tv-fw-check not installed",
                "hint": "firmware checking is optional and host-specific; compare the vendor page yourself "
                        "(docs/rooting.md describes the method)"}
    rc, out = _run([FWCHECK], 180)
    return {"rc": rc, "out": _clip(out, 500)}
