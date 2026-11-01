# AGENTS.md — how an AI agent should work in this repo

You are an agent handed this repository. Your job is **not** to follow a script blindly. Find out what
the TV in front of you actually is, propose the smallest safe change, prove it with real output, and
then tell the human exactly what to do — or what you already did.

Read this file completely before running anything.

---

## 1. Read order

1. `agent/manifest.json` — machine-readable facts: entry points, invariants, restore points.
2. `agent/playbooks/` — the task shape you probably need.
3. `docs/` — the reasoning behind the rules (why a unit is load-bearing, how boot actually behaves).

Do **not** read the whole repo into context. Manifest + one playbook is normally enough.

## 2. Discover before you act

Two entry points, in this order, and they answer different questions:

| Command | Answers | Needs |
|---|---|---|
| `./scripts/tv-doctor.sh` | *Can this host act at all?* (TV reachable, Developer Mode, whitelisted IP, sdb, root chain, watchdog) | nothing on the TV |
| `./agent/audit.sh` | *What is the TV's current state?* (units down, apps alive, memory, launcher offset) | a reachable TV |

If the doctor fails, fix that first — an audit over an unreachable TV tells you nothing.

**Paths of the same name live on different machines.** `/etc/tv-root-perf-units` and
`/etc/tv-root-kill-procs` are on the **host** and are writable. The TV's `/etc` is read-only; the only
thing written on the TV itself is unit *runtime* state (`/run`), app directories, and the package DB.

One discovery step, first:

```bash
./agent/audit.sh            # JSON on stdout, read-only, safe to run any time
```

It reports host settings, TV reachability, whether root is held, which units are masked, which app
processes are still alive, memory, and launcher timing. Everything after this is a decision made from
that JSON, not from assumptions.

If `audit.sh` says the TV is unreachable, stop and say so. Do not attempt changes over a flaky link.

## 3. Hard invariants

Load-bearing on this platform. Violating one produces a failure that looks like a network or account
problem, with **no logs to help you** (§7).

| Never touch | What breaks | How the human notices |
|---|---|---|
| `aaa_tvs_deamon` | Prime Video / PlayReady licence path | App opens, every video fails: *"Something went wrong. Please try again later."* |
| `com.samsung.tv.home.sidebar` + `com.samsung.tv.contentservicemanager` | Quick-settings panel data | Panel opens, every control reads *"Preparing… Please try again later"* |
| `dta-agent` | CDM/PlayReady trusted application install | DRM playback dies for a few MB saved |
| `sdbd` | The root transport itself (starts ~121 s into boot) | Root acquisition fails; nothing applies |
| `FreeMyTVio.*` / configured home app | The launcher the human uses | Home key shows nothing or a blank screen |
| `com.samsung.tv.csfs` | Core content framework | Broad instability, UI won't settle |

Never change more than **one** variable per verification cycle. One unit, one app, one reboot.

## 4. The bisect protocol (core method)

**Live changes prove nothing.** Stopping a service while the TV runs does not reproduce breakage — an
already-acquired licence or an already-rendered panel keeps working, so a live test reports "fine" when
the removed unit is the culprit. Starting a unit late does not repair it either: the state is
established at boot.

The only valid test:

1. Change exactly one thing (mask a unit / move one app dir / edit one list file).
2. Reboot, wait for the full apply chain to finish.
3. Verify the *state* (unit inactive and masked, dir gone, memory) **and** ask the human to exercise
   the feature.
4. If it broke: revert, reboot, re-verify, record the fact.

Bisecting a lost feature: restore in halves, not one-by-one guessing, and restore the most recent
change first — that is where the regression usually is.

Preferred undo is the script, on the host: `./restore.sh --list`, `./restore.sh --app <appid>`,
`./restore.sh --all --yes`. The manual equivalent runs on the TV: move the directory back from
`/opt/usr/share/tv-root-backups/<change-set>/` into `/opt/usr/apps/`, then
`UPDATE package_app_info SET app_disable='false', app_autorestart='true' WHERE app_id='<pkg>'` against
`/opt/dbspace/.pkgmgr_parser.db`, then drop the matching line from `/etc/tv-root-kill-procs` on the host.

## 5. Verification contract

A change is done only when all three are observed, not assumed:

- **State** — unit `inactive|failed` and `masked`; or app dir gone with no matching process. Use a
  *bracketed* pattern so `pgrep` cannot match your own command line (§7).
- **Persistence** — it survived a cold boot. Runtime masks do **not** survive power-off by themselves:
  the host watchdog re-applies them at each power-on, so what you verify is that the apply ran again and
  reported the line again. Read `/var/log/tv-root/apply.log` on the **host** (there are no logs on the
  TV) and require `END changed=… errors=0`.
- **Function** — the human confirmed the features they actually use (app screen, inputs, settings,
  playback). Without a human in front of the TV this gate cannot pass: say so rather than implying it did.

Power-cycling remotely: `tv power off` then `tv wake` (Wake-on-LAN; needs `TV_MAC` in
`/etc/default/tv-root`). `tv wake` brings the TV back from standby, which is enough for persistence
testing. A true mains-off cold boot needs a person, or a smart plug.

Report raw numbers you measured (MB available, swap, CMA, running apps, launcher offset). Never say
"memory improved".

## 6. What you tell the human

End every working turn with this structure, plain language, no filler:

```
Diagnosis   — what is going on, one or two sentences.
Evidence    — exact commands/output that prove it (command, number, file:line).
Change      — what you did or propose, and the single variable it touches.
Risk        — what breaks if this is wrong, and the symptom they would see.
Rollback    — the exact command/path to undo it.
Your turn   — what they should check or press, if anything.
```

If you need a decision, ask at most one question and make the recommended option obvious. If you
cannot verify something, say so instead of claiming success — an unverified claim is worse than a
known gap, because the human will trust it.

## 7. Platform traps that will waste your turn

- **There are no logs.** `journalctl`, `dlogutil`, `/var/log/dlog` are empty on this firmware. Do not
  burn turns hunting them; bisect instead.
- **`pkill -f` / `pgrep -f` match your own command line.** Bracket the pattern
  (`org[.]tizen[.]art-app`) or anchor on a path segment your command does not contain. A sloppy
  pattern kills your shell mid-script (exit 143, truncated output).
- **UEP blocks unsigned scripts even as root**: `sh /tmp/x.sh` → `[uep][bash] the file is NOT signed!!`.
  Ship work inline, or as data fed to a signed interpreter (`sqlite3 db < file.sql` is fine).
- **One huge command executes only partially.** A ~13 KB compound command ran its first and last
  groups while silently skipping the middle, with success exit status. Keep generated commands under
  ~4 KB, parse per-chunk `ITEM|` lines, and `bash -n` the string before sending it.
- **REST API is not boot.** `/api/v2/` answering early means nothing to a person waiting for a
  picture. Measure the launcher start offset from `/proc/<pid>/stat` field 22.
- **`systemctl mask --runtime` does not stop a running unit.** Mask *and* stop; some units ignore
  SIGTERM and sit in `deactivating` forever, so escalate to SIGKILL.
- **`launchpad-process-pool` restarts apps** regardless of `app_disable`; moving the app directory is
  what makes a removal stick.
- **`data-service` is D-Bus activated** and respawns instantly — a `stop` there is a fake win.

## 8. Ethics and scope

Owned devices only. Never touch firmware, never attempt to bypass content protection, never remove
something the manifest marks required just to save memory. Every removal must be reversible with its
restore point documented before the change, not after.
