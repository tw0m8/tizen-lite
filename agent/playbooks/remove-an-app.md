# Playbook — remove an app so it stays gone

Use for: pre-loaded apps you never use (TV Plus, Art Mode, AirPlay, cloud/account agents, ACR).

## Why the obvious approach fails

- `pkill` alone: `launchpad-process-pool` restarts the app within seconds.
- `app_disable='true'` alone: the framework still launches it.
- Only **disabling the records + moving the app directory out of `/opt/usr/apps`** is durable.

## Preconditions

- Unit is not in `manifest.json → invariants.never_remove`.
- The human has confirmed they do not use the feature (ask once, precisely).

## Steps

1. **Identify all pieces.** One feature is often several packages:

   ```bash
   tv run 'sqlite3 /opt/dbspace/.pkgmgr_parser.db \
     "SELECT app_id, package, app_onboot, app_autorestart, app_disable, app_removable FROM package_app_info;"' \
     | grep -i <feature>
   ls -d /opt/usr/apps/*<feature>* 2>/dev/null
   ```

2. **Back up first** — copy the package DB and move (never delete) the directory:

   ```bash
   BK=/opt/usr/share/tv-root-backups/<change-set>; mkdir -p $BK
   cp /opt/dbspace/.pkgmgr_parser.db $BK/pkgmgr.db.bak
   mv /opt/usr/apps/<pkg> $BK/
   ```

3. **Disable the records.** Ship the SQL as *data*, not as a script (UEP blocks unsigned scripts):

   ```bash
   echo <base64-sql> | base64 -d > /tmp/x.sql
   sqlite3 /opt/dbspace/.pkgmgr_parser.db < /tmp/x.sql
   ```
   ```sql
   UPDATE package_app_info SET app_disable='true', app_autorestart='false'
    WHERE package='<pkg>';
   ```

4. **Kill the live process** — bracket the pattern so it cannot match your own command line:

   ```bash
   pkill -f apps/org[.]tizen[.]art-app
   ```

5. **Verify** no process after ~20 s and no directory left. Beware self-matching `pgrep`:

   ```bash
   pgrep -f 'apps/com[.]samsung[.]tv[.]vi[f]'
   ```

6. **Cold boot**, then re-run `./agent/audit.sh` and ask the human to exercise the features they use.

## Undo

Move the dir back, set `app_disable='false', app_autorestart='true'`, remove any matching pattern from
`/etc/tv-root-kill-procs`, reboot, re-audit.

## Feature groups and what they cost

| Removed | Frees | Notes |
|---|---|---|
| `art-app` + `home.art` | ~187 MB | Art Mode; kill in the boot list too |
| TV Plus (`HEPsqFNie0`, `com.samsung.tv.tvplus`, `slive-daemon`) | ~40 MB + stops live channels | also disable `tvPlusDeeplinker` |
| `home.media` | ~112 MB | safe **only while** sidebar + contentservicemanager stay |
| `airplay-app-2`, `samsung-cloud` | ~26 MB | |
| `vif`, `context-aware-service` + `-agent` | ~35 MB | ACR / presence detection |
| `easysetup-daemon`, `tap-service-agent` | ~26 MB | |

## Traps

- **Never remove `home.sidebar` + `contentservicemanager`** — the quick-settings panel then opens with
  every control reading *"Preparing… Please try again later"*.
- A process that respawns in <20 s is framework-managed (`mde-framework`); a boot kill buys nothing.
- Moving a directory while its process runs leaves the old process alive until killed.
