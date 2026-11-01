---
name: samsung-tizen-tv
description: "Use when auditing, debloating or modding a Tizen TV. Component of the tizen-lite skill."
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
    tags: [samsung, tizen, smart-tv, debloat, sdb, homebrew, sideload]
---
> **Component skill.** The umbrella skill for this project is `tizen-lite` — it carries the
> load-bearing list, the boot-bisect protocol and the report format. Load it first.


# Samsung Tizen TV: audit, debloat, modded apps

## When to Use

Use when a Samsung Tizen TV needs auditing, debloating, app cleanup, or sideloading of modded apps; when `sdb` cannot connect or a package install fails on certificate errors; or when planning privacy and DNS changes for a smart TV. Applies to retail 2018–2026 sets; developer units and pre-2019 firmware behave differently.

## Core rules

1. **Read-only until explicit approval.** In a research/plan phase do not install, uninstall, change TV settings, or change AdGuard. Downloading the standalone `sdb` binary to the host is host-only and acceptable once the user asks to enumerate apps; it changes nothing on the TV.
2. **Inventory first, per-app confirmation always.** When asked to debloat, present the installed-app list with sizes and use counts, then wait for the user's keep list. Never bulk-uninstall and never infer consent from "debloat it".
3. **Never handle Samsung account credentials.** Certificate creation needs the user's own OAuth sign-in in their browser; do not type or accept a password or code.
4. **State the real gain.** Removing apps frees storage, not CPU. Perceived speed comes from the startup/home path and from skipping Smart Hub, not from deleting packages.
5. **Developer mode is a live attack surface.** `sdbd` listens on 26101 and trusts the whitelisted source IP; the sdb package-name parser has had command injection. Keep it on only while working, then turn it off.
6. **Never touch the service menu.** Panel type, tuner region and software model entries can leave the set without a picture or tuner; the service-menu factory reset also wipes usage history. No consumer recovery exists for a damaged bootloader.
7. **Never blanket-block Samsung domains.** Blocking `samsung.com`, `samsungapps.com` or the cloud-solution hosts breaks the store, login, SmartThings and streaming. Block explicit ad/telemetry hosts only.
8. **OTA is one-way, and its handling is the owner's standing policy — not a fresh judgement call each session.** A firmware update restores preloads, can clear developer mode and wipe sideloads, and Samsung offers no downgrade. This owner's policy: keep OTA blocked, re-check the vendor page for a newer build roughly every six weeks, and install only a *major* change (Tizen platform bump, a documented security fix, or a feature the owner asked for). A build-only increment is not a reason to give up root. Never let an update happen as a side effect of another task, and have the USB image on hand before allowing one.
9. **Terse follow-ups refer to this project's own plan file.** TV work spans sessions, and the current plan lives in `~/.hermes/plans/*tv*` with a trailing *Update* section; earlier sessions hold the decisions behind it. Read the newest plan before acting on a bare "install those things" / "do the next step", and when a later decision overturns a plan line, state which line changed instead of silently following the stale one.
10. **Never disturb what is on screen.** While the owner is watching, apply only state that the next boot or the next event picks up — registry flags, prefs, masks, DB rows, files. Defer `systemctl stop`, `--now` masks, DNS filter reloads, reboots and cold-boot verification to a window the owner hands you, say which items you deferred, and never restart the UI or an input service to "make a change take effect".

11. **Prove playback after every debloat item, not after the batch.** Masking a batch of telemetry/unused units at once broke Prime Video (generic "something went wrong") and left nothing to bisect. One item at a time, then the owner plays a DRM title before the next one. DRM on this platform spans `dta-agent` (CDM install), `license-manager-agent`, `registertv-service` and Samsung's CA reporting, so a unit whose name reads as pure telemetry can still be load-bearing for streaming.
12. **Never power the set off remotely without someone standing next to it.** `tv power off` is a standby request — it returns `power: on` and leaves uptime unchanged — and a real cycle (`tv root 'sync; poweroff'`) did not come back from a WoL magic packet; the owner had to press the button. Prefer `tv run 'reboot'`, which returns by itself, and when a step must leave the TV dark, say so before doing it.

## Phase 0 — identify and connect

