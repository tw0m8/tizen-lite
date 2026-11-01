# Playbook — a feature broke after cuts

Symptoms that look like network/account faults but are almost always a removed piece:

| Symptom | Usual cause |
|---|---|
| App opens, video fails: *"Something went wrong. Please try again later."* | `aaa_tvs_deamon` masked, or `dta-agent` gone (DRM) |
| Quick-settings panel opens, controls say *"Preparing… Please try again later"* | `com.samsung.tv.home.sidebar` or `contentservicemanager` missing |
| Home key does nothing / blank screen | the configured home app (`FreeMyTVio.*`) is missing or killed |
| App screen or inputs empty | `com.samsung.tv.csfs` / `tv-viewer` touched |
| Root acquisition fails, nothing applies | `sdbd` masked or down, or the exploit ran too early |

## Rules

1. **Do not hunt logs.** This firmware has none (`journalctl`, `dlogutil`, `/var/log/dlog` all empty).
2. **Bisect by restoring, newest-first.** Restore the most recent change in halves; wait for the human's
   confirmation between cycles.
3. **Restore + reboot + verify**, then re-run `./agent/audit.sh` so the next agent sees the truth.
4. **Check for a stale session before blaming a cut.** A DRM-style error can survive the TV's own reboot
   and clear only on a cold boot (power off, power on). If playback worked minutes earlier with the same
   config, suspect the session, not the config.

## Fast restore

```bash
BK=/opt/usr/share/tv-root-backups/<change-set>
mv $BK/<pkg> /opt/usr/apps/                      # directory back
# records back
sqlite3 /opt/dbspace/.pkgmgr_parser.db < /tmp/restore.sql   # app_disable='false', app_autorestart='true'
# and drop the pattern from /etc/tv-root-kill-procs, then:
tv run 'sync; reboot'
```

Masked unit: remove the line from `/etc/tv-root-perf-units`, then `tv svc unmask <unit>` (or reboot —
runtime masks clear themselves).

## After the fix

Record it: which piece, which symptom, found by which boot. Add it to `manifest.json → invariants` so the
next agent does not repeat the experiment. This is how `aaa_tvs_deamon` and the quick-settings pair got
documented — a wrong guess costs a reboot cycle, a written-down finding costs nothing.
