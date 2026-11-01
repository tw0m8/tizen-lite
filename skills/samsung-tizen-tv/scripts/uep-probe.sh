#!/usr/bin/env bash
# uep-probe.sh <tv-ip> <host-ip> [tv-root-wrapper]
#
# Decides whether this Tizen build executes an UNSIGNED native binary.
# UEP (Unauthorized Execution Prevention, part of SFD) checksums executables and
# libraries loaded from writable partitions, and root does NOT bypass it. Run this
# before promising any native daemon (dropbear, busybox, a custom listener).
#
# Interpretation of the printed RT_EXIT:
#   UEP_PROBE_OK + 0        -> unsigned ELF runs; a native daemon is possible
#   Operation not permitted / 126 -> UEP blocks it: only the signed `bash`
#                              (`cat x.sh | bash`) and /usr/bin/dotnet remain
#
# The probe is freestanding (-nostdlib), so no cross libc headers are needed and
# the binary is ~1 KB. It is deleted from the TV at the end of the run.
set -uo pipefail

TV="${1:?usage: uep-probe.sh <tv-ip> <host-ip> [tv-root-wrapper]}"
HOST="${2:?usage: uep-probe.sh <tv-ip> <host-ip> [tv-root-wrapper]}"
WRAPPER="${3:-/usr/local/bin/tv-root}"
export TV_HOST="$TV"          # the wrapper targets this TV, not whatever /etc/default says
curl -s -m 4 -o /dev/null "http://$TV:8001/api/v2/" \
  || { echo "no answer from $TV:8001 - is the TV on and reachable?" >&2; exit 2; }
PORT="${PORT:-8899}"
DIR="$(mktemp -d)"
SRV_PID=""
cleanup() {
  if [ -n "$SRV_PID" ]; then
    kill "$SRV_PID" 2>/dev/null || true
  fi
  rm -rf "$DIR"
}
trap cleanup EXIT

cat >"$DIR/probe.s" <<'ASM'
.global _start
_start:
 mov r7,#4        @ write
 mov r0,#1        @ stdout
 ldr r1,=msg
 mov r2,#13       @ 12 chars + newline
 svc #0
 mov r7,#1        @ exit
 mov r0,#0
 svc #0
msg: .ascii "UEP_PROBE_OK\n"
ASM

command -v arm-linux-gnueabihf-gcc >/dev/null || apt-get install -y -qq gcc-arm-linux-gnueabihf
arm-linux-gnueabihf-gcc -nostdlib -static -marm -o "$DIR/uep-test" "$DIR/probe.s" || {
  echo "cross-compile failed (need gcc-arm-linux-gnueabihf)" >&2; exit 2; }
readelf -h "$DIR/uep-test" | grep -E 'Class|Machine'

cd "$DIR" || exit 2
python3 -m http.server "$PORT" --bind "$HOST" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 20); do
  curl -s -m 2 -o /dev/null "http://$HOST:$PORT/uep-test" && break
  sleep 0.5
done

# Build the remote command in a double-quoted host string so $HOST/$PORT expand here,
# but escape $? — otherwise the host shell substitutes its own exit status.
REMOTE="cd /opt/usr/share && curl -s -o uep-test http://$HOST:$PORT/uep-test; chmod 755 uep-test; ./uep-test; echo RT_EXIT=\$?; rm -f uep-test"
"$WRAPPER" "$REMOTE" | sed -n '/stdout:/,$p'

cat <<'NOTE'
UEP_PROBE_OK + RT_EXIT=0      -> unsigned native binaries RUN; a native daemon is viable.
Operation not permitted/126    -> UEP blocks unsigned ELF even at uid 0: no native binaries.
                                  Use `cat x.sh | bash` or /usr/bin/dotnet (Core 6.0.9) instead.
NOTE
