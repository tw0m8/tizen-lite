---
name: tizen-lite
description: "Use when debloating, rooting or de-lagging a Samsung Tizen TV. Reversible, boot-verified cuts with a symptom-to-cause map."
summary: "Slim a Samsung Tizen TV without breaking playback: what is safe to remove, what silently breaks DRM or the settings panel, and how to prove every change with a cold boot."
version: 1.1.0
tags: [samsung, tizen, smart-tv, debloat, root, privacy, adb, sdb]
keywords: [samsung tv debloat, tizen root, remove tv plus, turn off acr, stop tv telemetry, tizen lag fix]
use_cases:
  - "Make a slow Samsung TV responsive by removing background services and heavy apps"
  - "Stop ACR content recognition, telemetry and the OTA updater on a Tizen TV"
  - "Diagnose which debloat change broke Prime Video or the quick-settings panel"
  - "Find out whether a Tizen TV can be rooted and what root actually enables"
docs_url: "https://github.com/tw0m8/tizenlite"
author: tw0m8
license: MIT
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
platforms: [linux]
metadata:
  hermes:
    tags: [samsung, tizen, tv, debloat, root, privacy]
    related_skills: [samsung-tv-cli, samsung-tizen-tv]
---

# Tizen Lite

Slim down a Samsung Tizen TV **without bricking playback**, and be able to undo every change.
Derived from one **Samsung QE75Q60** (Q60D, 2024, 75") on Tizen 9.0 (kernel 5.4.249), verified
over repeated cold boots. Same model year: the unit names below are likely to match. Different model
year: treat every name as a hypothesis and confirm it with the discovery step plus one cold boot.

Measured on that set, idle: **RAM 340 → 635 MB**, swap **768 → 513 MB**, apps **51 → 33**, CMA
(the memory video decode needs) **6 → 112 MB**. Most interface lag goes with it — not all of it.

## Use this skill when

- The TV feels slow, stutters, or apps freeze.
- The user wants ads, telemetry, ACR or OTA updates stopped.
- Something broke after debloating and you must find which cut did it.
- Someone asks whether a Tizen TV can be rooted, or what root actually buys.

## Rule 0 — discover, don't assume

```bash
./scripts/tv-doctor.sh      # prerequisites; ends with the numbered list of what to fix, if anything
./agent/audit.sh            # JSON: reachable, rooted, which units are really down, memory, launcher offset
```

A user who says "it doesn't work" almost always has Developer Mode off, a wrong Host PC IP, or no root
chain — the doctor names which one instead of guessing.

If that script is not present, gather the same facts manually before changing anything. Never cut a unit
or app you have not confirmed exists on this build — unit names and app ids differ between model years.

## Rule 1 — these are load-bearing

| Don't touch | Breaks | Symptom |
|---|---|---|
| `aaa_tvs_deamon` | Prime Video / PlayReady licence path | app opens, every video fails: *"Something went wrong. Please try again later."* |
| `com.samsung.tv.home.sidebar` + `com.samsung.tv.contentservicemanager` | quick-settings panel | panel opens, every control says *"Preparing… Please try again later"* |
| `dta-agent` | CDM / PlayReady trusted app | DRM playback dies for a few MB saved |
| `sdbd` | root transport (starts ~121 s into boot) | root acquisition fails, nothing applies |
| `com.samsung.tv.csfs` | core content framework | broad instability |
| the configured home app (`FreeMyTVio.*` on this set) | the user's launcher | Home key shows nothing |

None of these announce their importance. `aaa_tvs_deamon` is DRM; the sidebar pair is the settings panel.

## Rule 2 — one variable per cold boot

**Live changes prove nothing.** Stopping a unit on a running TV does not reproduce breakage: an
already-acquired licence or a rendered panel keeps working, so a live test reports "fine" even when that
unit is required. Starting it late does not repair it either.

1. Change exactly one thing.
2. Reboot, let the apply chain finish.
3. Verify state **and** ask the human to exercise the feature.
4. Broke it? Revert, reboot, record the finding.

Restoring a lost feature: halves, newest change first.

## Rule 3 — two different mechanics

- **Systemd units**: `systemctl mask --runtime` (retail `/etc` is read-only, so masks are per-boot) —
  and masks alone do **not** stop a running unit. Mask, stop, and escalate to SIGKILL when it hangs in
  `deactivating`. Static units can't be masked at all; D-Bus-activated ones respawn instantly.
- **Apps**: `pkill` is a no-op — `launchpad-process-pool` restarts them. Disable the package records
  (`app_disable='true'`, `app_autorestart='false'`) **and** move the directory out of `/opt/usr/apps`.
  Move, never delete; copy `package_app_info` (`/opt/dbspace/.pkgmgr_parser.db`) first.

## Rule 4 — verify, then report

Done means all three: state (`inactive|failed` + masked, or dir gone with no process), persistence
(survived a cold boot, apply log `END changed=… errors=0`), function (the human confirmed the features
they use). Report with numbers, not adjectives.

```
Diagnosis / Evidence / Change / Risk / Rollback / Your turn
```

## Where the memory actually is

| Target | Frees | Note |
|---|---|---|
| Art Mode (`art-app` + `home.art`) | ~187 MB | also early in the boot queue |
| `home.media` | ~112 MB | safe only while sidebar + contentservicemanager stay |
| quick panel (`home.sidebar` + `contentservicemanager`) | ~113 MB | **required** — do not remove |
| long tail: `vif`, `context-aware*`, `easysetup`, `tap-service`, `airplay`, `samsung-cloud` | ~120 MB | ACR removal is also the privacy win |
| telemetry/promo/OTA units | ~60 MB + shorter boot queue | `swu-auto-upgrade`, `reporterCA`, `pvod`, … |

## Platform traps

- **No logs.** `journalctl`, `dlogutil`, `/var/log/dlog` are empty. Bisect instead of hunting them.
- **`pkill -f` / `pgrep -f` match your own command line** — bracket the pattern (`org[.]tizen[.]art-app`).
- **UEP blocks unsigned scripts even as root** (`[uep][bash] the file is NOT signed!!`). Ship inline, or
  as data for a signed interpreter (`sqlite3 db < file.sql`).
- **One huge command runs only partly** — a ~13 KB compound command skipped its middle groups with exit
  status 0. Keep chunks under ~4 KB and parse `ITEM|` lines.
- **Judge boot by the launcher**, not `/api/v2/`: measure `/proc/<pid>/stat` field 22.
- **A DRM-style error right after a reboot may be a stale session**, not your cut — a cold boot clears it.

## References

- `agent/manifest.json` — machine-readable invariants, verified-removable list, restore layout.
- `agent/playbooks/` — disable-a-unit, remove-an-app, diagnose-broken-feature, reclaim-memory.
- `docs/` — rooting, boot & startup, debloat/modding, app uninstall, sdb audit.
- `bin/` — `tv` CLI, state applier, watchdog, polling agent.
