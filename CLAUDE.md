# CLAUDE.md

This repository is **Tizen Lite** — a skill for slimming down a Samsung Tizen TV, plus the tooling that
applies it. If you were handed this repo to work on a TV, read these two files before touching anything:

1. **`AGENTS.md`** — the operating contract: discovery step, load-bearing components, the boot-bisect
   protocol, verification contract, and the report format to use with the user.
2. **`agent/manifest.json`** — the same rules machine-readable, including the exact error string each
   wrong removal produces.

## The short version

- Discover first: `./agent/audit.sh` prints JSON (reachable, rooted, units down, memory, launcher offset).
- Never remove: `aaa_tvs_deamon` (DRM), `home.sidebar` + `contentservicemanager` (quick settings),
  `dta-agent` (CDM), `sdbd` (root transport), `csfs`, or the configured home app.
- Change **one thing per cold boot** — live changes cannot reveal a boot-time dependency.
- Units are masked at runtime (`/etc` is read-only); apps need their records disabled **and** their
  directory moved out of `/opt/usr/apps`, because `launchpad-process-pool` restarts anything it can exec.
- This firmware has **no logs**. `journalctl`, `dlogutil` and `/var/log/dlog` are empty — bisect instead.
- Report as: Diagnosis / Evidence / Change / Risk / Rollback / Your turn.

## Layout

| Path | Contents |
|---|---|
| `skills/tizen-lite/SKILL.md` | the importable skill (frontmatter + method) |
| `AGENTS.md`, `agent/` | agent contract, manifest, read-only audit, playbooks |
| `bin/`, `config/`, `scripts/` | runnable tools and editable state files |
| `docs/` | long-form notes: rooting, boot timing, debloat, app uninstall, sdb audit |
| `dist/tizen-lite.skill.md` | generated single-file bundle for pasting into any agent |

Regenerate the bundle with `./build-bundle.sh` after editing the skill or the manifest.
