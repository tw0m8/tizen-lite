---
name: samsung-tv-cli
description: "Use when operating the rooted Samsung TV via tv CLI. Component of the tizen-lite skill."
version: 1.1.0
author: Hermes Agent
license: MIT
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
platforms: [linux]
metadata:
  hermes:
    tags: [samsung, tizen, tv, cli, root, logging]
---
> **Component skill.** The umbrella skill for this project is `tizen-lite` — it carries the
> load-bearing list, the boot-bisect protocol and the report format. Load it first.


# Samsung TV CLI (`tv`)

## When to Use

Use whenever the rooted Samsung TV needs to be inspected or changed from this host: status and
memory checks, log tails, app launch/kill, service control, vconf prefs, boot/autostart wiring, SQL
against the Tizen DBs, AdGuard rewrites for the TV, or waking it. Reach for `tv` before writing a
your own `tv-agent` or `tv-root` command.

One command surface for the rooted Q60D. Backend is `/usr/local/bin/tvlib.py`; the CLI is
`/usr/local/bin/tv`. TV-side verbs ride the ~1 s polling agent (root, uid 0); `tv root` is the slow
~15–20 s fallback when that agent is down.

**Use the CLI instead of hand-built `tv-agent`/`tv-root` strings.** It is shorter to call, refuses the
commands that wedge the TV, and returns small JSON instead of a wall of text.

## Verbs

| Command | Does |
|---|---|
| `tv status` | power, root state, agent health, memory, running-app count, home app |
| `tv run '<cmd>'` | shell on the TV as root (~1 s) |
| `tv root '<cmd>'` | one volatile root acquisition (~15–20 s), fallback only |
| `tv sql <pkgmgr\|appsvc> '<query>'` | SQL against the package/appsvc DBs (base64-staged, quoting never bites) |
| `tv apps [filter]` / `tv app launch\|kill <id>` | running apps; start/stop by app id |
| `tv log file <alias> [-n N]` | tail a real log file (aliases below) |
| `tv log dlog [-n N] [--tag T]` | bounded `dlogutil -t N` (empty on this build — see below) |
| `tv boot list` | enabled units, onboot-app count, startup pref, home app (~20 s) |
| `tv boot startup <app>` / `tv boot onboot <app> on\|off` | autostart wiring |
| `tv svc status\|start\|stop\|restart\|mask\|unmask <unit>` | service control (mask is `--runtime`) |
| `tv vconf get <key>` / `tv vconf set <key> <val> [type]` | Tizen vconf prefs |
| `tv apply [groups] [--dry-run]` | re-apply managed state (home, memory, privacy, ota, voice, perf) |
| `tv agent status\|start\|reset` | the polling loop: health, restart after a lost loop, clear a stale queue |
| `tv firmware` | TV build vs published build |
| `tv power` / `tv wake [mac]` | read power state / WoL |
| `tv sdb devices\|connect\|capability` | sdb wrapper (also unwedges a stale session) |
| `tv dns list\|add <name> <ip>\|remove <name>` | AdGuard rewrites (stops the container, edits YAML, starts it) |

Log aliases: `install` (installation-history.log), `install-log`, `install-fail`, `fota`, `alarm`,
`migration`. Paths live under `/var/log/appfw/**`.

## Logging reality on this build

- **journald is inactive** — `journalctl` returns "No journal files were found". There are no
  per-service logs; do not promise them.
- **dlog reads empty** — `dlogutil` exists and `/dev/log_main` is readable, but the ring buffer holds
  nothing (`Dlog Config: plog(0) vlog(1) enable_apps(0)`), even seconds after an app launches.
- **The files are the logs.** `/var/log/appfw/app-installers/installation-history.log` records every
  install/update with result — use it to see Samsung preload apps updating themselves even while
  firmware OTA stays blocked.

## Hard rules (each one earned)

1. **The agent loop is single-threaded.** One blocking command stalls every later call, and the fix is
   `tv root 'pkill -f <cmd>'` from outside. `tv run` refuses `tail -f`, bare `dlogutil`, `logcat` and
   `watch` for exactly this reason.
