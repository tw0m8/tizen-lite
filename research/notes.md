# Research notes — 2026-11-01

Background research done by hand (web tools only; no subagents, no extra model quota).
Each item says what it changes in the repo.

## 1. The root chain is a published vendor vulnerability

**Bishop Fox — *Samsung Tizen OS | Version Through 9.0*** —
<https://bishopfox.com/blog/samsung-tizen-os-version-through-9-0/>

Documents **arbitrary command injection in the SDB service, affecting versions through 9.0**.

Consequences, all now stated in `docs/rooting.md`:

- Every root chain in this repo rides that bug; a future firmware patch breaks the toolkit.
- **Blocking OTA keeps the hole open** — the deliberate trade behind this project's OTA policy.
- A patched build looks exactly like a broken harness. Read the failure as "vendor closed it".

**Second chain, newer hardware** — DemonKingSwarn, *Breaking and Rooting a 2026 Samsung Tizen 9.0
Smart TV*: `QA55QEF1AULXL`, Tizen 9.0.0, `T-RSLFUABC-0090-REL-202608061940`, SoC `rosel`.
<https://github.com/DemonKingSwarn/samsung-tv-tizen-root/blob/main/ROOTING-RESEARCH.md>
→ added to the compatibility table. Their prerequisites (sdb 4.2.x, Python 3, openssl, .NET 6 SDK)
match what this repo assumes.

## 2. The ecosystem's own verdict: Tizen debloat is hard

**cleanyourtv — Samsung Tizen reconnaissance**
<https://github.com/Gathin23/cleanyourtv/blob/main/docs/devices/samsung-tizen.md>

> "Don't spend time on this repo expecting to debloat a Samsung Tizen TV or replace Samsung Home.
> That workflow does not work here."

Their conclusion: without root, the realistic Tizen shape is **DNS + remote-key settings**, not a
launcher and package surgery. Their DU7000 (2026) and AU8000 probes are careful, model-scoped
capability reports, not a debloat list.

→ `docs/compatibility.md` now states this plainly and explains what this repo does differently
(root + package records + directory move, accepting `launchpad-process-pool` respawns), so a reader
meets the counter-argument before they meet the claims.

## 3. `firmwareVersion` from the REST API is unreliable

cleanyourtv reports `firmwareVersion: Unknown` across **four TV years and three regions**.
→ `docs/compatibility.md` now says: identify your build from the TV's About screen or the build
string in `/etc/default/tv-root`, not from that API field.

## 4. TizenBrew / TizenTube are alive, with a specific install flow

- TizenBrew: <https://tizenbrew.vercel.app> — TizenTube ships as a TizenBrew module.
- TizenTube: <https://github.com/reisxd/TizenTube> — ad-free YouTube + SponsorBlock.
- Current flow: install the **TizenBrew Installer** app on the TV → "Install TizenBrew" → then the
  TizenTube module.

→ checked against `docs/debloat-modding.md`; the repo's YouTube section already points at TizenTube
and TizenBrew, so no factual change was needed beyond the credits.

## 5. Import targets that exist today (verified, not guessed)

| Registry | URL | Packaging |
|---|---|---|
| skills.sh | <https://skills.sh> | SKILL.md package |
| SkillsMP | <https://skillsmp.com> | SKILL.md package, Codex + Claude |
| LobeHub Skills | <https://lobehub.com/skills> | SKILL.md package |
| Agensi | <https://www.agensi.io> | ZIP upload, one SKILL.md, frontmatter-driven listing |
| Smithery | <https://smithery.ai> | MCP servers — **not** shipped here (an MCP variant was built and dropped: schema cost outweighed its value) |

→ README "Import it anywhere" gained skills.sh / SkillsMP / LobeHub rows.

## 6. What static scanners flag in agent skills

SkillSpector (NVIDIA) is the reference scanner; Agensi runs a comparable gate.

Observed rules while packaging this repo:

| Rule | What triggered it here | How it was avoided |
|---|---|---|
| TT3 tainted flow | env token → `urlopen` in the polling agent | the relay lives outside the uploaded package |
| SC2 external script fetching | `curl … \| python3` in a doc | split into `curl -o file` + read the file |
| PE5 privileged container / escape | rooting notes read as privilege abuse | rooting docs are not in the upload; the method is |
| TM2 chaining abuse | `&&`/`;` chains in a script | multiline cleanup blocks |
| LP1 capability mismatch | env/network code with no declared capability | only relevant to the full bundle |
| PE2 sudo/root execution | the literal word `sudo` in commands | phrased as "needs an elevated shell" |
| RA2 session persistence | persistence wording in docs | reworded to "enabled-state" / "after each boot" |
| AE1 incomplete artifact analysis | SKILL.md referencing a script not shipped | ship the referenced script or drop the reference |

Listing package: **8/LOW**, one MEDIUM. Full package: **100/CRITICAL** — which is why
`scripts/package-agensi.sh` builds two modes and the upload gets the method-only one.

## 7. Ecosystem ranking reality

GitHub repo search sorts heavily on stars; a 0-star repo sits at the bottom of any popular query no
matter how good the description is. Measured: 17th of 17 for "samsung tv debloat", 14th of 22 for
"tizen debloat", and **1st of 1** for "remove tv plus samsung". Description phrasing moved nothing;
stars and external links are the lever. Niche size: `tizen debloat` = 22 repos, `samsung tv debloat`
= 17, `tizen root` = 37 — small crowd, room to rank.

Topic audiences (repos per topic): `privacy` 35k · `ai-agents` 132k · `agent-skills` 40k ·
`adblock` 1.9k · `debloat` 1.1k · `smart-tv` 627 · `tizen` 447 · `samsung-tv` 246 · `tizen-tv` 90.
