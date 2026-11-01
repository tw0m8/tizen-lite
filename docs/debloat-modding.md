# Debloat and modding reference

## Native, zero-risk layer

| Goal | Path | Notes |
|---|---|---|
| Delete preinstalled app | Home → APPS → gear → select app → Delete | 2018–2024 models; e-Manual excluded; reversible |
| Disable ACR | General & Privacy → Terms & Privacy → Viewing Information Services = Off | DE: Anzeigeinformationsdienste = Aus |
| Disable ad targeting | same menu → Interest-Based Advertising = Off | DE: Interessenbasierte Werbung = Aus |
| Skip Smart Hub on wake | General & Privacy → Start Screen Options → Autorun Smart Hub / Start with Smart Hub Home = Off | biggest perceived-speed win |
| Disable TV Plus | highlight tile → Down or hold OK → Disable | returns after firmware update |
| Disable Gaming Hub | same as TV Plus | reversible |
| Bixby / remote mic | Bixby Voice Settings and Voice Wake-up = Off | also disables the remote mic button |

Account decisions: signing out of the Samsung account can disable Smart Hub apps; SmartThings is also the Matter/Zigbee/Thread hub on models that have it. Confirm with the user before touching either.

## DNS layer

Small, conservative list (keeps store/login/update/casting working):

```
https://raw.githubusercontent.com/helalaou/AeroTizen/main/dns/samsung-ads.txt
```

Broader option with per-domain breakage comments:

```
https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV-AGH.txt
```

AdGuard Home also has a built-in blocked service `Samsung TV Plus` (`samsung_tv_plus`).

Breakage map — do not block these casually:

- `lcprd1.samsungcloudsolution.net` → store, search, connectivity test
- `auth.samsungosp.com` → Samsung account login
- `time.samsungcloudsolution.com` → some streaming apps fail
- `otnprd8-11...`, `otn.samsungcloudcdn.com`, `www.samsungotn.net` → firmware updates stop
- `osb-*.samsungqbe.com` → TV Plus re-download; also reported as required for app install on some firmware — change one host at a time

Tier the list instead of adding everything at once: **safe** = Samsung ads + ACR + Smart Hub promo/telemetry; **strict** = `osb-*`, `gpm`, `scs`, `samsungrm.net` (TV Plus re-download and remote management); **OTA** = `otn*` only if the owner deliberately accepts frozen firmware and lost security patches.

After adding rules, verify both directions: a blocked host must return `0.0.0.0` and the store/login/streaming hosts (`samsungapps.com`, `account.samsung.com`, `netflix.com`, `primevideo.com`) must still resolve. If the resolver runs in a container, stop it before editing its config file — most write their state on
shutdown and will overwrite your edit otherwise.

Many TVs use hardcoded DNS, so AdGuard may never see the TV's queries. Verify with the query log filtered by the TV's client IP; real enforcement needs a router NAT redirect of port 53, which is a network-wide decision.

- **Filtering rules are global — there is no per-client custom rule.** A domain block cannot be scoped to one TV in AdGuard Home, so a "block it only for that device" request is answered either on the device (registry flags on the SWU/app records, on-device files) or with a resolver dedicated to that set. Say which of those you are doing instead of adding a global rule and hoping.
- **Check what the lists already block, and measure the blast radius, before adding anything.** Grep the filter cache (`workdir/data/filters/*.txt`) for the host and for the neighbouring vendors' domains: TV firmware lives on `samsungotn.net` (+`www`/`rwww`), handset firmware on `ospserver.net`, so a TV-firmware entry does not touch phones — while a vendor-wide `samsungqbe.com` entry reaches every Samsung TV on the LAN. A host already filtered everywhere is why an update unit can sit in `failed` state with zero related queries; report the existing block rather than adding a duplicate.

AdGuard Home keeps `workdir/data/querylog.json` as JSON-lines — one object per query, client in `IP`, name in `Question.Name`. Stream it in Python, filter on the TV's IP, and count per domain: that is the set's real contact list rather than a guessed one, and it is the honest before-picture for any DNS change. Absence is evidence too — a set whose `fw-update-service`/`vdca-update` units are `failed` and that has zero `otn*` queries is not being offered updates, whatever a menu claims.

## Homebrew ecosystem

| Project | Form | Notes |
|---|---|---|
| TizenBrew | web-app host + module loader | 1.7k★; stable on Tizen 7/8; Settings bug on Tizen 9 |
| TizenTube | TizenBrew module or standalone Cobalt app | ad-free YouTube + SponsorBlock; standalone needs partner signing; proxy/DNS issues on Tizen 9 |
| YouTube for Tizen (SushyDev) | standalone | alternative if TizenTube proxy fails |
| Jellyfin | official client, self-signed wgt | prebuilt wgt repos exist; must be re-signed per DUID |
| Plex | Samsung Store app | no sideload needed — lowest-risk media path |
| Moonlight | native/wasm client | Tizen 9 can break Game Mode; use a no-gamemode build |
| Steam Link | unofficial port | Valve discontinued the official TV app |
| AeroTizen / arn0-tv | signed wgt launcher | Home takeover is undocumented and firmware-dependent — last resort |