2. **`systemctl` costs ~10 s per query on this TV.** Fetch once into a variable and reuse it; a
   two-call version of `boot list` timed out at 30 s, the single-call version takes ~20 s.
3. **SQL goes through `tv sql`, not `tv run`.** Double quotes inside a shell string get eaten and
   SQLite then reads `%main%` as an identifier; the base64 path avoids the whole class of bug.
4. **A wedged sdb session looks like a broken exploit.** If `tv root`/archive-root fails at `probe`
   with `TimeoutError` while the TV is fine, run `tv sdb connect` (kill-server/start-server/connect)
   before rebooting anything.
5. **The Home mapping is read at boot.** Changing the appsvc `operation/main` row needs a power
   cycle, and `tv-root-apply`'s `HOME_APP` must match or the next boot reverts it.
6. **`/etc` is read-only**, so unit masks are `--runtime` and vanish on power-off; the watchdog
   re-applies them per boot. Never expect a persistent mask.
7. **Renaming or re-pointing an app's launch arguments is DB state**, not `config.xml` — the framework
   replays `package_app_app_metadata.native.userdata` from `/opt/dbspace/.pkgmgr_parser.db`.
8. **`app_disable`/'app_onboot' do not stop a daemon — the parent does.** Read `ppid` before choosing
   a weapon:
   - **`ppid 1`** = started by **systemd**: `systemctl status <pid>` names the unit, then
     `systemctl mask --runtime <unit>` + stop, escalating to `systemctl kill -s KILL` when it stays
     `deactivating` (several Samsung units ignore SIGTERM and never finish stopping).
   - **`ppid 257`** = `/usr/bin/launchpad-process-pool`, which relaunches app processes within seconds
     and **ignores the DB flags** (`app_disable='true'` and `app_autorestart='false'` were both set and
     the process still returned in <5 s). No kill or record edit stops it; **moving the app dir out of
     `/opt/usr/apps`** is the only durable stop. Do not kill launchpad itself — it launches every app.

   The `perf` group in `tv-root-apply` does exactly this (`PERF` app list + `PERF_UNITS` + the
   `/etc/tv-root-kill-procs` list); `/etc` being read-only means masks must be re-applied every boot,
   so they have to live in an apply group. Uninstall details, the respawn mechanism and the
   kill-verification traps are in `references/app-uninstall.md`.
9. **Two watchdog defects are fixed but easy to reintroduce:** it used to read
   `/etc/default/tv-root` **once at startup** (a new group silently never ran at boot), and it never
   reattached `sdb` after a power cycle (acquisition then failed with a misleading "REST API did not
   answer"). Both now happen every cycle — keep them there when editing it.
10. **`tv-root-apply --only home` prints `ITEM|home|home_mapping|ok` but still exits as "acquisition
    or remote command failed"** — a parser quirk for a single-group run. Verify Home with
    `tv sql appsvc "SELECT pkg_name FROM appsvc WHERE operation LIKE '%main%'"` instead.
11. **You cannot choose the TV's first screen from userspace.** `db/appfw/startup_appid` is "last app
    used" and the framework **rewrites it at shutdown** (HDMI viewer wins back the moment that input
    was used), while every app-launch route — `/api/v2/applications/<id>`, `/ws/apps/…`, `/apps/…`,
    DIAL :56789 — answers **401**. So a boot-to-launcher request is satisfied by the watchdog pushing
    the Home app (`ensure_launcher`, once root is available) plus cutting the startup queue; say that
    plainly instead of promising a persisted startup key.
12. **Archive-root fails on a cold boot by design of its own timing oracle** — while services are
    starting, the `control` probe is slow enough that the delay probe looks identical and the tool
    reports "package-name shell execution was not confirmed". The watchdog must therefore settle ~30 s
    after power-on and retry (4 attempts, ~25 s apart); a single attempt at power-on leaves the TV
    with no apply and no agent, which reads like a broken exploit.
13. **A playback failure needs a cold boot to test, and the app's own state cleared first.** DRM session
    state is established at boot, so a unit masked mid-session can keep playing while the same masks
    applied at boot break playback — and restoring a unit afterwards does not rebuild that session. Clear
    the app's data/cache, then cold boot, then bisect one unit at a time; anything less cannot attribute
    the fault. Measure RAM only when idle (a streaming set reads ~300 MB lower).
