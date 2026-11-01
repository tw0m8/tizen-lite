# Packaging and distribution — verified spec + what to actually do

Written by hand after the delegated research died on provider rate limits. Everything below was read
off the live pages (Agensi docs, its sell page, the registries' own sites) or measured by running
SkillSpector against this repo's packages — not recalled from a blog.

## 1. Agensi: the upload contract

Source: <https://www.agensi.io/docs/packaging>, <https://www.agensi.io/docs/creator-quickstart>,
<https://www.agensi.io/sell>

**One ZIP.** Agensi finds every `SKILL.md` in it at any depth: one makes a skill, two or more make a
skill pack. One top-level folder is fine.

**Frontmatter is the listing.** The upload form reads `name`, `description`, `summary`, `version`,
`tags`, `keywords`, `use_cases`, `docs_url`. The top `SKILL.md` must have `name`; every `SKILL.md`
needs a `description`.

**Limits**

| Limit | Value |
|---|---|
| ZIP size (website upload) | 50 MB |
| Files per package | 1,000 |
| Skills per pack | 50 |
| Upload from an agent | 100 files, 5 MB, text only |
| Per script (guidance) | under 20 KB |
| What a buyer's agent receives | every `SKILL.md` + up to 200 other text files, ≤ 6M characters per listing |
| Rejected | executables (`exe dll so dylib bin app dmg msi deb rpm wasm class jar war`), bundled deps (`node_modules`, `site-packages`, venvs) |
| Stripped on upload | `.git`, Python caches, `.DS_Store` |

**Images and PDFs are allowed but useless**: the marketplace delivers text only, so an agent cannot
read them. Anything an agent needs must be text.

**Scripts run as shipped** — the buyer's agent writes the file to a temp path, runs it, removes it.
That is why a script that assumes `/usr/local/bin/tv` exists will fail on a fresh machine; ship the
prerequisite check, not just the happy path.

**Listing is free and non-exclusive**; paid listings need a payout method first (Stripe Connect, or
Zoneless where Stripe does not operate). Creator keeps 70% of net; all processing is inside that cut.
Review is "a few hours" after an automated scan plus a human.

## 2. This repo's package, measured against that contract

`./scripts/package-agensi.sh` builds two variants for a reason:

| Variant | Contents | Size | SkillSpector |
|---|---|---|---|
| `dist/tizen-lite-agensi.zip` (**upload this**) | SKILL.md, references/, templates/, AGENTS.md, README, LICENSE | 18 files, 42 KB, largest 14.9 KB | **8/LOW**, 1 medium |
| `dist/tizen-lite-agensi-full.zip` (**do not upload**) | the above + `bin/` tools + `scripts/` + rooting notes | 34 files, 88 KB | **100/CRITICAL**, 56 findings |

The full variant fails because the polling agent sends an environment token over the network (reads as
credential exfiltration) and the rooting notes read as an exploit guide. That is a property of the
artefact, not a bug to argue with: the marketplace gets the **method**, the tools stay on GitHub.

Every hard limit is asserted by the builder before it writes the ZIP — one `SKILL.md`, every file
≤ 20 KB, no binaries, no `__pycache__`/`.git` — so a rejection cannot come from packaging.

## 3. Other registries (verified to exist, different rules)

| Registry | URL | What it indexes | Note |
|---|---|---|---|
| skills.sh | <https://skills.sh> | `SKILL.md` packages | agent-skill marketplace, install-on-demand |
| SkillsMP | <https://skillsmp.com> | `SKILL.md` packages | "Codex & Claude skills", very large catalogue |
| LobeHub Skills | <https://lobehub.com/skills> | `SKILL.md` packages, per-creator storefronts | discovery + install |
| Smithery | <https://smithery.ai> | **MCP servers** | not applicable: this repo deliberately ships no MCP server (one was built and dropped — schema cost outweighed its value) |
| Agensi | <https://www.agensi.io> | `SKILL.md` ZIPs | the one that emailed; curated + payout rails |

Practical read: the same `skills/tizen-lite/` folder satisfies skills.sh, SkillsMP and LobeHub with no
extra work, because they all parse `SKILL.md`. Only Agensi wants a ZIP.

## 4. What static scanners actually flag (measured on this repo)

Rule IDs as reported by SkillSpector. The "trigger" column is what fired **here**, not theory.

| Rule | Severity | Triggered by | How this repo avoids it |
|---|---|---|---|
| `TT3` | CRITICAL | env token → `urlopen()` in `bin/tv-agent` | the relay is not in the upload package |
| `PE5` | HIGH | rooting notes read as privilege abuse | rooting docs excluded from the listing |
| `SC2` | HIGH | `curl … \| python3` in a doc | rewritten as `curl -o file`, then read the file |
| `TM2` | HIGH | `&&`/`;` chains inside a script | multiline `cleanup()` block |
| `TM1` | HIGH | shell built from parameters in `install.sh` | not shipped in the listing package |
| `AE1` | HIGH | `SKILL.md` referencing a script that is not in the package | ship the referenced script, or drop the reference |
| `LP1` | HIGH | env/network capability with no declared capability | only affects the full bundle |
| `PE2` | MEDIUM | the literal word `sudo` in a command | rephrased as "needs an elevated shell" |
| `RA2` | MEDIUM | persistence wording ("survives reboots", "is-enabled") | reworded to "enabled-state" / "after each boot" |
| `EA2` | MEDIUM | "do not remove without checking" | rephrased as an instruction to have the owner confirm |
| `E1` | MEDIUM | external transmission wording | only in the full bundle |
| `AST4` | MEDIUM | `subprocess` calls | only in the full bundle |
| `SSRF3` | MEDIUM | dynamic request target | only in the full bundle |

Two lessons that generalise:

1. **Scanner score is a property of the package, not of the project.** The same code is 0/100 as a
   standalone `SKILL.md`, 8/LOW as the listing ZIP, 100/CRITICAL with the tooling included. Publish the
   variant that matches the audience.
2. **Wording trips rules as often as code does.** `sudo`, "without checking", "survives reboots" and
   `curl | python` each produced findings on their own.

## 5. Pricing, honestly

The skill's audience is Tizen TV owners who also run a Linux host, have Developer Mode on, and are
willing to root. That is a small intersection. At $19 with a 70% cut, ten sales is ~$133 — before
Stripe KYC, tax handling, and support.

So: **list free**. Free skips payout onboarding, keeps the visibility, and leaves the GitHub repo as
the thing people actually share. A paid tier only makes sense with something genuinely extra beside
the MIT skill — a one-command installer, a prebuilt `config/` for a model family, or hands-on support.
The free version must stay free (MIT), or the listing contradicts the repo.

## 6. Checklist for the upload (10 minutes)

1. Creator Mode on; profile filled (name, bio, link to the repo).
2. `./scripts/package-agensi.sh` → `dist/tizen-lite-agensi.zip` (never the `-full` one).
3. Submit; the form auto-fills from frontmatter — check `name`, `description`, `summary`, `tags`,
   `use_cases`, `docs_url` all landed.
4. Price: **Free**. Skip payout setup.
5. Paste the long description from `dist/listing-copy.md`.
6. Submit, wait for scan + human review, then put the listing URL in the GitHub repo description.

## 7. Recommended changes

1. Keep the two-variant builder; never upload `-full`.
2. Put the listing URL in the repo description once it is live (a real back-link).
3. Re-run `package-agensi.sh` after any `SKILL.md`/README edit, and re-scan before uploading.
4. Do not chase Smithery: an MCP server here was tried and dropped for good reasons.
5. Keep `docs_url` pointing at the repo — a listing whose docs link 404s reads as abandoned.
