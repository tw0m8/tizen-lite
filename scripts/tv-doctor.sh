#!/usr/bin/env bash
# tizen-lite doctor — check every prerequisite and tell a human what to fix next.
#
#   ./scripts/tv-doctor.sh            fast checks (a few seconds)
#   ./scripts/tv-doctor.sh --deep     also performs one real root acquisition (~20 s)
#
# Exit codes: 0 all good, 1 something needs fixing, 2 usage.
set -uo pipefail

SETTINGS="${TV_ROOT_SETTINGS:-/etc/default/tv-root}"
DEEP=0
[ "${1:-}" = "--deep" ] && DEEP=1

if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; D=""; B=""; N=""
fi

pass=0; fail=0; warn=0
next_steps=()

ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; pass=$((pass+1)); }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && next_steps+=("$2"); }
note() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; warn=$((warn+1)); }
info() { printf '  %s· %s%s\n' "$D" "$1" "$N"; }

echo
printf '%sTizen Lite doctor%s\n' "$B" "$N"
printf '%sChecks the TV, this computer, and the root tool. Changes nothing.%s\n\n' "$D" "$N"

# ---------------------------------------------------------------- 1. settings
echo "${B}1. Configuration${N}"
TV_HOST=""
if [ -r "$SETTINGS" ]; then
  # shellcheck disable=SC1090
  . "$SETTINGS" 2>/dev/null
  ok "settings file: $SETTINGS"
else
  bad "no settings file at $SETTINGS" "run ./install.sh, then set TV_HOST in $SETTINGS"
fi

if [ -z "${TV_HOST:-}" ]; then
  bad "TV_HOST is empty" "edit $SETTINGS and set TV_HOST=<your TV's IP>"
elif printf '%s' "$TV_HOST" | grep -qE '^(192\.0\.2\.|CHANGE|your)'; then
  bad "TV_HOST is still the placeholder ($TV_HOST)" "put your TV's real LAN IP in $SETTINGS"
else
  ok "TV_HOST = $TV_HOST"
fi

HOST_IP=$(ip route get "${TV_HOST:-1.1.1.1}" 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
if [ -n "$HOST_IP" ]; then
  ok "this computer is $HOST_IP — that is the address to whitelist on the TV"
else
  note "could not work out this computer's LAN IP (no default route?)"
fi

# ------------------------------------------------------------------- 2. tools
echo
echo "${B}2. Tools on this computer${N}"
if python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,7) else 1)' 2>/dev/null; then
  ok "python3 $(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])') (3.7+ required)"
else
  bad "python3 is too old" "the shipped tools need python3 >= 3.7"
fi

if command -v sdb >/dev/null 2>&1; then
  ok "sdb found ($(command -v sdb))"
elif [ -x /usr/local/bin/sdb ]; then
  ok "sdb found (/usr/local/bin/sdb)"
else
  bad "sdb is not installed" "install the Tizen SDK, or copy sdb onto PATH"
fi

if [ -x /usr/local/bin/tv-root ]; then
  ok "tv-root wrapper present"
else
  bad "tv-root wrapper missing" "install the root harness (see docs/rooting.md), then copy bin/tv-root* into /usr/local/bin"
fi

if [ -x /usr/local/bin/samsung-tv-root ]; then
  ok "root exploit present (/usr/local/bin/samsung-tv-root)"
else
  note "samsung-tv-root not found — root acquisition will fail until it is installed"
  next_steps+=("build/install chris-ritsen/samsung-tv-root (docs/rooting.md explains the chain)")
fi

# ------------------------------------------------------------- 3. reachability
echo
echo "${B}3. The TV${N}"
API=""
if [ -n "${TV_HOST:-}" ]; then
  API=$(curl -s -m 3 "http://$TV_HOST:8001/api/v2/" 2>/dev/null)
fi

if [ -z "$API" ]; then
  bad "no answer on http://$TV_HOST:8001/api/v2/" \
      "Turn the TV on, check it is on the same network, then retry. If it only answers in standby, wake it first."
else
  ok "TV REST API answers"
  # Read the device fields into variables without `eval`: the JSON comes from
  # the TV, and a TV (or anything answering at that address) must never be able
  # to run code on this host.
  DEV_MODE=""; DEV_IP=""; MODEL=""; POWER=""
  while IFS='=' read -r _k _v; do
    case "$_k" in
      DEV_MODE) DEV_MODE="$_v" ;;
      DEV_IP)   DEV_IP="$_v" ;;
      MODEL)    MODEL="$_v" ;;
      POWER)    POWER="$_v" ;;
    esac
  done <<EOF
