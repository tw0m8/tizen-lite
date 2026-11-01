# Playbook — disable one systemd unit

Use for: telemetry, promo, OTA, unused-hardware services.

## Preconditions

- `./agent/audit.sh` shows `tv.reachable: true` and `tv.status.root_ok: true`.
- The unit is **not** in `manifest.json → invariants.never_remove`.

## Steps

1. **Find out what it is.** `RequiredBy` empty means nothing hard-depends on it:

   ```bash
   tv run 'systemctl show -p Id -p Description -p RequiredBy <unit>'
   ```

2. **Add it to the masked list** — `/etc/tv-root-perf-units` (one unit per line, comments allowed).
   The applier reads this file every cycle, so this is the only place the decision lives.

3. **Apply now** (no reboot needed to see the effect, but a reboot is what proves it):

   ```bash
   tv-root-apply --only perf
   ```

4. **Mask *and* stop.** `systemctl mask --runtime` alone leaves a running unit alive. The `tv svc mask`
   verb now masks, stops, waits, and escalates to SIGKILL when a unit sits in `deactivating`:

   ```bash
   tv svc mask <unit>        # expect: inactive | failed   (failed = stop returned non-zero, still masked)
   ```

5. **Verify state** — `systemctl is-active <unit>` must not be `active`, and the enabled-state must
   read `masked` / `masked-runtime`.

6. **Cold boot and re-verify** — masks live in `/run` and disappear on power-off, so only a boot proves
   persistence. The apply log must show `ITEM|perf|unit_masks|…` and `END changed=… errors=0`.

## Undo

Remove the line from `/etc/tv-root-perf-units`, `systemctl unmask <unit>`, `systemctl start <unit>`,
reboot, re-audit.

## Traps

- **Static units cannot be masked** (`is-enabled` = `static`). Masking them is a silent no-op; the unit
  runs anyway. Check `is-enabled` before claiming a win.
- **D-Bus activated units respawn** within seconds of a stop (`data-service` is the classic case). Not a
  win — record it as "not worth it" instead.
- Some units ignore SIGTERM and hang in `deactivating`; escalate to SIGKILL.
- Nothing in the unit name guarantees safety. `aaa_tvs_deamon` looks like plumbing and is required for
  Prime Video.