- Discover the TV: `arp-scan -l | grep -i samsung`, then confirm identity with the unauthenticated REST API:
  `curl -s http://<tv>:8001/api/v2/` → `device.modelName`, `device.developerMode`, `device.developerIP`, `device.PowerState`.
- Read the firmware build on screen (Settings → Support → About This TV). The API's `firmwareVersion` returns `"Unknown"` on retail sets, and `sdb` does not expose the build string.
- Do not infer the Tizen version from the model year or the owner's recollection. `capability`'s `platform_version` is authoritative for the firmware actually running: 2024 models have received Tizen 9 over the air, so a Q60D can report `9.0` while the owner believes it is on 8. Use the on-screen `T-…` build only as confirmation, and let the reported version decide the TizenBrew/TizenTube path.
- Install the standalone **sdb** (~3 MB, host-side only; it changes nothing on the TV). Never Tizen Studio (~1.8 GB), never distro/AUR sdb packages — they are years behind and fail against Tizen 7+. Resolve the current file and its SHA-256 from `.../tizenstudio/official/pkg_list_ubuntu-64` (`Package : sdb`, `Path : /binary/sdb_<ver>_ubuntu-64.zip`, `SHA256 :`) and verify before installing: the `/binary/` directory index lists filenames that 404. Recipe: `references/sdb-audit.md`.
- **Read `device.developerIP` from `http://<tv>:8001/api/v2/` before blaming the network.** It names exactly one host; if it is a *different machine* than this one, `sdb connect` fails outright ("failed to connect") and no route change helps — the fix is on the TV (Apps → App Settings → `12345` → Developer mode → host IP) plus a power-cycle. A wrong *route source* is the other failure mode and looks different (handshake dies after connect). `scripts/tv-preflight.sh <tv-ip>` reports both in one shot.
- **Port 8001 is the power signal; 26101 is not.** The REST API only answers while the screen is on, but `sdbd` also answers `26101` in standby — so a reachable `sdb` port never proves the TV is awake, and the API step fails as a bare `curl: (7)` that reads like "developer mode is off". Wake the set first (WoL magic packet to the MAC from `ip neigh`), then poll `http://<tv>:8001/api/v2/` for up to ~60 s before connecting.
- **Pin the source IP before connecting.** Developer mode whitelists exactly one Host PC IP. On a multi-homed host the route can leave via the wrong NIC even though both are on the same subnet:
  `ip route get <tv>` → if the source is not the whitelisted IP, `ip route replace <tv>/32 dev <iface> src <whitelisted-ip>`.
  Without this, `sdb connect` may report success while every command fails or hangs.
- Connect: `sdb kill-server; sdb start-server; sdb connect <tv>:26101; sdb devices`.

## Phase 1 — read-only audit

- `sdb -s <tv>:26101 capability` — record `platform_version` (Tizen major), `sdbd_plugin_version`, `sdk_toolpath`, and the permission flags. On retail firmware expect `intershell_support: disabled`, `sdbd_rootperm: disabled`, `rootonoff_support: disabled`. If any of those is enabled, stop and re-plan — that is an unusual unit.
- `sdb -s <tv>:26101 shell 0 vd_applist` — **this is the user-facing installed-app inventory**: title, package id, version, size, install date, `is_removable`, `use_count`. Use it for keep/remove decisions.
- `sdb -s <tv>:26101 shell 0 applist` — every package including services (~500). Never present this as "installed apps".
- `sdb -s <tv>:26101 shell 0 getduid` — the DUID needed for certificates later.
- `sdb shell` without the `0` prefix prints `closed`; that is expected. The `0` selects sdbd's fixed command dispatcher, not a shell and not root.
- Nothing else works on retail: no `ps`, `df`, `du`, `dlog`, no file pull. **There is no backup**; the captured package list is the only pre-change artefact.

## Phase 2 — debloat ladder (lowest risk first)

Do not skip to package removal. Layers 1–3 deliver most of the perceived benefit with no brick risk.

