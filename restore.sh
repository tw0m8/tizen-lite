#!/usr/bin/env bash
# tizen-lite restore — undo changes, one app at a time or everything.
#
#   ./restore.sh --list              show backups and what is currently masked (changes nothing)
#   ./restore.sh --app <appid>       put one app back
#   ./restore.sh --all --yes         revert every removal + unmask every unit
#
# Every action is applied on the TV through `tv run` (root, one call each).
set -uo pipefail
BK="/opt/usr/share/tv-root-backups"
DB="/opt/dbspace/.pkgmgr_parser.db"
PERF="${TV_PERF_UNITS:-/etc/tv-root-perf-units}"
KILL="${TV_KILL_PROCS:-/etc/tv-root-kill-procs}"

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; B=$'\033[1m'; N=$'\033[0m'
else G=""; R=""; Y=""; D=""; B=""; N=""; fi

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

tvrun() { tv run -c "${2:-2500}" "$1" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("out","").strip())' 2>/dev/null; }

list_backups() {
  echo
  printf '%sBackups on the TV%s  %s(%s)%s\n' "$B" "$N" "$D" "$BK" "$N"
  tvrun "ls -1 $BK 2>/dev/null" | sed '/^$/d' | while read -r set; do
    echo "  • $set"
    tvrun "ls -1 $BK/$set 2>/dev/null" | sed '/^$/d' | sed 's/^/      /'
  done
}

list_state() {
  echo
  printf '%sCurrently masked%s %s(%s)%s\n' "$B" "$N" "$D" "$PERF" "$N"
  if [ -r "$PERF" ]; then grep -vE '^\s*(#|$)' "$PERF" | sed 's/^/  • /' | head -40; else echo "  (file not found)"; fi

  echo
  printf '%sProcesses killed after every boot%s %s(%s)%s\n' "$B" "$N" "$D" "$KILL" "$N"
  if [ -r "$KILL" ]; then grep -vE '^\s*(#|$)' "$KILL" | sed 's/^/  • /' | head -40; else echo "  (file not found)"; fi

  echo
  printf '%sRemoved app directories%s\n' "$B" "$N"
  tvrun "for set in \$(ls -1 $BK 2>/dev/null); do
           dirs=\$(ls -1d $BK/\$set/*/ 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')
           [ -n \"\$dirs\" ] && echo \"  \$set: \$dirs\"
         done" | sed '/^$/d'
}

# An app id reaches the TV as root inside a shell command and inside SQL, so it
# is validated before use: letters, digits, dot, dash, underscore only.
valid_app_id() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) [ "${#1}" -le 64 ] ;;
  esac
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

restore_app() {
  local app="$1" found="" safe_app
  if ! valid_app_id "$app"; then
    printf '%s✗%s invalid app id: %s (letters, digits, dot, dash, underscore only)\n' "$R" "$N" "$app"
    return 2
  fi
  safe_app=$(sql_escape "$app")
  for set in $(tvrun "ls -1 $BK 2>/dev/null"); do
    if [ -n "$(tvrun "[ -d $BK/$set/$app ] && echo yes")" ]; then found="$BK/$set/$app"; break; fi
  done
  if [ -z "$found" ]; then
    printf '%s✗%s no backup found for %s\n' "$R" "$N" "$app"
    printf '  run %s./restore.sh --list%s to see what is available\n' "$D" "$N"
    return 1
  fi
  printf '  %s· restoring %s from %s…%s\n' "$D" "$app" "${found#"$BK"/}" "$N"
  out=$(tvrun "if [ -d /opt/usr/apps/$safe_app ]; then mv /opt/usr/apps/$safe_app /opt/usr/apps/$safe_app.bak.\$(date +%s); fi
         cp -a $found /opt/usr/apps/ && sqlite3 $DB \"UPDATE package_app_info SET app_disable='false', app_autorestart='true' WHERE app_id IN ('$safe_app','$(appid_alias \"$app\")');\"" 4000)
  case "$out" in
    *[Ee]rror*|*"no such"*|"")
      printf '  %s✗%s %s NOT restored — the TV said: %s\n' "$R" "$N" "$app" "${out:-no output}"
      return 1 ;;
  esac
  printf '  %s✓%s %s restored — reboot the TV (or let the watchdog apply) for it to launch\n' "$G" "$N" "$app"
}

# A few packages are stored under a longer id than the folder name.
appid_alias() {
  case "$1" in
    *FreeMyTV*) echo "FreeMyTVio.FreeMyTV" ;;
    *) echo "$(sql_escape "$1")" ;;
  esac
}

restore_all() {
  [ "${1:-}" = "--yes" ] || { printf '%sRefusing without --yes.%s This unmasks every unit and restores every backup.\n' "$Y" "$N"; exit 1; }
  echo
  printf '%s1/3%s restoring app directories…\n' "$B" "$N"
  tvrun "for set in \$(ls -1 $BK 2>/dev/null); do
           for d in $BK/\$set/*/; do
             [ -d \$d ] || continue
             p=\$(basename \$d)
             if [ ! -d /opt/usr/apps/\$p ]; then cp -a \$d /opt/usr/apps/ && echo \"restored \$p\"; fi
             esc=\$(printf '%s' \"\$p\" | sed \"s/'/''/g\")
             sqlite3 $DB \"UPDATE package_app_info SET app_disable='false', app_autorestart='true' WHERE app_id LIKE '%\$esc%';\" 2>/dev/null
           done
         done" 8000 | sed 's/^/    /'

  printf '%s2/3%s unmasking units…\n' "$B" "$N"
  tvrun "while read -r u; do case \$u in ''|'#'*) continue;; esac; systemctl unmask \$u 2>/dev/null; systemctl start \$u 2>/dev/null; echo \"unmasked \$u\"; done < $PERF" 8000 | sed 's/^/    /'

  printf '%s3/3%s clearing the kill-list…%s\n' "$B" "$N" "$D"
  if [ -w "$KILL" ] || [ "$(id -u)" = 0 ]; then
    cp "$KILL" "$KILL.bak.$(date +%s)" 2>/dev/null
    sed -i 's/^\([^#]\)/# \1/' "$KILL"
    printf '    %scommented out every pattern in %s (backup kept)%s\n' "$G" "$KILL" "$N"
  else
    printf '    %s!%s cannot write %s — comment its lines out by hand\n' "$Y" "$N" "$KILL"
  fi
  echo
  printf '  %sDone.%s Power-cycle the TV, then run ./agent/audit.sh to confirm the stock state.\n' "$G" "$N"
  echo
}

case "${1:-}" in
  --list|"") list_backups; list_state ;;
  --app) [ -n "${2:-}" ] || usage 2; restore_app "$2" ;;
  --all) shift; restore_all "${1:-}" ;;
  -h|--help) usage 0 ;;
  *) usage 2 ;;
esac
