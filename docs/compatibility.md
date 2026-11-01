# Compatibility

## Verified

| Device | Firmware | Tizen | Result |
|---|---|---|---|
| **QE75Q60** (Q60D, 2024, 75", EU) | `T-NKLDDEUC-0090/2123.9` | 9.0 | everything in this repo, over repeated cold boots |

Kernel 5.4.249. Root via the archive-launcher route, one command at a time, no persistence on the TV.

## Reported by the upstream root project

| Device | Firmware | Note |
|---|---|---|
| QN90B | various | original research target |
| QN90F | various | reproduced |
| QN43LS03DAFXZA (Frame 2024) | `T-PTMDAKUC-0090-2130.0` | archive-launcher probe returned UID 0 |

Source: [chris-ritsen/samsung-tv-root](https://github.com/chris-ritsen/samsung-tv-root). The untethered
variant is [levkropp/samsung-tv-root-untethered](https://github.com/levkropp/samsung-tv-root-untethered).

| Device | Firmware | Note |
|---|---|---|
| QA55QEF1AULXL (2026, 55") | `T-RSLFUABC-0090-REL-202608061940` | archive-root chain, Tizen 9.0.0, SoC `rosel` — [research paper](https://github.com/DemonKingSwarn/samsung-tv-tizen-root/blob/main/ROOTING-RESEARCH.md) |

## Two things that trip people up

**`firmwareVersion` from the REST API is often `Unknown`.** That has now been reported across four
TV years and three regions ([cleanyourtv's Tizen reconnaissance](https://github.com/Gathin23/cleanyourtv/blob/main/docs/devices/samsung-tizen.md)).
Identify your build from the TV's own About screen or from the build string in
`/etc/default/tv-root` — not from that API field.

**Package-level debloat of a Tizen TV is not a solved problem for most people.** cleanyourtv states
it plainly: *"Don't spend time on this repo expecting to debloat a Samsung Tizen TV or replace Samsung
Home. That workflow does not work here."* Their conclusion is that the realistic no-root shape is
DNS plus remote-key settings, not a launcher and package surgery.

This repo takes the other branch: it requires **root**, edits the package records *and* moves the
directory, and accepts that `launchpad-process-pool` will respawn some apps. That is why the numbers
here were measured over cold boots and why every change has a rollback — not because the method is
easy. Expect the same walls they did.

## What to check on your own set before cutting anything

```bash
tv status                        # model, firmware, build, power state
curl -s http://TV_IP:8001/api/v2/ -o status.json   # then open status.json
```

Look for `modelName`, `firmwareVersion` and `developerMode`. If the archive route does not return
`uid=0`, nothing in this repo can help — root is the precondition, not a feature of it.

## What transfers, what does not

| Transfers | Does not |
|---|---|
| the method: one change per cold boot, restore points, symptom → cause | unit names (`swu-auto-upgrade`, `reporterCA`, …) |
| the mechanics: runtime masks, database flags, moving app directories | app ids (`HEPsqFNie0.tvplusstandalone`, …) |
| the load-bearing concept (DRM, quick settings, sdbd, csfs) | memory numbers — a different panel has different sizes |
| the tooling (`tv`, `tv-root-apply`, watchdog, agent) | which services exist at all |

Treat every name in this repo as a **starting hypothesis for your model year**, and verify it with
`./agent/audit.sh` plus one cold boot per change.