1. **Native delete (no tools, reversible).** Home → APPS → gear/Settings → select app → Delete. On 2018–2024 models most preinstalled apps can be deleted this way; e-Manual is excluded.
2. **Privacy / ACR.** General & Privacy → Terms & Privacy → Viewing Information Services = Off, Interest-Based Advertising = Off. German: Allgemein & Datenschutz → Nutzungsbedingungen & Datenschutz → Anzeigeinformationsdienste / Interessenbasierte Werbung.
3. **Startup path.** Turn off Autorun Smart Hub / Start with Smart Hub Home / Autorun Last App. This is the single most noticeable speed change.
4. **Disable, don't remove.** TV Plus, Gaming Hub (highlight → Down or hold OK → Disable), Bixby wake and voice. These return after a firmware update; re-disable manually.
5. **DNS filtering (needs approval).** Add a small ad/telemetry list — Samsung ads, ACR and Smart Hub promo/telemetry — then verify store, login, Netflix/YouTube and casting still work. Keep TV Plus re-download (`osb-*.samsungqbe.com`) and OTA (`otn*`) hosts in separate stricter tiers, added one host group at a time. AdGuard Home is shared infrastructure: every filter change is LAN-wide. Confirm which process owns `:53` before editing any resolver config, and stop the service before editing its YAML — AdGuard (and Pi-hole) rewrite their file on shutdown.
6. **sdb uninstall, last.** Only confirmed store/downloaded apps, one at a time, reboot and test between. Never remove `org.tizen.*` or `com.samsung.*` platform packages.
   - Pass the `app_package_name` field from `vd_applist` to `sdb uninstall`, not `app_id`/`app_tizen_id`. Generated packages use a 10-char prefix (`AprZAARz4r`) while the app ID is `AprZAARz4r.Jellyfin`; the full app ID returns `package is not in pkgmgr_info DB`.
   - `sdb` exits 0 even when the TV prints `failed` or `can not uninstall app`; parse the output text, never the exit code.
   - Locked preloads (`can not uninstall app`) and e-Manual cannot be removed over sdb; use the native Apps → gear → Delete path instead.

## Phase 3 — modded apps

- Every install is DUID-bound: Samsung author certificate + distributor certificate containing the TV's DUID, plus `device-profile.xml` pushed to the TV's `sdk_toolpath`. A valid certificate with a missing profile fails with `install failed [118,-12]`.
- A free Samsung developer account is enough; a seller account is only for store publishing. Partner privilege is needed for on-boot services and local-proxy apps.
- Check for an existing author certificate before minting a new one. A TV with prior sideloads already has a profile on the machine that installed them; reusing it preserves update rights for those apps and avoids another Samsung account. Ask for the existing `author.p12` and its password, back it up off-TV, and never accept the Samsung account password — the owner completes Samsung's OAuth page themselves.
- Back up `author.p12` and its password off-TV. A build signed by a different author cannot update an installed app — uninstall first.
- Installers: **Apps2Samsung** is the default for general `.wgt` packages, and its self-contained **CLI** runs headless on Linux (`apps2samsung-cli scan|catalog|installed|cert|install`). TizenBrew Installer is only for TizenBrew modules; avoid manual Tizen Studio unless debugging signing. See `docs/debloat-modding.md (repo)` for the exact sequence.
- **Headless certificate sign-in:** the first certificate opens a Samsung OAuth page whose callback is `http://localhost:4794/signin/callback`. On a headless host either forward that port from a desktop (`ssh -L 4794:127.0.0.1:4794 user@host`) and open the printed URL there, or create the profile on the desktop with `cert --prepare --duids <DUID>` (no TV connection required) and reuse its certificate store. `--no-browser` prints the URL; never ask for the account password.
- **Phone-only owner:** when there is no desktop, install the **Apps2Samsung Android app** and use it for scan → certificate → catalog or Custom WGT; the signing certificate then lives on the phone. Do not propose a Windows-only or desktop-GUI workflow. A custom `.wgt` such as AeroTizen's is unsigned and gets re-signed by the app. Remember the TV accepts sdb only from the Host PC IP, so it must point at the phone while that app installs.
- Tizen 9 is the breaking point for older homebrew: TizenBrew 2.x has an open Settings/`ERR_ACCESS_DENIED` bug, and TizenTube's local proxy suffers DNS failures. Tizen 8 is the well-trodden path. Install one app, reboot, test, then the next.
- Keep every original `.wgt` and the certificate profile; an OTA can remove or invalidate all of it.

### UX upgrade order (what actually helps)

