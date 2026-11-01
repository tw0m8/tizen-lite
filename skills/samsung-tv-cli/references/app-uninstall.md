# Uninstalling a store/preload app on this TV (TV Plus worked example)

App-level debloat is separate from systemd masks. `pkill` alone is not durable — the framework
restarts most of these — and a `package_app_info.app_disable='true'` row alone did not stop some
apps from running. What actually sticks is: disable the records, move the app dir out of
`/opt/usr/apps`, and kill the live process. Verify after a cold boot.

## TV Plus (restore point `/opt/usr/share/tv-root-backups/tvplus-01`)

Identifiers on T-NKLDDEUC_0090 (Tizen 9.0):

- `com.samsung.tv.tvplus` — the packaged TV Plus app (`app_removable=true`)
- `HEPsqFNie0.tvplusstandalone` (package `HEPsqFNie0`) — **the one that actually plays**; a
  store-installed standalone whose dir is `/opt/usr/apps/HEPsqFNie0` and whose binary is
  `bin/HEPsqFNie0.tvplusstandalone`
- `com.samsung.tv.slive-daemon` — live-channel service (`slive-provider-daemon`); its package is
  shared with `org.tizen.bms-service`
- `tvs-tvplus`, `slive-provider` — extra dirs under `/opt/usr/apps`
- `com.samsung.tv.tvPlusDeeplinker` — can relaunch TV Plus by deeplink, disable it too

Steps: back up `package_app_info` (`/opt/dbspace/.pkgmgr_parser.db`) → `UPDATE package_app_info SET
app_disable='true', app_onboot='false'` for all of the above → `mv` their dirs to the backup dir →
`pkill` the live processes → cold boot → confirm zero processes and no dirs.

## UEP blocks unsigned scripts, even from root

`sh /tmp/whatever.sh` fails with `[uep][bash] the file is NOT signed!!`. Do not ship script files to
the TV. Two things that do work:

- **SQL via a file, not a script**: `base64` the statement, decode it to `/tmp/x.sql` on the TV, then
  `sqlite3 <db> < /tmp/x.sql`. UEP only blocks *executing* it.
- **Everything else inline** in one `tv run` command string.

## Who respawns app processes: `launchpad-process-pool`

App processes return within seconds of a kill because `/usr/bin/launchpad-process-pool` (**ppid 257**)
relaunches them. The DB flags do not stop it: `app_disable='true'` and `app_autorestart='false'` were
both set on `airplay-app-2` and the process still came back in under 5 s. So the sequence is
**move the dir → then kill**; once the exec target is gone launchpad cannot restart it, and it stays
dead across cold boots (verified for Art Mode, TV Plus, AirPlay, Samsung Cloud, content-service
manager). Killing launchpad itself is not an option — it launches every app including the launcher.

App services with **`ppid 1`** are a different case: systemd owns them, so `systemctl mask --runtime`
plus a stop (SIGKILL escalation) works.

## Verify a kill by resolving the process, not by grepping for it

Every kill-and-verify loop here produces false positives unless the pattern cannot match the command
that runs it:

- `pkill -f /opt/usr/apps/org.tizen.art-app/` kills the *shell itself* — rc 143 and no output at all.
- `pgrep -f contentservicem` also matches its own child processes, so a dead app looks alive.
- An echo label is enough to self-match: `echo "tvplus=[$(pgrep -f tvplu[s])]"` still hits, because the
  literal `tvplus=` is in the command line.

Bracket any character that can complete a match (`contentservice[m]`, `tvplu[s]`, `airplay[-]app`) and
make labels differ from patterns. When the answer matters, confirm with `readlink /proc/<pid>/exe` or a
`ps -eo args=` filter on a path the command line does not contain.

## App ids worth knowing

- Samsung **Home**: `com.samsung.tv.home.media` (`HomeMedia.dll`); fallback `com.samsung.tv.coba.newhome`.
- `mde-framework` (ads/recommendations, ~22 MB) respawns after every kill even with its dir present —
  the boot kill is best-effort only, not a durable win.
