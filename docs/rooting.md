# Rooting assessment for a retail Tizen TV

## Bottom line

Retail firmware has no supported root path. `sdb root on` is denied, and developer mode exposes only a fixed app-management channel. Public research root is a two-stage chain: an sdb-side flaw yields a low-privilege service account, then a userland technique turns that into full system privileges. It is **volatile** — lost on reboot and reacquired from a host — and it depends on a bug Samsung can patch at any time.

Do not reproduce the chain from memory. Use the published research repositories and read their warnings. This file covers the decision (is root worth it), the host-side harness that drives a published chain safely, and where each kind of change lands.

## The hole is a published vulnerability

The archive-launcher chain this repo uses is **command injection in the SDB service**. Bishop Fox
documented it as *"Arbitrary Command Injection — affected versions through 9.0"* in their Tizen
advisory: [Samsung Tizen OS | Version Through 9.0](https://bishopfox.com/blog/samsung-tizen-os-version-through-9-0/).

Three consequences worth stating plainly:

- Every root chain in this repo rides that bug. If Samsung patches SDB in a future build, the
  toolkit stops working — the TV goes back to stock and the removals stay removed (they are files),
  but nothing new can be cut.
- **Blocking OTA keeps the hole open.** That is the point of the OTA policy in this project, and it
  is also the reason the kit still works years later. It is a deliberate trade, not an oversight.
- A patched build looks like a broken harness. Re-read the failure as "the vendor closed it" before
  debugging your own setup.

A second, independent chain has since been published for 2026 hardware
([DemonKingSwarn, *Breaking and Rooting a 2026 Samsung Tizen 9.0 Smart TV*](https://github.com/DemonKingSwarn/samsung-tv-tizen-root/blob/main/ROOTING-RESEARCH.md)):
`QA55QEF1AULXL`, Tizen 9.0.0, `T-RSLFUABC-0090-REL-202608061940`, SoC platform `rosel` — same
archive-route family, newer model year.

## Compatibility for a 2024 Q60D

- The set reports `T-NKLDDEUC-0090-2123.9`, which is **Tizen 9.0**.
- **Verified on a Q60D on this build:** the archive route returns `uid 0` / `euid 0`, `cap eff: 0000003fffffffff`, and reports `system files unchanged: yes`, `staging cleaned: yes`. Kernel 5.4.249, `armv7`, `/usr/bin/bash` present, `/opt` with roughly 1 GB free.
- A 2024 Q65D on the same `T-NKLD…-0090-2123.9` build base reported a working root agent too, so this build base does not look patched.
- Still **one OTA away from gone**: an update rewrites the entry point. Re-verify after every firmware change and read a later failure as a patch, not as a broken harness.
- There is no passive test: even the published preflight checks execute the first stage. If the goal is research only, stop at `capability`.

## Power gating: what proves the TV is awake

- `26101` (`sdbd`) answers in **standby**; `8001` (REST API) answers only with the **screen on**. A reachable `26101` therefore never proves the TV is on, and the harness's API step fails as a bare `curl: (7)` that reads like "developer mode is off".
- Wake it: read the MAC from `ip neigh`, send a WoL magic packet to both the TV address and `255.255.255.255` on ports 9 and 7, then poll `http://<tv>:8001/api/v2/` for up to ~60 s. On a wired set this returns in well under a minute and removes the false negative.
- `developerMode` and `developerIP` can only be read once 8001 answers, and `developerIP` must equal the `src` that `ip -4 route get <tv>` reports — check that before running any acquisition.

## The untethered fork

`levkropp/samsung-tv-root-untethered` is a fork of the main research project. It adds a boot agent that reacquires root on the TV at every boot, a token-gated sdb relay so external tools survive Host PC IP being set to `127.0.0.1`, and a module system for service masking.

Limits: proven end-to-end only on a 2022 Q60B / Tizen 6.5. It needs an **initial root session to deploy**, because it overwrites a system app and edits the package database — it is not a from-stock bootstrap. It pins Host PC IP to `127.0.0.1`, has no releases (build from source), and is a small research fork. Research-grade, not a first attempt.

## Host-side harness (install, drive, re-arm)

The model-agnostic route is the only one worth pointing at an unlisted set (a Q60D-class TV is neither of the supported models). Nothing here changes the TV until a root command is actually executed.

**Install.** Use the GitHub **release tarball for the host arch**, not a source build: releases carry prebuilt .NET payloads, so root commands work with no .NET SDK and no GNU Make (a source checkout needs `make common-payload qn90b-payload qn90f-payload` and .NET 6). Verify the published `.sha256` first. `doctor` is read-only and reports payload readiness per family — a green `doctor` is the cheapest proof the harness is complete.

**Config schema.** `config init` writes a file that must contain at least one `[televisions.<name>]` table with `model` limited to the supported model ids. The archive route ignores profiles entirely and takes the host as an argument, so on an unsupported model the profile is a schema filler — say so in a comment, and set `root_on_presence = false` so nothing arms itself on presence.

**Per-call root.** `archive-root root <host> --command '<cmd>'` is root-on-demand: the chain runs (~10 s), the command runs as uid 0, then everything is torn down and the TV is stock again. There is no persistent session. `archive-root probe` is *not* passive — it performs the whole acquisition.

**Wrapper preflight order** (each step returns its own one-line fix, so a failure never surfaces as a bare sdb error):

1. `ping` — off, standby, or changed IP.
2. `http://<tv>:8001/api/v2/` — `developerMode` must be `1`.
3. `developerIP` must equal the source IP the kernel routes to the TV with (`ip -4 route get <tv>`); if not, print the TV-side menu path instead of acquiring.
4. `sdb connect` + `sdb devices` must list `<tv>:26101`.
5. Only then run the tool, tee'd into a log with a timestamp and exit code per attempt.

**After-boot re-arm.** Root dies with the TV. A host watchdog that polls `api/v2` `PowerState` and runs one verification command (`id -u`, expecting `0`) per off→on transition keeps a later real command from being the first thing to discover a firmware patch. Poll the REST API, never sdb reachability: `26101` answers in standby, so an sdb-based watchdog fires on a TV that is not actually on. Gate it behind an explicit flag (e.g. `AUTO_ACQUIRE=0` in `/etc/default/<svc>`) and default it off: auto-rooting on presence turns the TV into a standing LAN root service, which is exactly what the risk section warns against. Also cap attempts per power cycle and do not loop — sdb wedges after a handful of operations and needs `sdb kill-server` or a TV reboot.

**Re-arm is also the state applier.** The only configuration worth owning is the set of changes the firmware resets: runtime masks, registry flags and prefs. Prove each one actually resets before promising it persists — a measurement made after a power cycle is the evidence (e.g. a preload preference silently returned to `true` and had to be re-applied). Pattern on this host: `tv-root-apply` (idempotent, `--dry-run`, `--only home,memory,privacy,ota,voice`, one acquisition per run, one `ITEM|group|name|state` line per change), `tv-root-revert --group` (restores registry flags with `ATTACH` against a baseline DB copy), `tv-fw-check` (vendor-page build compare), all driven from the watchdog with `AUTO_ACQUIRE=1` + `APPLY=1`. A second run reporting `changed` for an item means the check is broken, not that the change was needed twice.

**systemd pitfall.** A `ReadWritePaths=` entry under `/run` fails the unit at start with `status=226/NAMESPACE` when the directory does not exist yet (it is created only *after* the namespace is set up). Create it with `RuntimeDirectory=` (or `StateDirectory=` for `/var/lib`) instead of listing it in `ReadWritePaths`.

## Driving the per-call route

- **One plain command per call.** Each call passes a single argv string through host → TV shell → sdbd; a nested `sh -c "… | sed s/ .*// …"` gets its quoting mangled and returns `unterminated 's' command`. Run the bare command, write its output to a host file, and parse in Python on the host.
- Budget ~15–25 s per acquisition (the reference's ~10 s is optimistic on an armv7 set). Batch reads into one call only with a genuinely self-contained command; never build nested quoting to save a round trip.
- **No helper scripts on the TV: every unsigned file is refused for execution.** `sh /tmp/x.sh`, `sh /opt/usr/share/x.sh` and `sh /home/owner/share/tmp/sdk_tools/x.sh` all fail with `[uep][bash] the file is NOT signed`, and piping a non-trivial script into `sh` fails too. Ship the work as **one inline command** joined with `;` (a ~6.5 KB command string works); a file is only usable when an interpreter *reads* it — `echo <base64> | base64 -d > /tmp/x.sql; sqlite3 <db> < /tmp/x.sql` is fine, executing it is not.
- **`sdb push` is refused** on retail sets (`You cannot push files to this path`, after a 100 % "pushed" progress bar that is a lie). For small text (SQL, keys) base64 through the root command is the transport; for anything larger, do not chunk it — the set ships `curl` (with `openssl`, `scp`, `sftp`), so serve the file from the host over plain HTTP and `curl -o` it inside one acquisition.
- **Do not trust `sed -i` on the TV.** It can exit 0 and leave the file byte-identical with no error, so "the patch applied" is a lie you only catch with `md5sum`. Round-trip instead: `base64 -w0 <file>` → edit host-side in Python → `echo <b64> | base64 -d > <file>` (truncates in place, so ownership survives) → prove it with `md5sum` plus a `grep -o` of the field you changed.
- **A statement that needs quotes goes into a file on the TV, not into the command string.** Inline SQL loses its quotes between the layers. Write it with octal quotes instead — `printf "UPDATE t SET c=\047X\047 WHERE k=\047Y\047;\n" > /tmp/q.sql` — `cat` it to prove the quotes landed, then `sqlite3 <db> < /tmp/q.sql`.
- Prefer a bare `sqlite3 <db> .dump` (no quoting, and it doubles as the before-picture) when you want a whole table. **`.dump <table>` can print nothing and still exit 0**, which reads as "the table is empty" — it is not a subset filter you can trust. Confirm any "empty" answer with an explicit `SELECT count(*)` fed from a SQL file before concluding a table has no rows.
- **The tool's own verdict is the safety signal:** `uid`/`euid`/`gid` = `0`, `cap eff: 0000003fffffffff`, `system files unchanged: yes`, `staging cleaned: yes`. Report that set; absence of errors is not evidence.
- Output arrives under `commands:` with `exit code`, `timed out`, `stdout`, `stderr`. A non-zero `exit code` is the *command* failing, not the acquisition — read it before blaming the chain.
- **Never `pkill -f` a string that also appears in your own command line** (`pkill -f 'sdb start-server'` inside a script that contains that text kills the shell running it). Call `sdb kill-server` directly, or anchor the pattern.
- **Do not stop UI, streaming or input services, and do not reboot, while someone is watching.** Persistent state only in that window: registry flags, prefs, masks, DB rows. Defer `systemctl stop`, `--now` masks, DNS reloads and cold-boot verification to a window the owner gives you, and say which items you deferred.
- Service inventory for mask planning: one call of `systemctl list-units --type=service --all --no-pager --no-legend` yields ~380 units; extract `[\w.@:-]+\.service` and filter `adagent|preview-updater|analytics|voice|bixby|gamebar|fw-update|vdca-update|was-background-update|bootmode-system-update|shop|health`. Mask one candidate at a time, reboot and test between.

---

Continues in [`rooting-operations.md`](rooting-operations.md): database map, Home-key rebinding, OTA blocking, runtime masking, remote access, and the risk rule.
