# What changed in `optimize/2026-11-01`

Nothing here is published. The live repo and GitHub are untouched; this branch lives only in a local
working copy that is not connected to the published remote.

## Security fixes (real defects, found by reading the code)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `bin/tvlib.py` `sql()` | the `db` argument was interpolated into a shell command **unquoted** — `tv sql "x; <cmd>" '<q>'` executed arbitrary commands **on the TV as root** | only known aliases or an absolute `*.db` path are accepted; the path is `shlex.quote`d; the staged temp file is now PID-unique |
| 2 | `restore.sh` `restore_app()` | the app id from `--app` went into a shell command and into SQL unvalidated — same class of injection, root on the TV | `valid_app_id()` allowlist (`A-Za-z0-9._-`, ≤64 chars) + `sql_escape()` for the SQL literal |
| 3 | `restore.sh` `restore_all()` | a backup directory name went into SQL unescaped | escaped in the TV-side command |
| 4 | `bin/tv-agent-server.py` | token compared with `==` (timing side channel) | `hmac.compare_digest` |
| 5 | `bin/tv-root-apply` | chunking worked **per group**, so a single large group (`perf` = app records + kill-list + unit masks) could still exceed the command budget — and an over-long command is exactly what gets silently half-executed on the TV | chunking now works **per step**: groups are expanded into individual shell steps and packed into chunks under 4000 bytes, so one group can span several chunks. An oversized single step is logged as `OVERSIZE` instead of disappearing |
| 6 | `bin/tv-root-watchdog` `ensure_launcher()` | the home-app id was interpolated into a TV shell command unquoted (it comes from `/etc/default/tv-root`, so it is host-root-controlled — but it lands on the TV as root) | `shlex.quote`d |

## Correctness fixes

| # | Where | Problem | Fix |
|---|---|---|---|
| 7 | `bin/tvlib.py` `status()` vs `apps()` | the same "running apps" fact was counted two ways — `tv status` said 39, `tv apps` said 38 | both now use one counting rule (strip leading space, keep lines containing `(`, drop lines starting with `app`) |
| 8 | `scripts/uep-probe.sh` vs `skills/samsung-tizen-tv/scripts/uep-probe.sh` | the two copies had drifted: the skill copy lacked the `TV_HOST` export and the reachability pre-check | one file, copied to both places, keeping the scanner-friendly multiline cleanup |
| 9 | `skills/samsung-tv-cli/SKILL.md` | claimed "13 masked Tier A services" — the live configuration masks **11** | corrected to 11 |
| 10 | `scripts/package-agensi.sh` | the package README claimed "SkillSpector: 0/100, no findings"; the packaged zip actually scans **8/LOW** with one MEDIUM (0/100 is the standalone `SKILL.md`) | both numbers now stated correctly |
| 11 | `systemd/*.service` | `tv-root-watchdog.service` credited `chris-ritsen/samsung-tv-root` as its documentation URL; `tv-agent.service` had none | both point at this repo |
| 12 | `README.md` | one table said "Processes", another "running apps" | unified to "running apps" |

## Honesty fixes (claims vs measured reality)

- **The headline numbers are cold-boot measurements, and the README now says so.** A TV left on ~10 h
  drifts back to roughly **300 MB free and ~38 running apps** — the cuts still hold (removed apps stay
  gone, units stay masked), but services Samsung starts later in the session eat the idle pool again.
  Added a "Long-idle reality" section with the actual long-idle figures.
- **`mde-framework` comes back.** `launchpad-process-pool` respawns it despite the kill-list; the
  kill-list is a boot-time net, not a supervisor. Documented instead of implied away.
- **The host relay is LAN-exposed.** `0.0.0.0:8899` can run commands **as root on the TV**, gated only
  by `/etc/tv-agent.token` (mode 600). Disclosed in the Design section with the mitigation.

## Documentation added from research (`research/notes.md`)

