# Playbook — measure, then reclaim memory or boot time

## Measure first (idle only)

A streaming TV holds ~300 MB more than an idle one, so every reading must be idle-to-idle.

```bash
./agent/audit.sh | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["state"]["memory"], d["tv"]["launcher_start_offset_s"])'
```

What to trust:

- **RAM available / swap / CMA** from `/proc/meminfo` — higher available, lower swap, higher `CmaFree` is
  the goal (CMA is what the video decoder needs; when it collapses, playback stutters).
- **Launcher start offset** from `/proc/<pid>/stat` field 22 — this is what a person feels. The REST API
  answering early means nothing: it can be up 100 s before the first picture.

## Where the memory actually is

Ranked by what was measured on this platform:

1. **Art Mode** — `art-app` + `home.art`, ~187 MB. Also early in the boot queue, so it delays the launcher.
2. **Samsung Home app** — `home.media`, ~112 MB (safe only with sidebar + contentservicemanager present).
3. **Quick-panel stack** — `home.sidebar` ~93 MB + `contentservicemanager` ~20 MB. **Required** for quick
   settings; do not remove.
4. **Long tail** — `vif`, `context-aware*`, `easysetup`, `tap-service`, `airplay`, `samsung-cloud`,
   ~120 MB combined.
5. **Services** — telemetry/promo/OTA units, ~60 MB and a shorter boot queue.

Core framework (`csfs` ~150 MB, `FreeMyTV` ~70 MB on this build) is not negotiable.

## Boot time

Boot delay is the *startup queue*, not memory. Services start serially and the launcher is near the end
(~134–150 s on this set). Removing things that start ahead of the launcher shortens it; removing late
services does not. Map the queue before promising an improvement:

```bash
tv run 'ps -eo pid=,rss=,comm= | ... '   # or read /proc/<pid>/stat field 22 for each app
```

## Reporting

Quote the four numbers (available, swap, CMA, processes) plus launcher offset, before and after, and say
plainly if the change did not move them. "Felt faster" is not a measurement; neither is "memory improved".
