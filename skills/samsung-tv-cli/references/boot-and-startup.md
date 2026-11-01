# Boot, startup queue and first-screen behaviour

How a cold boot actually spends its time on this set, how to measure it honestly, and what is safe to
cut. Read this before promising "faster boot" or "boots into the launcher".

## Measure the launcher, not the API

- Port **8001 answers ~35–43 s** after power-on, boot logo still on screen. It is a bootstrap
  milestone. Polling it is how you conclude "no change" while the owner sees one.
- The metric that tracks what a person feels is the launcher's own start offset, in seconds since
  kernel boot:
  ```bash
  tv run 'p=$(pgrep -f "^/opt/usr/apps/FreeMyTVio/" | head -1); awk "{printf \"%.1fs\n\", \$22/100}" /proc/$p/stat'
  ```
  Field 22 of `/proc/<pid>/stat` is starttime in clock ticks since boot; `/100` gives seconds.
- Cross-check the whole chain with the watchdog log (`/var/log/tv-root/watchdog.log`) — power-on,
  sdb reattach, acquisition, launcher, apply and agent each get a timestamped line.
- There is **no `systemd-analyze`** on this firmware. `systemctl show -p
  ActiveEnterTimestampMonotonic --value <unit>` is the per-unit equivalent (µs since boot).
- Boot-to-boot variance is real: the same configuration measured 134 s, 146 s and 173 s to launcher
  across reboots. Sample more than once before claiming a win or a regression.
- **Measure memory idle, never during playback.** Streaming pins decoder buffers: the same set read
  ~230 MB available while a video was playing and ~540 MB idle, which looks like a catastrophic
  regression if you quote it. Check `tv apps` for a video app — or just ask whether anything is playing
  — before reporting RAM, swap or CmaFree.

## The startup queue (what the boot waits behind)

Every offset below is seconds after kernel boot, measured with an idle, normal boot:

| offset | process | MB | verdict |
|---|---|---|---|
| 7 | csfs (app framework) | 83 | keep |
| 41 | art-app (Art Mode) | 53 | **disable** |
| 48 | home.media | 111 | keep until tested |
| 52 | pisa-service | 9 | **disable** (assistant) |
| 68 | sso-service | 12 | keep (login) |
| 70 | comss | 11 | **disable** |
| 73 | welcome-mode | 7 | **disable** (setup wizard) |
| 79 | webappservice | 12 | keep (web apps/store) |
| 86 | csf-content-eng | 5 | **disable** (promo engine) |
| 87 | vd-sc-client-se | 9 | test first |
| 88 | smartthings-cli | 12 | **disable** (no sensors) |
| 91 | key-manager | 7 | keep (keystore) |
| 92 | pushd | 9 | keep (notifications) |
| 94 | efl_webprocess | 11 | keep |
| 95 | health-mde-serv | 6 | **disable** |
| 96 | mcf-agent | 8 | **disable** (MultiControl) |
| 104 | function-osd / samsungcloud | 20 / 10 | keep OSD, disable cloud |
| 110 | sfpmd, psa-init, aifw-data-manag, NW-Daemon | 3–6 | keep (security/network) |
| 121 | context-aware, awm-app | 7 / 3 | **disable** |
| 124 | audio-share | 6 | test first |
| 127 | contents-cognit, devicetracker | 10 / 9 | **disable** |
| 130 | multiscreen | 32 | **disable** |
| 136 | easysetup | 17 | **disable** (setup done) |
| 138 | sesd | 6 | test first (USB storage) |
| 142 | smartthings-thi | 8 | **disable** |
| ~145–173 | **FreeMyTV (the Home app)** | 103 | the thing being waited for |

Sum of the "disable" rows ≈ 200 MB and ~15 queue slots ahead of the Home app.

## The first screen cannot be chosen from userspace

Tested and rejected, so a future session does not re-derive it:

- `db/appfw/startup_appid` = **last app used**, and the framework **rewrites it at shutdown** — set it
  to the launcher and the next boot that used the HDMI input flips it back to `org.tizen.tv-viewer`.
- The appsvc `operation/main` row is the **Home key**, not the first screen.
- Every launch route is auth-gated: `/api/v2/applications/<id>`, `/ws/apps/`, `/apps/<name>` all return
  **401**; only `/api/v2/` (device info) is open; DIAL on :56789 is closed.

What actually helps: the watchdog's `ensure_launcher` step launches the Home app as soon as one root
acquisition succeeds, and cutting the queue makes the framework reach it sooner. Until then the set
sits on whatever input was last used.

## Boot-time root acquisition is fragile by nature

`archive-root` confirms execution with a timing oracle (a `control` command vs a 2 s sleep probe). On a
cold boot the control probe itself takes ~0.75 s, the delta collapses, and the tool reports
"package-name shell execution was not confirmed" — even though sdb is attached and the TV is healthy.
A single attempt at power-on therefore ends with **no apply pass and no agent**. The watchdog settles
30 s after power-on and retries up to 4 times, 25 s apart; that is the difference between a silent
failed boot and a working one.

## Tier A service pass (systemd units, masked)

`systemctl show -p RequiredBy` is empty for all of these — nothing hard-depends on them. Masked
`--runtime` and held in `PERF_UNITS` of `tv-root-apply`, so the perf group restores them every boot:

`swu-auto-upgrade` (the OTA pusher, ~285 s), `reporterCA`, `emergency-log-transmitter`,
`pvod-appfw.pvodservice`, `wireless-cam-service`, `wifi-presence`, `mirroring-recognition-manager`,
`ambient-ua-agent`, `pisa-service`, `nagsam-daemon`, `ua-manager`.

Two units that look like they belong and do not: `aaa_tvs_deamon` (breaks Prime — see the rule below) and
`registertv-service` (static, so it was never masked in the first place).