### Launchers on Tizen 9 — the Home-key reality

- **No plain `.wgt` can take the Samsung Home key.** True Home rebinding rewrites undocumented `home_appid`/`appfw` prefs through a PC-side native helper (AeroTizen CLI `home apply`, Arn0 Part 2, CleanFrame) or root. Everything else is watcher mode or an app-only grid.
- **AeroTizen 2.4.0** — the released `aerotizen-launcher-2.4.0.wgt` is unsigned and contains the on-boot watcher service; Apps2Samsung re-signs it, so watcher mode works without the CLI. Watcher cannot detect Home inside YouTube, Prime Video, Stremio, Spotify or HbbTV, and a full power-off can land on Samsung Home. The optional native Home binding is explicitly experimental.
- **Nha Minh (`meocong/prj-tv-samsung`)** — one tap in the Apps2Samsung catalog, QR phone setup, on-boot service; young and untested on Tizen 9.
- **Free My TV** — mature and safe, but not a Home replacement: it only becomes the first screen via Start Screen Options → Autorun Last App, and Home returns to Smart Hub.
- **TVDeck** — a TizenBrew module launcher; no certificate, installs from the TV, but cannot own Home and is bounded by TizenBrew's Chromium.
- `arn0-tv` Part 1 is an app-only grid; Part 2's Home takeover is one model (Q70B) and ships no runner.

### When YouTube breaks on Tizen 9

- **The standalone YouTube mod is not a separate player.** TizenTube injects into Samsung's own Cobalt app (`com.samsung.tv.cobalt-yt`, package `com.samsung.tv.cobalt`) through `xvvl3S1TT1.StandaloneService`. That injector re-spawns within seconds of a `kill`, so killing it proves nothing, and while it runs you cannot tell the official app from the modded one.
- **To get a vanilla official app, change registry flags and reboot.** Set `app_disable='true'` (with `app_onboot`/`app_autorestart` false) on both `xvvl3S1TT1.*` records in `package_app_info`, then power-cycle: these flags are read at boot and are inert before it, which is why killing the service or re-launching the app appears to ignore them. The official app is absent from the app row but starts fine.
- **`app_launcher` flags are not interchangeable:** `-s <app_id>` starts (add `-u 5001`), `-k` **kills**, `-S` lists running apps. Typing `-k` while meaning "launch" ends the owner's playback — read `app_launcher -h` before the first call.
- **Read the listener table instead of probing a port.** Tizen ships neither `nc` nor `timeout`, so a `timeout … /dev/tcp/…` wrapper fails with `timeout: command not found` and reads like "port closed". Instead: `grep -oE "[0-9A-F]{8}:[0-9A-F]{4}" /proc/net/tcp | grep '^0200007F'` lists `127.0.0.2` listeners (hex address, little-endian; the port is the hex field after the colon).
- **A live `127.0.0.2` listener with playback still failing points at Cobalt's loopback reach, not a missing service.** The Tizen 9 remedy is the same release's second asset, `TizenTubeCobaltTizenTubeProxyAddress.wgt` — and what makes it different is the **hostname, not the address**: it sets `--proxy=http://tizentube:8101` and expects DNS to resolve `tizentube` to the TV's own **static** IP (its docs say so explicitly, and warn the IP must not change). Substituting the bare LAN IP is not equivalent: `--proxy=http://<tv-ip>:8101` replaced the "something went wrong at the start of the video" error with a **freeze**, while the proxy kept listening on `0.0.0.0:8101` and was reachable from the TV itself. Implement it with a DNS rewrite (`tizentube` → TV IP) plus the DB row, or install upstream's build.
- **Change the launch arguments in the package DB, not in `config.xml`.** The install-time `config.xml` is inert afterwards: the framework replays `package_app_app_metadata.md_value` (`md_key='http://samsung.com/tv/metadata/native.userdata'`) from `/opt/dbspace/.pkgmgr_parser.db` on every launch, so editing the file under `/opt/usr/apps/<pkg>/res/wgt/` changes nothing observable — check `md5sum` and behaviour before claiming otherwise. Records re-enabled in `package_app_info` stay unavailable (`is not available for the user 5001`) until a reboot.
- **Test DNS and the socket separately, and read `000` correctly.** `curl -v -m5 http://tizentube:8101/ | grep -E 'Trying|Connected|resolve'` proves name resolution plus TCP; a plain `GET` returns no body and `%{http_code}=000` because the proxy does not answer an ordinary request, so `000` alone proves nothing about the fix. Confirm the listener with `grep -c 1FA5 /proc/net/tcp` (hex port; `00000000:` means all interfaces) — the set has no `nc`.
- **Verified end-to-end fix (Q60D / Tizen 9, 2026-10-31): DNS rewrite + hostname in the DB row, then reboot.** Result: ads gone, clean playback, ~15 established sockets on the proxy. Order matters:
  1. Add the rewrite `tizentube` → TV IP to your local resolver's rewrite list (AdGuard Home shown here) **with the container stopped**: AdGuard persists its own config on shutdown, so a file edited against a running instance is unverified until it answers. `docker stop <container>` → patch the file → `docker start`, then `dig +short @<resolver> tizentube` must return the TV IP before touching TizenTube. `tv dns` does this for you when `TV_AGH_YAML` and `TV_AGH_CONTAINER` are set in `/etc/default/tv-root`. The TV resolves through AdGuard, and its `/etc/hosts` is read-only, so a local hosts entry is not an option. Restarting AdGuard costs a 2–3 s LAN-wide DNS blip — fine for streaming, still worth doing when nobody is mid-boot. Look for an existing `rewrites:` list and append to it; do not add a second key.
  2. In `/opt/dbspace/.pkgmgr_parser.db`: replace `http://127.0.0.2:8101` with `http://tizentube:8101` in `package_app_app_metadata.md_value` for `xvvl3S1TT1.TizenTubeStandalone`, and set `app_disable='false'`, `app_onboot='true'`, `app_autorestart='true'` on both `xvvl3S1TT1.*` records.
  3. Reboot — re-enabled records stay `not available for the user 5001` until boot, so a start attempt before it looks like a broken app.
  4. Verify in this order: `curl -v http://tizentube:8101/` prints `Connected to tizentube (<tv-ip>) port 8101`; `grep -ac 1FA5 /proc/net/tcp` is non-zero; then play a real video and watch for ads. Sockets on the proxy while a video plays are the proof the injector is in the path, not merely installed.