- Replace the TizenTube **module** with the standalone **`TizenTubeCobalt.wgt`**: the module renders in Tizen's embedded Chromium, which is the stutter; the standalone uses Samsung's Cobalt engine. `reisxd/TizenTubeCobalt` is the Android/Fire TV repo — wrong package for a TV.
- On Tizen 9, proxy-based apps fail because Cobalt cannot reach `127.0.0.2` and the Node service's resolver hangs. The remedy is the **hostname** form, not the IP: upstream's proxy-address build sets `--proxy=http://tizentube:8101` and expects DNS to resolve `tizentube` to the TV's own **static** address. Pointing the proxy at `http://<tv-lan-ip>:8101` is not equivalent — it turns "something went wrong at the start of the video" into a freeze. **Verified working 2026-10-31 on a Q60D: AdGuard rewrite `tizentube` → TV IP, DB row switched to the hostname, reboot — ads gone and playback clean.** Recipe: `docs/debloat-modding.md (repo)`.
- **A modded app's launch arguments are database state, not package files.** The framework passes the cached `native.userdata` string from `package_app_app_metadata` (`md_key='http://samsung.com/tv/metadata/native.userdata'`) in `/opt/dbspace/.pkgmgr_parser.db`, so editing `config.xml` under `/opt/usr/apps/<pkg>/res/wgt/` changes nothing the launcher reads. Confirm any file edit with `md5sum` and a behaviour test before believing it landed.
- **A broken streaming app is not evidence about the debloat.** The standalone YouTube mod is an injector on top of Samsung's own Cobalt app, its service re-spawns after a kill, and registry flags only land at boot — isolate the wrapper from the platform (and mind `app_launcher -k` vs `-s`) before reverting anything. Recipe: `docs/debloat-modding.md (repo)`.
- **No `.wgt` can take the Samsung Home key on Tizen 9 — root can, and that is verified on a Q60D.** Watcher-mode launchers re-open a second after Home but cannot see Home pressed inside YouTube, Prime Video, Stremio or Spotify. With root the Home key is one row in the app framework's default-app registry (`/opt/dbspace/user/5001/.appsvc.db`, table `appsvc`, operation `http://tizen.org/appcontrol/operation/main`) pointing at an installed launcher's **app id**; it survives a power cycle, needs no certificate, and reverts with one `UPDATE`. Prefer a launcher already installed and purpose-built for it (Arn0 Launcher's own manifest states the Home mapping targets its app id) over shipping a new package. Recipe and caveats: `docs/rooting.md (repo)`. No-root launchers (AeroTizen, Free My TV) still change appearance only and add their own memory; Vetro/CleanFrame-class root launchers need a personal DUID-bound certificate and remain unverified on this set.
- Startup: Start Screen Options → turn off *Start with Smart Hub Home* and *Autorun Last App*; never autostart TizenBrew (it puts Chromium plus a Node service on the boot path). Device Care is the only built-in cache/RAM cleaner; Reset Smart Hub and factory reset are not speed fixes.
- Media clients: Moonfin or Litefin for Jellyfin, SamSUCKS for Plex. Skip Fladder, Flixor and Chorus2 — unmaintained ports that duplicate the others.
- There are no credible boot-time or navigation-latency numbers for Tizen sets. Report changes qualitatively and never invent seconds; the only hard figures are Game Mode input lag and Samsung's per-app memory caps.

## Phase 4 — root, only on explicit request

- The one-shot archive route is **verified working** on a Q60D / Tizen 9 (`uid 0`, `cap eff: 0000003fffffffff`). Retail root is real while the build stays unpatched — do not restate "retail has no root path" once it has been demonstrated on the unit in question. Assessment, compatibility, the untethered fork and the host harness: `docs/rooting.md (repo)`.
- Root is **per command and volatile**: it exists only for the duration of one `tv-root '<cmd>'` call (~15–25 s) and dies on reboot. There is no persistent session, so plan work as a sequence of discrete commands, not as an interactive shell session.
- **No unsigned native executable will run on this platform — UEP blocks it, and root does not bypass it.** A 936-byte static ARM probe, delivered with the TV's own `curl` and executed inside an acquisition at `uid 0` / `CapEff=0000003fffffffff` / SMACK `User`, died with `Operation not permitted` (exit `126`). So dropbear or any self-built binary is not a plan, and "put a static binary on `/opt` and run it" must never be proposed again. Exactly two doors exist: pipe the work into the signed `bash` (`cat x.sh | bash`), or let the signed `/usr/bin/dotnet` (Core **6.0.9** present) run a managed assembly, which UEP treats as data. Probe before planning: `scripts/uep-probe.sh <tv-ip> <host-ip>`; designs and device inventory: `docs/rooting.md (repo)`.
- Pass **one plain command** per call. Nesting `sh -c "…sed …"` gets its quoting mangled across the host string → TV shell → sdbd layers and returns `unterminated 's' command`; run the bare command and parse its output host-side.
- **Wrap the remote command in single quotes.** In a double-quoted `tv-root "…"` the *host* shell expands `$var` first, so a remote `for p in …; do … $p; done` arrives with empty variables and fails as a shell syntax error or a path-not-found on the loop body.
- **Never wildcard `/proc/*/cmdline` into the transcript.** One `cat -v` of it returns tens of thousands of characters covering every process. Read a single pid, or match narrowly: `grep -ao "proxy=http://[^ ]*" /proc/[0-9]*/cmdline | sort -u`.
- Cite the tool's own verdict — `system files unchanged: yes` and `staging cleaned: yes` — as the proof an acquisition left the TV stock. That pair, not the absence of errors, is what makes repeat attempts defensible.
- Get the matching USB recovery image onto the host before any change that is not trivially reversible (OTA blocking, system-app swaps). Individual service masks are reversible; an OTA is not.
- **Every root change is one item with a recorded before-value and a written inverse**, taken after a DB snapshot under `/opt/usr/share/tv-root-backups/`. Root is re-acquired per call, so there is no "fix it later in this session": each change has to be correct on its own or revertible on its own. Apply one item, verify it, then the next.
- The three state surfaces worth knowing before touching anything: default app per operation (Home key — the one proven rebind), `key_filter` rows (remote remapping: the brand buttons are `XF86Netflix` / `XF86Amazon` / `XF86Disney` / `XF86KeyTVPlus` owned by `org.tizen.function-osd`, while `XF86App1/2/3` are unbound on remotes that have those brand buttons; a row edit is **not yet proven** to change what a button does, so price a remap as an experiment with a physical press — and expect the owner's existing apps to be reachable enough that the answer is often "leave it"), and registry flags / unit masks (re-applied per boot on a read-only rootfs). Map and commands: `docs/rooting.md (repo)`.

### Instant commands instead of one acquisition per command (verified 2026-10-31)

`tv-root` costs ~10–20 s per command because every call re-runs the whole chain. When the owner's
complaint is that speed, build the relay instead — it needs no binary and therefore nothing UEP can
block:

- `tv-agent '<command>'` runs a command on the TV as **uid 0** and returns output in **~1 s** measured
  (0.94 s for `id -u`; 1.35 s for a multi-line command). `tv-agent --status` reports whether the TV
  loop is polling; `tv-agent --reset` clears a stale queue.
- Architecture: the TV runs one `bash -c` loop that polls `GET /cmd` on the the Linux host every second,
  executes the command, and POSTs the output to `/out`. **Nothing listens on the TV.** Host side:
  `tv-agent.service` (Python, `/usr/local/bin/tv-agent-server.py`, binds the LAN IP:8899, token in
  `/etc/tv-agent.token`), client `/usr/local/bin/tv-agent`, loop payload
  `/usr/local/lib/tv-agent/loop.sh`, starter `/usr/local/bin/tv-agent-start` (idempotent; the
  watchdog runs it after each power-on when `AGENT=1` in `/etc/default/tv-root`).
- **`socket.getfqdn()` blocks ~16 s on this host**, and `HTTPServer` calls it in `server_bind` — so a
  stock `ThreadingHTTPServer` binds but does not `listen()` for 16 s and every probe fails with
  "connection refused" on a service systemd calls *active*. Subclass it and set `server_name`
  directly to skip the reverse lookup.
- **A backgrounded long-lived child makes the acquisition report `TimeoutError` while the payload
  still runs.** `nohup … &`, `setsid … &` and `</dev/null` all behave the same: the launcher never
  sees its exit marker and the CLI retries. Treat the loop's poll status as the truth, not the exit
  code, and give the loop a self-dedupe (kill other instances matching its own command line, never
  `$$`) so retries cannot leave two loops.
- **A wedged sdb session looks exactly like a broken exploit.** `archive-root` failing at `probe`
  with `TimeoutError` while `sdb capability` still answers is a stale client session: run
  `sdb kill-server; sdb start-server; sdb connect <tv>:26101` before touching the TV or rebooting it.
- **`ps` alone will show phantom loop copies.** The loop forks constantly for `$(curl …)`, and a
  forked-not-yet-exec'd child briefly carries the parent's `cmdline`; count long-lived instances by
  `ppid` instead of by matching text.
- **A failed `apply` immediately after power-on is usually boot timing, not breakage.** Ten to sixty seconds after the set comes back, services are still starting, so items like `unit_masks` and `stop_<service>` can report `changed`/`error`; re-running the applier once the TV is idle returns `ok` for everything. Judge the harness by that second run. One post-power-on attempt is *not* enough here: archive-root's timing oracle reads as failure while services are still starting, so the watchdog settles ~30 s and retries up to 4 times, ~25 s apart — a lone attempt silently leaves the TV with no apply pass and no agent.
- **Use the `tv` CLI instead of hand-built agent/root strings.** Verbs, log aliases and the traps
  (single-threaded loop, ~10 s systemctl, journald inactive, dlog empty) live in the
  `samsung-tv-cli` skill; the backend is `/usr/local/bin/tvlib.py`. A status check is one short call
  returning ~285 chars instead of a hand-built command plus a wall of text.
- Delivering the loop: start it detached (`nohup`/`setsid`) and feed the script to a signed
  interpreter on stdin. UEP rejects any file you write yourself, so encode the script, decode it
  inline through `bash -c`, and never leave an executable file on the TV.

## Reporting style

- **Sequence this owner expects for multi-step TV work: research → saved plan → one short "what I will do" list → explicit go.** Research with real sources and the set's own measurements, write the plan to `~/.hermes/plans/` (see the `plan` skill), then state the intended actions in a short numbered list and stop for approval. Do not start mutating the TV from inside a plan-in-progress, and do not pad the handover with a re-explanation of the research.
- Lead with the bottom line: what was verified, what changed (usually nothing), what is blocked.
- Give a numbered app list with size and use count, and attach the full table as a file rather than pasting a wide table into chat.
- Call out overlap explicitly (e.g. several clients for the same media server) so the user can consolidate.
- When the ask is "what else can we improve", split findings into **fits the ask** and **doesn't fit but worth doing**, rank by improvement per euro/effort, and finish with one clear recommendation instead of a repo list.
- **"Are there risks?" wants a ranked list, not reassurance.** Put the likeliest first — usually your own mistake and the fragile after-boot persistence chain, not a remote attacker — then the concrete mitigation for each, then what is genuinely unchanged (display, playback, recovery image). Say plainly which risk you would not accept yourself.
- **"How long?" wants a breakdown, not a number.** Give minutes per step (feasibility probe, build, delivery, verify, cold boot) and name the one step that decides the rest, so a failed probe visibly shortens the estimate instead of sounding like a promise.
- **When the owner says "just fix X", do only X.** List what you parked in one line and do not resume those items until asked; a TV being watched by other people is not the place to continue an agenda.

## References

- `references/sdb-audit.md` — exact command sequence, capability fields, `vd_applist` parsing, limitations.
- `docs/debloat-modding.md (repo)` — menu paths, DNS list choices and breakage map, homebrew ecosystem, certificate workflow, recovery.
- `docs/rooting.md (repo)` — root assessment (what is real, compatibility including a verified Q60D/Tizen 9 result, the untethered fork, when root is not worth it) plus the host-side harness: power gating and WoL, per-call root wrapper, command-shape and verification rules, after-boot re-arm watchdog, Home-key rebinding.
- `scripts/tv-preflight.sh` — one-shot diagnosis of the connection chain: ping, TV API, developer mode, `developerIP` vs route source, sdb attach.
- `scripts/uep-probe.sh <tv-ip> <host-ip>` — settles whether this build executes unsigned native binaries (UEP). Run it before promising any native daemon; exit 126 means the only routes are the signed `bash` and `/usr/bin/dotnet`.