**NEVER mask `aaa_tvs_deamon`** — masking it breaks Prime Video: the app opens fine, then every video
fails with "Something went wrong. Please try again later. For more help, go to amazon.de/Videohilfe".
Nothing in the unit name suggests DRM, no dependency declares it, and the no-journal build gives no
logs — it was found only by boot bisect. The live list now lives in `/etc/tv-root-perf-units`
(override read by `tv-root-apply`), with `aaa_tvs_deamon` excluded and the reason written at the top.

**Bisect with boots, not live masks.** Masking a unit at runtime while the TV is up does not reproduce
the failure: an already-acquired licence keeps playing, so a live test reports "plays" even when the
unit is the culprit. Only a power cycle with the unit masked at boot shows the break, and starting the
unit late does not fix it either — the state it sets up is established at boot.

**`data-service` cannot be stopped** — it is `static` and D-Bus activated
(`TriggeredBy: org.tizen.tv.dataservice.busname`), so it respawns within seconds of a `stop`. Removed
from the ad-service kill list rather than left in as a fake win.

**Do not mask `dta-agent`** — "Install cdm library and TA for downloadable app": it installs the
DRM/CDM trusted application, and Prime Video playback is the thing that breaks.

**`tv svc mask` must also `stop`, and must escalate to `SIGKILL`.** Masking a running unit leaves it
running, so the verb looks like a no-op printing `active`. Worse, several Samsung units ignore SIGTERM
and sit in `deactivating` indefinitely with the process still alive — `wireless-cam-service` and
`mirroring-recognition-manager` both did. Verb and boot applier now do mask → stop → wait 2 s →
`systemctl kill -s KILL` on anything still `active`/`deactivating`, then report the real state; a
`failed` result there just means the stop returned non-zero, the unit is masked either way.

**A static unit cannot be masked.** `systemctl is-enabled` returning `static` makes `mask` a silent
no-op: `registertv-service` sat in the kill-list reporting `changed`/`ok` while still running the whole
time. Check `is-enabled` for every unit you intend to mask and drop the `static` ones from the list
instead of trusting the item line.

**Playback (DRM) failures are bisected by cold boot, and the culprit is a service.** Resolved on this
set: `aaa_tvs_deamon` (see the NEVER-mask rule above). Repeat the sequence that found it, and expect it
to cost ~4 min per round — power-on, 30 s settle, ~18 s acquisition, ~40 s apply:

1. **Baseline first**: one boot with none of the masks applied, and play a DRM title. If it fails in
   that state too, the cuts are innocent and bisecting them is wasted work.
2. **Halve the list per boot**, playing a title between boots. Do not batch-cut and do not bisect on a
   live set.
3. **Argue from the bisect, never from unit names.** `aaa_tvs_deamon` reads as "TV service daemon",
   declares no dependents, and none of its siblings matter; a name-based guess would have cleared it.

Two tests that each produced a **wrong** answer before the bisect: restoring the services without a
cold boot (an already-acquired licence keeps playing, so it looks innocent), and blaming Developer Mode
(it was on for the whole period the set played fine — the owner ruled it out from direct experience, and
should be believed over a debloat doc's warning).

**`sdbd.service` starts ~121 s in** — the reason boot-time root acquisition fails the timing oracle
(control 0.75 s vs delay 2.1 s) even when sdb is attached. Settle and retry; do not conclude the
exploit is broken.

## Applying the cuts

**Validate the generated shell before sending it.** `tv-root-apply` builds one ~13 KB compound command;
a quoting mistake in it (`done; && echo`) makes the remote shell fail with no `ITEM|` lines, and the
applier then reports "acquisition or remote command failed" — which reads like a root/dependency problem
rather than a syntax error in your own edit. After editing an apply group, generate the command and run
it through `bash -n` locally before letting the watchdog use it:
```bash
python3 - <<'EOF'
import subprocess, importlib.util
ns={"__name__":"notmain"}; exec(compile(open("/usr/local/bin/tv-root-apply").read(),"apply","exec"),ns)
cmd=ns["build_command"](list(ns["DEFAULT_GROUPS"]),False)
r=subprocess.run(["bash","-n","-c",cmd],capture_output=True,text=True)
print(len(cmd), "OK" if r.returncode==0 else r.stderr[-300:])
EOF
```
**Send the apply in chunks, not one 13 KB command.** A single compound command of that size is only
partially executed: `home`/`memory`/`perf` ran while `privacy`/`ota`/`voice` silently did nothing and
emitted no `ITEM|` lines (so the applier still reported success). `main()` now splits groups into
commands under `MAX_CHUNK = 4000` chars and re-acquires per chunk — six groups become four chunks in
~42 s, and every group reports again. Symptom to recognise: item counts that look right for the first
and last group but missing in the middle, plus a service you expected stopped still being `active`.

A failed apply is silent on the TV side too: runtime masks from the previous boot are gone, so the set
quietly comes back fully bloated while the log only shows one FAILED line.

**The kill-lists are plain files, so bisecting needs no code edit.** `/etc/tv-root-perf-units` (unit
masks) and `/etc/tv-root-kill-procs` (process patterns) are read at the start of every apply; write them
from `execute_code` with plain `open()` because the `write_file` tool refuses paths under `/etc`, and
keep the reason for each exclusion in a comment at the top — the next session reads that file first.

Disabling the *app records* handles the framework-started ones (`tv boot onboot <app> off` plus
`app_disable`), but daemons owned by systemd need `systemctl mask --runtime` + stop, and both kinds must
live in an apply group so the read-only rootfs gets them back after every power cycle. Measure available
RAM, swap and CmaFree before and after each batch — swap is the number that tracks how the UI feels.
