#!/usr/bin/env bash
# Install Tizen Lite on the host that will drive the TV.
#
#   sudo ./install.sh              install tools, state files, systemd units
#   DESTDIR=/tmp/x ./install.sh    stage for inspection (no systemd actions)
#   sudo ./install.sh --uninstall  remove units and binaries (state files and
#                                  TV-side backups are deliberately kept)
#
# Nothing on the TV is touched by this script; it only places host-side files.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTDIR="${DESTDIR:-}"
MODE="install"
[ "${1:-}" = "--uninstall" ] && MODE="uninstall"

BIN="$DESTDIR/usr/local/bin"
LIB="$DESTDIR/usr/local/lib/tv-agent"
UNIT="$DESTDIR/etc/systemd/system"

say()   { printf '  %s\n' "$*"; }
head_() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" = "0" ] || [ -n "$DESTDIR" ] || { echo "run as root (or set DESTDIR)" >&2; exit 1; }

# The tools need Python 3.7+: f-strings, `subprocess.run(capture_output=)` and
# `from __future__ import annotations` (which is why `str | None` annotations are
# fine on 3.7-3.9 - they are never evaluated). Failing here beats a traceback later.
if [ -z "$DESTDIR" ]; then
  if ! python3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,7) else 1)' 2>/dev/null; then
    echo "python3 >= 3.7 is required (found $(python3 -V 2>&1 || echo none))" >&2
    exit 1
  fi
  command -v sdb >/dev/null 2>&1 || echo "note: sdb not on PATH yet - it comes with the Tizen SDK" >&2
fi

if [ "$MODE" = "uninstall" ]; then
  head_ "stopping and removing units"
  if [ -z "$DESTDIR" ] && command -v systemctl >/dev/null; then
    systemctl disable --now tv-root-watchdog.service 2>/dev/null || true
    systemctl disable --now tv-agent.service 2>/dev/null || true
  fi
  rm -f "$UNIT/tv-root-watchdog.service" "$UNIT/tv-agent.service"
  if [ -z "$DESTDIR" ] && command -v systemctl >/dev/null; then systemctl daemon-reload || true; fi
  head_ "removing binaries"
  rm -f "$BIN/tv" "$BIN/tv-root-apply" "$BIN/tv-root-watchdog" "$BIN/tv-agent" \
        "$BIN/tv-agent-server.py" "$BIN/tv-agent-start" "$LIB/loop.sh"
  say "kept: $BIN/tvlib.py, /etc/default/tv-root, /etc/tv-root-perf-units, /etc/tv-root-kill-procs"
  say "kept: everything on the TV — use ./restore.sh --all --yes to undo cuts there"
  exit 0
fi

head_ "installing host tools"
mkdir -p "$BIN" "$LIB" "$DESTDIR/etc/default"
install -m 755 "$SRC/bin/tv"                 "$BIN/tv"
install -m 755 "$SRC/bin/tvlib.py"           "$BIN/tvlib.py"
install -m 755 "$SRC/bin/tv-root-apply"      "$BIN/tv-root-apply"
install -m 755 "$SRC/bin/tv-root-watchdog"   "$BIN/tv-root-watchdog"
install -m 755 "$SRC/bin/tv-agent"           "$BIN/tv-agent"
install -m 755 "$SRC/bin/tv-agent-server.py" "$BIN/tv-agent-server.py"
install -m 755 "$SRC/bin/tv-agent-start"     "$BIN/tv-agent-start"
install -m 755 "$SRC/bin/tv-agent-loop.sh"   "$LIB/loop.sh"
say "bin/ -> $BIN"
say "loop  -> $LIB/loop.sh"

head_ "installing default state files (existing files are kept)"
for pair in "tv-root.env.example:/etc/default/tv-root" \
            "tv-root-perf-units.example:/etc/tv-root-perf-units" \
            "tv-root-kill-procs.example:/etc/tv-root-kill-procs"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  if [ -e "$DESTDIR$dst" ]; then
    say "kept existing $dst"
  else
    mkdir -p "$(dirname "$DESTDIR$dst")"
    install -m 644 "$SRC/config/$src" "$DESTDIR$dst"
    say "created $dst"
  fi
done

head_ "installing systemd units"
mkdir -p "$UNIT"
install -m 644 "$SRC/systemd/tv-root-watchdog.service" "$UNIT/tv-root-watchdog.service"
install -m 644 "$SRC/systemd/tv-agent.service"         "$UNIT/tv-agent.service"
say "tv-root-watchdog.service + tv-agent.service -> $UNIT"
if [ -z "$DESTDIR" ] && command -v systemctl >/dev/null; then
  systemctl daemon-reload
  systemctl enable --now tv-agent.service 2>/dev/null || say "tv-agent will start on boot"
  say "watchdog installed but NOT started — run the doctor first:"
  say "  sudo systemctl enable --now tv-root-watchdog"
else
  say "DESTDIR set — systemd not touched"
fi

cat <<'NEXT'

==> next steps
  1. ./scripts/tv-doctor.sh          checks the TV, sdb and root, and tells you what to fix
  2. ./scripts/tv-doctor.sh --deep   also performs one real root acquisition (~20 s)
  3. ./agent/audit.sh                current state as JSON, changes nothing
  4. sudo systemctl enable --now tv-root-watchdog   once the doctor is green

  Nothing on the TV has been changed yet.
NEXT