- **Bishop Fox's advisory**: the root chain is *command injection in SDB, Tizen through 9.0*. Added to
  `docs/rooting.md` with the three consequences — a future firmware patch breaks the toolkit, and
  **blocking OTA keeps the hole open** (the deliberate trade behind this project's OTA policy).
- **The ecosystem's counter-argument**: cleanyourtv states that Tizen debloat and launcher
  replacement do **not** work without root. `docs/compatibility.md` now meets that argument before the
  claims, and explains what this repo does differently.
- **`firmwareVersion` from the REST API is unreliable** (`Unknown` across four TV years and three
  regions) — identify your build from the About screen or the build string instead.
- **DemonKingSwarn's 2026 chain** (`QA55QEF1AULXL`, SoC `rosel`) added to the compatibility table.
- **More import targets**, all verified: skills.sh, SkillsMP, LobeHub. Smithery is listed as *not*
  shipped (the MCP variant was built and deliberately dropped).
- **Scanner-rule table** in `research/notes.md`: which SkillSpector rule fires on what, and how this
  repo avoids each one.

## Verification of the optimization pass itself

The optimizations were re-checked by *executing the changed logic against stubs*, not by re-reading it.
That pass found two defects the first pass had introduced or left:

| # | What the check found | Status |
|---|---|---|
| V1 | `status()` built `$( … ` without closing the substitution (the `)` landed inside the awk quotes), so `tv status` would have returned **nothing at all** on the live TV — a regression introduced during this pass | **fixed**, and re-verified by executing the generated command against a stub `app_launcher` (counts 2 of 4 lines, matching `apps()`) |
| V2 | the Python floor was documented as 3.10 on the strength of `str \| None` alone — but every module has `from __future__ import annotations`, so 3.7 is enough; the gate would have rejected Debian 11 / Ubuntu 20.04 | **fixed** in `install.sh`, `scripts/tv-doctor.sh`, `README.md` and this report |
| V3 | the new CI workflow's leak-scan pattern matched **itself** inside `verify.yml`, so that job could never pass | **fixed** with a pathspec exclusion, then all seven CI steps simulated locally |
| V4 | `tv-root-apply --dry-run` still ran `pkill` on the kill-list — the flag promised "change nothing" and killed processes anyway | **fixed**: dry uses `pgrep` and reports `would-kill=N` (verified live: `would-kill=1`) |
| V5 | `parse_items` anchored at the start of the line, but `tv-root` prefixes its first output line with `stdout: ` — so **the first item of every chunk was silently dropped** (live run showed 15 of 19 items, hiding `home_mapping`, `disable_swu_records`, `disable_records`, `disable_perf_apps`) | **fixed** and verified live: 19/19 items |
| V6 | the first fix for V5 matched `ITEM\|` anywhere, which then **invented items from the wrapper's echoed command text** (rows ending in `'; elif …`). Tightened to records that end the line and contain no quote or semicolon | **fixed** and unit-tested against real, prefixed and echoed input |

What was verified by execution, with stubs and without touching the TV:

- `build_command()` output is **byte-identical** to the pre-refactor version (12,860 bytes, every group
  and all groups together) — the step-level refactor changed only how it is chunked.
- the new chunker turns 19 steps into 4 chunks of ≤ 3,793 bytes; each chunk passes `bash -n`, and it
  splits *inside* a group where needed.
- `sql()` rejects `x; rm -rf /`, `../../etc/passwd`, `pkgmgr; reboot` and `/opt/dbspace/ok.db; id`, and
  builds a quoted command for the accepted forms.
- `restore_app()` sends **zero** commands for hostile ids and a correctly quoted command for valid ones.
- the token comparison accepts the right token and rejects a wrong or missing one.
- `ensure_launcher()` quotes a hostile app id into a single shell word.
- the doctor's new JSON block stores a hostile `modelName` verbatim and executes nothing (marker file
  never created), while the three real fields parse correctly.
- both systemd units pass `systemd-analyze verify`.
- all seven CI steps pass when simulated locally.

---

## Not done, and why

- **No artifacts rebuilt.** `dist/tizen-lite.skill.md` and `dist/tizen-lite-agensi.zip` are unchanged
  because rebuilding means running `build-bundle.sh` / `scripts/package-agensi.sh` — you asked for no
  script execution. Both are one command each when you say go.
- **No live verification.** Everything above was checked statically (`bash -n`, `shellcheck`,
  `py_compile`, JSON parse, link check, leak scan) plus the earlier read-only runs against the real
  TV. The two code fixes in `restore.sh` and `tvlib.sql()` are **not** exercised against the live TV.
- **No MCP server**, no paid pack, no marketplace upload — all still decisions for you.
