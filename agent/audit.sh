#!/usr/bin/env bash
# agent/audit.sh — read-only discovery for an AI agent.
#
# Prints one JSON object describing: host settings, TV reachability, root state,
# which masked units are actually inactive, which app processes are still alive, memory,
# launcher timing and whether the manifest's invariants currently hold.
#
# Never changes anything. Safe to run at any time, including with the TV off.
set -uo pipefail

SETTINGS="${TV_ROOT_SETTINGS:-/etc/default/tv-root}"
PERF="${TV_PERF_UNITS:-/etc/tv-root-perf-units}"
KILL="${TV_KILL_PROCS:-/etc/tv-root-kill-procs}"
TV_BIN="${TV_BIN:-/usr/local/bin/tv}"

TV_HOST=""
APPLY_GROUPS=""
AGENT=""
# shellcheck source=/dev/null
if [ -r "$SETTINGS" ]; then . "$SETTINGS" 2>/dev/null || true; fi

AU_UNITS=$(grep -v '^[[:space:]]*#' "$PERF" 2>/dev/null | tr '\n' ' ')
AU_PROCS=$(grep -v '^[[:space:]]*#' "$KILL" 2>/dev/null | tr '\n' ' ')

AU_API=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://${TV_HOST}:8001/api/v2/" 2>/dev/null)
[ -z "$AU_API" ] && AU_API="000"
AU_REACH="no"
[ "$AU_API" = "200" ] && AU_REACH="yes"

AU_STATUS=""
AU_UNITS_RAW=""
AU_PROCS_RAW=""
AU_MEM_RAW=""
AU_LAUNCHER="0"

if [ "$AU_REACH" = "yes" ] && [ -x "$TV_BIN" ]; then
  AU_STATUS=$("$TV_BIN" status 2>/dev/null | head -c 2000)
  [ -n "$AU_UNITS" ] && AU_UNITS_RAW=$("$TV_BIN" run "for u in $AU_UNITS; do printf '%s=%s\n' \"\$u\" \"\$(systemctl is-active \"\$u\" 2>/dev/null)\"; done" 2>/dev/null)
  [ -n "$AU_PROCS" ] && AU_PROCS_RAW=$("$TV_BIN" run "for p in $AU_PROCS; do printf '%s=%s\n' \"\$p\" \"\$(pgrep -f \"\$p\" 2>/dev/null | wc -l)\"; done" 2>/dev/null)
  AU_MEM_RAW=$("$TV_BIN" run 'printf "%s %s %s" "$(awk "/^MemAvailable/{print \$2}" /proc/meminfo)" "$(awk "/^SwapFree/{print \$2}" /proc/meminfo)" "$(awk "/^CmaFree/{print \$2}" /proc/meminfo)"' 2>/dev/null)
  AU_LAUNCHER=$("$TV_BIN" run 'p=$(pgrep -f FreeMyTVio | head -1); [ -n "$p" ] && awk "{printf \"%d\", \$22/100}" /proc/$p/stat 2>/dev/null || echo 0' 2>/dev/null | tr -dc '0-9')
  # which app directories still exist on the TV - an already-removed app leaves no process,
  # so without this an agent cannot tell "never there" from "already gone"
  AU_DIRS_RAW=$("$TV_BIN" run 'ls -1 /opt/usr/apps 2>/dev/null | head -100' 2>/dev/null)
  # confirm the load-bearing units exist on THIS firmware, not just that they are masked
  AU_INV_RAW=$("$TV_BIN" run 'for u in aaa_tvs_deamon dta-agent sdbd com.samsung.tv.csfs com.samsung.tv.home.sidebar com.samsung.tv.contentservicemanager; do printf "%s=%s/%s\n" "$u" "$(systemctl is-active "$u" 2>/dev/null)" "$(systemctl is-enabled "$u" 2>/dev/null)"; done' 2>/dev/null)
  [ -z "$AU_LAUNCHER" ] && AU_LAUNCHER="0"
fi

export AU_SETTINGS="$SETTINGS" AU_HOST="$TV_HOST" AU_GROUPS="$APPLY_GROUPS" AU_AGENT="$AGENT"
AU_UNITS_COUNT="$(printf '%s' "$AU_UNITS" | wc -w)"
AU_PROCS_COUNT="$(printf '%s' "$AU_PROCS" | wc -w)"
export AU_UNITS_COUNT AU_PROCS_COUNT
export AU_REACH AU_API AU_STATUS AU_UNITS_RAW AU_PROCS_RAW AU_MEM_RAW AU_LAUNCHER AU_DIRS_RAW AU_INV_RAW

python3 - <<'PY'
import json, os, re

def unwrap(raw):
    """tv run returns {"rc":0,"out":"..."}; older builds returned plain text."""
    s = (raw or "").strip()
    if s.startswith('{"rc"') or s.startswith('{ "rc"'):
        try:
            return json.loads(s).get("out", "") or ""
        except Exception:
            return s
    return s


def kv_lines(raw):
    raw = unwrap(raw)
    out = {}
    for ln in (raw or "").splitlines():
        ln = ln.strip()
        if "=" not in ln:
            continue
        k, v = ln.rsplit("=", 1)
        out[k.strip()] = v.strip()
    return out

status = None
raw_status = unwrap(os.environ.get("AU_STATUS"))
if raw_status.startswith("{"):
    try:
        status = json.loads(raw_status)
    except Exception:
        status = {"unparsed": raw_status}

units = kv_lines(os.environ.get("AU_UNITS_RAW"))
procs = {}
for k, v in kv_lines(os.environ.get("AU_PROCS_RAW")).items():
    procs[k] = int(v) if v.isdigit() else v

mem = {}
parts = unwrap(os.environ.get("AU_MEM_RAW")).split()
if len(parts) >= 3 and all(p.isdigit() for p in parts[:3]):
    mem = {"mem_available_kb": int(parts[0]), "swap_free_kb": int(parts[1]), "cma_free_kb": int(parts[2])}

app_dirs = [ln.strip() for ln in unwrap(os.environ.get("AU_DIRS_RAW", "")).splitlines() if ln.strip()]
inv = {}
for k, v in kv_lines(os.environ.get("AU_INV_RAW")).items():
    active, _, enabled = v.partition("/")
    inv[k] = {"active": active, "enabled": enabled}

doc = {
    "schema": "tizen-lite/audit/1",
    "host": {
        "settings_file": os.environ.get("AU_SETTINGS"),
        "tv_host": os.environ.get("AU_HOST"),
        "apply_groups": os.environ.get("AU_GROUPS"),
        "agent_enabled": os.environ.get("AU_AGENT"),
        "masked_unit_count": int(os.environ.get("AU_UNITS_COUNT") or 0),
        "kill_pattern_count": int(os.environ.get("AU_PROCS_COUNT") or 0),
    },
    "tv": {
        "reachable": os.environ.get("AU_REACH") == "yes",
        "api_http_code": os.environ.get("AU_API"),
        "status": status,
        "launcher_start_offset_s": int(os.environ.get("AU_LAUNCHER") or 0),
    },
    "state": {
        "units": units,
        "app_processes": procs,
        "app_dirs": app_dirs,
        "memory": mem,
    },
    "invariants": {
        "units": inv,
        "note": ("`units` lists the load-bearing components and whether each exists on this firmware: "
                 "active/unknown means the unit name does not exist here. `state.app_dirs` is the full "
                 "list under /opt/usr/apps - an id missing from it is either never-installed or already "
                 "removed; check the backup root before assuming which."),
    },
}
print(json.dumps(doc, indent=2))
PY