- Removing one member of a family leaves siblings behind; grep the package prefix, not the single id
  (`context-aware-service` had a `context-aware-agent`; `easysetup-daemon` has `easysetup-client`,
  `easysetup-mediator`, `org.tizen.easysetup-UI` — inert unless something launches them).

## You cannot see Samsung Home while Free My TV is the Home app

When the appsvc `operation/main` row points at Free My TV, the framework treats Free My TV as home:
`app_launcher -s com.samsung.tv.home.media` reports `successfully launched pid = <pid>` but changes
nothing on screen, and `app_launcher -k FreeMyTVio.FreeMyTV` is undone within seconds because launchpad
starts the home app again. So a Samsung-Home-dependent removal (e.g. `contentservicemanager`, which
feeds Samsung's content rows) cannot be verified visually in the normal state. Either verify the
surfaces the user actually opens, or temporarily point the home mapping at Samsung Home, power cycle,
look, and put it back. Do not claim a UI removal was verified when the only check was "process gone".

## Restoring an app you removed

Moving the dir back is only one third of it:

1. `mv` the dir from the backup dir back to `/opt/usr/apps`.
2. Reset the records — `app_disable='false'` (and `app_autorestart='true'` if that is how it shipped);
   leaving `app_disable='true'` makes it look restored while the framework keeps refusing to start it.
3. **Drop its pattern from `/etc/tv-root-kill-procs`**, or every boot apply kills it again and the
   restore silently undoes itself.

## Measuring what is left (verified recipe)

Per-app RSS totals, largest first, through the `tv` CLI — the two-stage `awk` is what survives the
quoting layers (awk programs in double quotes inside the single-quoted `tv run` argument):

```bash
tv run 'ps -eo rss=,args= 2>/dev/null | awk "/\/opt\/usr\/apps\//{ for(i=1;i<=NF;i++) if ($i ~ /\/opt\/usr\/apps\//) { split($i,a,\"/\"); print $1, a[5] } }" | awk "{ m[$2]+=$1 } END { for (k in m) printf \"%5dMB %s\n\", m[k]/1024, k }" | sort -rn | head -16'
```

Measure only when idle — a streaming set holds ~300 MB more, so a "memory went up" reading during
playback means nothing.

## The Samsung Home stack is load-bearing for the quick-settings panel

Do not remove these three without checking the **remote's quick-settings button**:
`com.samsung.tv.home.sidebar`, `com.samsung.tv.home.media`, `com.samsung.tv.contentservicemanager`.
With any of them missing the panel still opens but every control reads **"Preparing… Please try again
later"** — it reads like a network or account fault, and there are no logs to say otherwise.

`home.sidebar` is the panel itself, so it is almost certainly the one that must stay; `home.media`
(112 MB) and `contentservicemanager` were needed in combination on this set.

**Refined same day:** `com.samsung.tv.home.sidebar` + `com.samsung.tv.contentservicemanager` are the
required pair — `home.media` (112 MB) was removed again with quick settings still fully working, so it
is only needed while `contentservicemanager` or `sidebar` is missing.

Removed with no visible breakage (app screen, inputs, settings shortcut and Prime all still fine):
`art-app` + `home.art` (Art Mode), `vif`, `context-aware-service` + `context-aware-agent`,
`easysetup-daemon`, `tap-service-agent`, `airplay-app-2`, `samsung-cloud`, TV Plus.

## Removed so far on this set

TV Plus (all pieces), Art Mode (`art-app` + `home.art`), `airplay-app-2`, `samsung-cloud`,
`contentservicemanager`, `vif`, `context-aware-service` + `context-aware-agent`, `easysetup-daemon`,
`tap-service-agent`. Kept deliberately: `csfs`, `home.media`, `home.sidebar`, `ssoservice`, `dseal`,
`cis-service-app`, `vd-sc-client-service`, SmartThings and Google Cast, plus everything DRM/account.
Biggest remaining non-core processes: `home.sidebar` (~93 MB), then `mde-framework` (~20 MB, respawns).