$(printf '%s' "$API" | python3 -c '
import json,sys
try: d=json.load(sys.stdin).get("device",{})
except Exception: sys.exit(0)
for k,v in [("DEV_MODE",d.get("developerMode")),("DEV_IP",d.get("developerIP")),
            ("MODEL",d.get("modelName")),("POWER",d.get("PowerState"))]:
    print(f"{k}={str(v)}")
' 2>/dev/null)
EOF

  if [ "${DEV_MODE:-}" = "1" ]; then
    ok "Developer Mode is on"
  else
    bad "Developer Mode is off" "TV: Apps → press 12345 → Developer mode ON → reboot the TV"
  fi

  MYIP="$HOST_IP"
  if [ -n "${DEV_IP:-}" ] && [ "${DEV_IP}" = "$MYIP" ]; then
    ok "TV whitelists this computer ($DEV_IP)"
  elif [ -n "${DEV_IP:-}" ]; then
    bad "TV whitelists $DEV_IP but this computer is ${MYIP:-unknown}" \
        "TV: Apps → 12345 → set Host PC IP to ${MYIP:-this box}, then reboot the TV"
  else
    note "could not read developerIP from the TV"
  fi
  info "model: ${MODEL:-unknown} · power: ${POWER:-unknown}"
fi

# ---------------------------------------------------------------- 4. deep root
echo
echo "${B}4. Root${N}"
if [ "$DEEP" = "1" ]; then
  if command -v tv-root >/dev/null 2>&1 || [ -x /usr/local/bin/tv-root ]; then
    printf '  %s· acquiring root (about 20 s)…%s\n' "$D" "$N"
    UID_OUT=$(timeout 120 /usr/local/bin/tv-root 'echo ROOTUID=$(id -u)' 2>&1 | grep -oE 'ROOTUID=[0-9]+' | head -1)
    if [ "$UID_OUT" = "ROOTUID=0" ]; then
      ok "root works — one command as uid 0"
    else
      bad "root acquisition failed" "see docs/rooting.md; try again while the TV is idle"
    fi
  else
    bad "cannot test root without the tv-root wrapper" "install it first (step 2)"
  fi
else
  info "skipped (add --deep to test one real acquisition)"
fi

# --------------------------------------------------------------- 5. auto-apply
echo
echo "${B}5. Re-applying after each power-on${N}"
if systemctl cat tv-root-watchdog.service >/dev/null 2>&1; then
  if systemctl is-enabled --quiet tv-root-watchdog 2>/dev/null; then
    ok "watchdog installed and enabled"
    if systemctl is-active --quiet tv-root-watchdog; then ok "watchdog is running"; else
      note "watchdog enabled but not running"; next_steps+=("sudo systemctl start tv-root-watchdog")
    fi
  else
    note "watchdog installed but not enabled" ; next_steps+=("sudo systemctl enable --now tv-root-watchdog")
  fi
else
  note "watchdog not installed — cuts will revert after a power cycle"
  next_steps+=("sudo ./install.sh  (or copy systemd/tv-root-watchdog.service into /etc/systemd/system)")
fi

for f in /etc/tv-root-perf-units /etc/tv-root-kill-procs; do
  if [ -r "$f" ]; then
    n=$(grep -vc '^[[:space:]]*#' "$f" 2>/dev/null || echo 0)
    ok "$(basename "$f"): $n entries"
  else
    note "$(basename "$f") missing — nothing will be masked/killed"
  fi
done

# ------------------------------------------------------------------- summary
echo
printf '%s────────────────────────────────────────%s\n' "$D" "$N"
printf '  %s%d passed%s   %s%d failed%s   %s%d notes%s\n' "$G" "$pass" "$N" "$R" "$fail" "$N" "$Y" "$warn" "$N"

if [ "$fail" -eq 0 ]; then
  echo
  printf '  %sReady.%s Next: ./agent/audit.sh to see the current state, then ./agent/... playbooks.\n' "$G" "$N"
  echo
  exit 0
fi

echo
printf '  %sDo this next:%s\n' "$B" "$N"
i=1
for s in "${next_steps[@]}"; do printf '   %d. %s\n' "$i" "$s"; i=$((i+1)); done
echo
exit 1
