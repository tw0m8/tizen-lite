# sdb audit cookbook

## Host setup

The package list is the authoritative source for the current filename and hash. Do not trust the `/binary/` directory index: it lists historical filenames that now return a 404 page (a ~1.4 KB HTML body that `unzip` then rejects).

```bash
mkdir -p ~/tizen-sdb && cd ~/tizen-sdb
curl -fsS https://download.tizen.org/sdk/tizenstudio/official/pkg_list_ubuntu-64 -o pkglist.txt
grep -A8 '^Package : sdb$' pkglist.txt     # Version, OS, Path, SHA256, Size
curl -fsSLO https://download.tizen.org/sdk/tizenstudio/official/binary/sdb_4.2.36_ubuntu-64.zip
echo "<SHA256 from pkglist>  sdb_4.2.36_ubuntu-64.zip" | sha256sum -c -
unzip -j sdb_4.2.36_ubuntu-64.zip data/tools/sdb
install -m 0755 sdb /usr/local/bin/sdb && sdb version
```

The binary is x86-64 only, Ubuntu-built, and runs unmodified on Debian 12/13. No Tizen Studio, no Java, no 32-bit libs.

## Source-IP pinning (the most common failure)

Developer mode stores one Host PC IP. Three different failures look similar, so identify which one you have before changing anything:

| Symptom | Cause | Fix |
|---|---|---|
| `sdb connect` prints `failed to connect` | `device.developerIP` names another machine | TV-side: Apps → App Settings → `12345` → Developer mode → host IP, then power-cycle |
| `sdb connect` succeeds but `capability`/`shell` hangs or fails | route leaves via the wrong NIC, so the source IP is not the whitelisted one | host-side: `ip route replace <tv>/32 dev <iface> src <whitelisted-ip>` |
| port 26101 closed | sdbd not running / TV in standby | power-cycle the TV at the mains |

```bash
curl -fsS http://<tv-ip>:8001/api/v2/ -o tvapi.json
grep -o '"developerMode":"[^"]*"' tvapi.json
grep -o '"developerIP":"[^"]*"'   tvapi.json
ip route get <tv-ip>                     # compare its "src" with developerIP
ip route replace <tv-ip>/32 dev <iface> src <whitelisted-ip>
```

On a multi-homed host both interfaces can be on the same LAN, so a self-consistent-looking setup still routes from the wrong address.

## Connect and gate

```bash
export TV=<tv-ip>:26101
./sdb kill-server; ./sdb start-server
./sdb connect $TV
./sdb devices
./sdb -s $TV capability | tee capability.txt
```

Capability fields worth recording:

- `platform_version` — Tizen major (e.g. `9.0`)
- `sdbd_version`, `sdbd_plugin_version`
- `intershell_support`, `sdbd_rootperm`, `rootonoff_support` — all `disabled` on retail
- `filesync_support` — `push` or `pushpull`; file pull is still refused on retail
- `sdk_toolpath` — where `device-profile.xml` must go for installs
- `cpu_arch`, `appid2pid_support`

## Inventory commands

```bash
./sdb -s $TV shell 0 vd_applist > vd_applist.txt   # user/downloaded apps, rich metadata
./sdb -s $TV shell 0 applist    > applist.txt      # all packages incl. services
./sdb -s $TV shell 0 getduid    > duid.txt
```

`vd_applist` header contains `apps count: N`. Fields per app include `app_id`, `app_package_name`, `app_title`, `app_version`, `app_size` (bytes), `install_date`, `use_count`, `installed_source_type`, `is_removable`, `is_hidden`, `is_lock`.

## Parsing pitfall

Values are terminated by a run of dashes (`30558313-------------`). Strip them before integer conversion, or `int()` raises.

`vd_applist` prints a formatted text table after a `get app list...` preamble — it is **not** JSON, and `json.loads()` on it fails on line 1. Parse `key=value` pairs instead (below). The app id field is `app_tizen_id`; the field `sdb uninstall` wants is `app_package_name`.

```python
import re, json
raw = open('vd_applist.txt', encoding='utf-8', errors='replace').read()
blocks = raw.split('-' * 93)
apps = []
for b in blocks:
    d = {}
    for m in re.finditer(r'-{14}([A-Za-z_()0-9:]+)\s*=([^\r\n]*)', b):
        d[m.group(1)] = m.group(2).strip().rstrip('-').strip()
    if 'app_id' in d:
        apps.append(d)
```

Sort by `app_size` descending for a keep/remove review. Summed `app_size` is installed-app footprint only — it excludes caches, app data and firmware, so never report it as free space.

## What is not obtainable

- Running processes (`ps`, `appcmd` disabled)
- Disk free space (`df`, `du` blocked) — read it on the TV: Settings → Support → Device Care → Manage Storage
- Firmware build string — on-screen only
- Logs (`dlog` disabled)
- File pull — no backup path exists

## Command surface

Only these are safe/available on retail:

```
shell 0 applist
shell 0 vd_applist
shell 0 getduid
uninstall <pkgid>
```

Destructive or state-changing verbs to avoid during an audit: `0 vd_appuninstall`, `0 appuninstall`, top-level `uninstall`, `0 debug <appid>` (launches an app and opens Web Inspector), `0 execute`, `0 kill`.