- **Isolate ownership before touching platform state.** If the Cobalt/YouTube app records are untouched and no DRM or media unit is stopped, the fault is in the wrapper build, not in the debloat work — an A/B against the official app is the cheapest discriminator, and it keeps a working cleanup from being reverted over an unrelated app bug.

## Certificate workflow

1. Free Samsung Developers account; sign in yourself. Seller account is only for store publishing.
2. Create author certificate; back up `author.p12` + password.
3. Create distributor certificate; add the TV's DUID (from `shell 0 getduid` or Settings → Support → Contact Samsung).
4. Push `device-profile.xml` to `sdk_toolpath` (`tizen install-permit` wraps this).
5. Install one package, reboot, test, repeat.

Common failure: `install failed [118,-12] Invalid certificate chain` = stale/missing device profile, or a certificate not bound to this TV's DUID. `Author certificate not match` = an older build by a different author is still installed; uninstall it first.

## Apps2Samsung CLI (preferred; runs headless)

The release ships a self-contained `apps2samsung-cli` binary per platform
(`Apps2Samsung-cli-v<version>-linux-x64.tar.gz`). It uses the same catalog,
certificate and install pipeline as the desktop app:

```bash
apps2samsung-cli scan --json                 # ready / developerIp / debugPortOpen
apps2samsung-cli cert --tv <ip> --json       # Public and Partner profile state
apps2samsung-cli installed --tv <ip> --json  # catalog-aware app list
apps2samsung-cli catalog tizentube           # files, versions, requiresPartner
apps2samsung-cli install "TizenTube" --tv <ip> --launch
apps2samsung-cli install ./local.wgt --tv <ip> --launch
```

- Certificate store: `~/.config/Apps2Samsung/Certificate` on Linux, shared with the desktop app on the same machine. Back it up; losing it means re-signing every app.
- `cert --tv` shows whether a Public/Partner profile `exists` and is `usable`; `--partner` forces partner level. The catalog's `requiresPartner` is not the final word — the installer selects the privilege level an app needs.
- First certificate needs a Samsung sign-in. The callback is `http://localhost:4794/signin/callback`, so `--no-browser` is only useful when a browser can reach that port on the CLI host. On a headless box use an SSH local forward from a desktop (`ssh -L 4794:127.0.0.1:4794 user@host`) and open the printed URL there, or create the profile on a desktop with `cert --prepare --duids <DUID>` (no TV connection needed) and reuse its store.
- The CLI exits 3 at a pre-install warning (Developer Mode off, Host PC IP pointing elsewhere, wrong subnet); `--yes` continues. Treat exit 3 as a diagnosis, not a failure.
- If the GitHub API is rate-limited, read the tag from `releases.atom` and list assets from `releases/expanded_assets/<tag>`.

## Risk and recovery

- Native deletion / settings: reversible by toggling back or factory reset.
- sdb uninstall: no backup; reinstall from the store or factory reset. Removing the wrong platform package can kill the launcher.
- Broken UI: Settings → General → Reset (PIN 0000) restores all preloads.
- USB firmware reflash needs a booting TV with working menus; a dead bootloader means mainboard replacement.
- Root on retail sets is model/firmware-specific, volatile (reacquired from a PC after each boot), and depends on an unpatched sdb bug. Do not propose it as a consumer debloat path.
