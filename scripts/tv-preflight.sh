#!/usr/bin/env bash
# tv-preflight — diagnose the sdb connection chain to a Samsung TV.
#
# Read-only: queries the TV's REST API on :8001 and asks sdb to attach. Does not
# install, uninstall, change TV settings or acquire root. Run this BEFORE any
# audit or install so a failure surfaces as the actual cause, not a bare
# "sdb connect failed".
#
# usage: tv-preflight.sh <tv-ip> [sdb-path]
set -uo pipefail

TV="${1:?usage: tv-preflight.sh <tv-ip> [sdb-path]}"
SDB="${2:-$(command -v sdb 2>/dev/null || echo /usr/local/bin/sdb)}"
API="/tmp/tv-preflight-${TV}.json"
rc=0

say()  { printf '%-6s %s\n' "$1" "$2"; }
fail() { say "FAIL" "$2"; rc=1; }

# 1. reachable
if ping -c1 -W2 "$TV" >/dev/null 2>&1; then
  say OK "ping $TV"
else
  fail x "ping $TV — TV off, in standby, or a different IP; not proceeding"
  exit 1
fi

# 2. REST API facts (developerMode / developerIP / PowerState / modelName)
if curl -fsS -m 4 "http://${TV}:8001/api/v2/" -o "$API"; then
  say OK "REST API :8001"
else
  fail x "REST API :8001 unreachable — dev mode off, or the TV blocks the request"
  exit 1
fi
for field in modelName PowerState developerMode developerIP; do
  printf '       %-14s %s\n' "$field" "$(grep -o "\"$field\":\"[^\"]*\"" "$API" | cut -d'"' -f4)"
done

DMODE="$(grep -o '"developerMode":"[^"]*"' "$API" | cut -d'"' -f4)"
DIP="$(grep -o '"developerIP":"[^"]*"' "$API" | cut -d'"' -f4)"
[ "$DMODE" = "1" ] || fail x "developerMode is not 1 — enable it: Apps > App Settings > 12345 > Developer mode"

# 3. the registered host IP must be THIS host's source IP for the TV
MINE="$(ip -4 route get "$TV" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
printf '       %-14s %s\n' "route src" "${MINE:-unknown}"
if [ -n "$MINE" ] && [ "$DIP" != "$MINE" ]; then
  fail x "developerIP '$DIP' is not this host ('$MINE'). If '$DIP' is another machine: change it on the TV (Apps > App Settings > 12345 > Developer mode) and power-cycle. If it is this host but the route is wrong: ip route replace $TV/32 dev <iface> src $DIP"
else
  say OK "developerIP matches the route source"
fi

# 4. sdb attach
if [ -x "$SDB" ]; then
  "$SDB" kill-server >/dev/null 2>&1
  "$SDB" start-server >/dev/null 2>&1
  "$SDB" connect "${TV}:26101" >/dev/null 2>&1
  if "$SDB" devices 2>/dev/null | grep -q "${TV}:26101"; then
    say OK "sdb attached to ${TV}:26101"
  else
    fail x "sdb cannot attach — port 26101 closed (power-cycle the TV) or the host IP is not the whitelisted one"
  fi
else
  fail x "no sdb at '$SDB' — install the standalone sdb package (see references/sdb-audit.md)"
fi

exit "$rc"
