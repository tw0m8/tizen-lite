# FAQ — the questions people actually ask

### Will this brick my TV?

Nothing in this work bricked the set it was developed on, and nothing is ever erased: removed apps are
*moved* into `/opt/usr/share/tv-root-backups/`, and the database is copied before every edit. That is
evidence from one TV, not a guarantee for yours. The
realistic worst case is a feature that stops working until you restore it — which `./restore.sh` does.

The genuine risks, stated plainly: root exploits are unofficial and a future firmware may close them;
`/etc` is read-only so masks vanish on reboot; and a half-applied change can leave the TV in a state
where one app misbehaves until the next apply. None of that is unrecoverable.

### Do I need a server?

No. You need a **host** — a Raspberry Pi, NAS or the PC you already leave running, on your own LAN.
Nothing is uploaded anywhere and there is no cloud account.

Why it can't be a one-time job: the TV does not keep root across a power-off, and service masks live in
RAM. So once per boot, something reconnects (~20 s), re-acquires root, re-applies (~40 s) and steps away.

| Survives a power cycle on its own | Needs the host after each boot |
|---|---|
| uninstalled apps (files + database rows) | systemd unit masks |
| disabled package records | the process kill-list (Art Mode, TV Plus runtime) |
| TizenTube configuration | the launcher push |

### Does it survive a firmware update?

Masks and kills: no, they are re-applied each boot by design, so yes once the host is running again.
App removals: a firmware update usually reinstalls packages, so expect to redo those.

Owner policy used here: OTA is blocked, and firmware is reviewed roughly every six weeks — install only
if a build brings something worth having, skip minor point releases.

### Will Netflix / Prime / Disney+ still work?

They did here, including DRM playback, because the DRM path is deliberately left intact (`dta-agent`,
`aaa_tvs_deamon`, `playready`, `security-manager`, `key-manager`). If a streaming app breaks after a cut,
you removed a DRM component — restore it and reboot.

### Do I lose the app store or Samsung account?

No. But this setup keeps the TV's internet blocked and unblocks it only when you want to install or
update something, then blocks it again. That is a choice, not a requirement.

### Will the picture change?

No. Debloating touches software processes, not panel, HDMI or picture settings.

### Why is boot still slow?

Because the bottleneck is the firmware's own serialized startup queue, not the services removed here.
Measured on this set: REST API answers at ~34–43 s, the picture appears at ~134 s. Removing services
shortens the queue and frees memory; it cannot rewrite the boot chain.

### Why are there no screenshots?

This firmware ships a stripped `enlightenment` with no screenshot support and no capture binary. A
rendered mock-up would be fiction, so the README describes behaviour instead of drawing it.

### Can I undo it?

Yes — `./restore.sh --list` shows what is backed up, `./restore.sh --app <id>` puts one back,
`./restore.sh --all --yes` reverts everything. Then power-cycle and run `./agent/audit.sh`.

### Is my TV supported?

See [compatibility.md](compatibility.md). Short version: tested on a 2024 Q60D with Tizen 9.0; the method
generalises, the exact unit names and app ids do not.

### What does root actually buy me?

Three things only: writing to read-only paths, masking units at runtime, and querying the package
database directly. It does not unlock the bootloader, install a custom kernel, or remove Samsung's
update mechanism at the block level.