14. **Never power the set off remotely unless someone is there to press the button.** `tv power off`
    returns `power: on` and leaves uptime unchanged (it is a standby/key request, not a power cut), so
    check reachability and uptime instead of trusting its reply. A real cycle is
    `tv root 'sync; poweroff'`, and that acquisition can still print an sdb error while the poweroff
    lands. The set did **not** return from a WoL magic packet after a standing power-off, so a remote
    power cycle strands the TV until a human walks over. Prefer `tv run 'reboot'`, which comes back on
    its own, and say out loud when a step will leave the screen dark.

## Performance work

Idle daemons are the only lever that moves anything real, and the way to prove it is the **launcher's
boot offset**, not the REST API (8001 answers ~40 s in, boot logo still on screen). The `perf` group in
`tv-root-apply` holds the disabled app records plus the runtime unit masks; measured at comparable
uptime, **available 340 → 540 MB, swap 768 → 634 MB, CMA 6.5 → 72 MB, running apps 51 → 41** (the
perf group plus the 11 masked Tier A services).

Boot-to-launcher stays ~2.5 min because ~20 app services start **serially** ahead of the Home app; the
queue, the ranked disable candidates, the measurement recipe and the first-screen findings are in
`references/boot-and-startup.md`. The remaining memory pool is the Samsung UI stack (HomeMedia 111 MB,
QuickLaunch 58, HomeSidebar 45, ArtApp 39, HomeArt 33 ≈ 286 MB) — one process at a time, reboot as the
kill switch. When a "process kill" turns out not to stick, it is launchpad respawning it: see rule 8 and
`references/app-uninstall.md` (Art Mode, TV Plus, AirPlay, Samsung Cloud and the content-service
manager were all removed by moving their dirs, reaching idle 340 → ~630 MB available on this set). The
verified per-app RSS ranking command lives at the end of that file — use it instead of re-deriving the
`awk` pipeline, and only measure when the set is idle.

## What is load-bearing for this user

He runs **Free My TV** as the launcher of record, and it already covers the app screen, input
switching and the settings shortcut. So Samsung's own Home stack (`home.media`, `home.sidebar`,
`home.art`) is discretionary, and "Samsung Home might break" is not a reason to keep a 20 MB service —
but equally it means Samsung Home **cannot be brought on screen for a visual check** (see
`references/app-uninstall.md`), so never present a removal as verified on process-gone alone.

Installing a store app means unblocking Samsung's domains for a few minutes and re-blocking after; that
is his normal flow, not something to "fix" by re-enabling OTA or telemetry. The verification loop he
expects for every debloat change is: change one thing → cold boot → he confirms the surfaces he uses
(app screen, input switching, settings, Prime) → then keep it. Batch removals of the same family are
fine once that loop has been through it a couple of times; unrelated features are not.

## Typical calls

```bash
tv status
tv log file install -n 10
tv sql pkgmgr "SELECT app_id FROM package_app_info WHERE app_onboot='true' LIMIT 10"
tv boot onboot com.samsung.tv.wakeupless off
tv svc mask fw-update-service
tv vconf get db/appfw/startup_appid
tv app launch com.samsung.tv.cobalt-yt
```

## When something looks broken

- `agent_alive: false` → `tv agent start` (needs one root acquisition, ~60 s, and reports a timeout
  even when it works — check `tv status` after).
- Commands queue forever → `tv agent reset` clears stale entries, then retry.
- TV unreachable on 8001 → it is off/standby or the screen is off; `tv wake` (WoL) may not bring it
  back — see rule 14.
- `tv status` reports `root_ok: false` while `agent_alive: true` → the status probe is unreliable right
  after a boot. The watchdog log's `acquisition OK` line is the authority, not that JSON field.
- Everything slow after a reboot → the watchdog is still arming root and applying state. The apply runs
  as four chunks, one acquisition each, so "apply END" lands ~155 s after power-on; slow, not stuck.
