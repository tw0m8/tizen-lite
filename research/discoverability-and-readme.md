# Discoverability and README — measured, not guessed

Written by hand after the delegated research died on provider rate limits (HTTP 429, NVIDIA NIM).
Everything numeric here was measured against the live GitHub API while the repo was public.

## 1. What actually moves the needle (measured)

GitHub repo search ranks **heavily on stars**. A 0-star repo lands at the bottom of any popular
query no matter how good the metadata is. Evidence — our own repo, `tw0m8/tizen-lite`, queried
after the description was optimised:

| Query | Results | Our position |
|---|---:|---|
| `samsung tv debloat` | 17 | **17th** (last) |
| `tizen debloat` | 22 | **14th** |
| `samsung tizen debloat` | 21 | **17th** |
| `tizen tv root reversible` | 3 | **2nd** |
| `agent skill samsung tv` | 5 | 5th |
| `remove tv plus samsung` | 1 | **1st (only result)** |

A second phrasing of the description ("Samsung TV debloat for Tizen 9: …" vs "Debloat a Samsung
Tizen TV — …") moved **no** position at all (16/13/16 before and after). Conclusion: **description
phrasing does not move rank.** It moves click-through and it is what Google indexes.

What it *does* control:
- the **snippet** in Google results (README + description are both indexed),
- whether someone who lands from a forum link understands the project in five seconds,
- the **topic pages**, which are separate, static listings.

So the lever is stars and external links — not wording. A repo description should therefore be
written for a human who already arrived, while the README's first lines should carry the exact
noun phrases people type.

## 2. Description: what worked

Live description (151 characters, no truncation):

> Samsung TV debloat for Tizen 9: remove TV Plus, ads, ACR and telemetry, 340 → 635 MB free RAM,
> reversible, root on demand. Agent skill, tested on Q60D.

Rules applied:
- **Exact-match head term first** — "Samsung TV debloat", not "Debloat a Samsung Tizen TV" (the
  former is a phrase people type; the latter reads better but matches nothing literally).
- **Then the highest-intent object** — TV Plus is what owners search when the channel hijacks the boot.
- **Then a number** — makes the claim credible and gives a snippet a reason to be clicked.
- **Then the differentiators** — "reversible", "root on demand".
- **Then the audience** — "Agent skill" (marketplace/search) and the tested model (compat evidence).

Keep it ≤ ~160 characters: GitHub truncates the About field in list views, and a truncated
description that cuts before "reversible" loses the differentiator.

## 3. Topics with real audiences (repos per topic, measured)

| Topic | Repos | Note |
|---|---:|---|
| `ai-agents` | 132,353 | broad, noisy, but free reach |
| `agent-skills` | 40,042 | exactly this artifact class |
| `privacy` | 35,488 | real audience for the ACR/telemetry angle |
| `adblock` | 1,939 | strong intent |
| `debloat` | 1,072 | the category word |
| `smart-tv` | 627 | broader audience |
| `tizen` | 447 | platform |
| `samsung-tv` | 246 | brand + platform |
| `home-theater` | 182 | the buying-intent crowd |
| `tizen-tv` | 90 | most precise, smallest |

Live topic set: `tizen, tizen-tv, samsung-tv, debloat, smart-tv, privacy, adblock, ai-agents,
agent-skills, skill-md` (10 of the 20 allowed). `home-theater` was left out only because the
audience skews to projectors/soundbars; worth adding if the README keeps its media-box framing.

**Niche size:** `tizen debloat` = 22 repos, `samsung tv debloat` = 17, `tizen root` = 37. Small
crowd, so ranking is reachable — but only with stars, and stars need a link from a real community.

## 4. Competitive set (as measured)

| Repo | Stars | What it does that we don't |
|---|---:|---|
| `chris-ritsen/samsung-tv-root` | 491 | the root chain itself — **we depend on it** |
| `jss8649/quiet-tizen` | 436 | native launcher + "agent-readable guide"; a *quieter* Home, not a debloat |
| `woo-jobradovic/tizen-tv-control-center` | 41 | pop-up blocker over any app; "apps truly disabled"; survives reboots |
| `cfloinc/samsung-q70t-tizen-root` | 31 | persistent debloat on a Q70T |
| `ardazeytin/samsung-tizen-tv-debloat` | 31 | "what sdb can and cannot do"; a classified package map; AGENTS.md |
| `invaliddayta/samsung-tv-tools` | 20 | root commands, remote keys, **screenshots**; community-reported model list |
| `DavidNgugi/samsung-tv-unlock` | 14 | **no-root** reversible launcher + debloat kit, Tizen 6 |

Read together: the two biggest are (a) the root chain and (b) a launcher. The people who rank
in this niche publish **one model, one method, one honest limitation** — exactly what this repo
does. The gap is that most of them publish **no numbers**; ours does, which is a differentiator
worth keeping precise rather than rounding up.

Two things they have that we don't:
1. **Screenshots.** `samsung-tv-tools` shows real captures. This firmware has no capture path
   (`enlightenment` is stripped), so a fake render is the only way — and a fabricated screenshot is
   worse than none. Keep the no-screenshot stance and say so explicitly.
2. **Community-reported model lists.** A "verified on" table plus "reported by others" is the
   cheapest honest growth lever: it makes each report worth sending.

## 5. Realistic ways to earn the first stars (no spam)

1. **One honest post in a community that already has the problem** — r/Tizen, r/SamsungTV, a
   Samsung forum thread, the Free My TV / TizenTube issue trackers. Lead with the measured numbers
   and the one thing that surprised you (the quick-settings dependency), not with a promo.
2. **A comment on the upstream projects** they already depend on (`free-my-tv`, `TizenTube`,
   `samsung-tv-root`) — upstream README links are the classic first-star source, and they are also
   the only links here that would be *earned* rather than solicited.
3. **The Agensi listing** and any agent-skill registry — these index by `SKILL.md`, and a listing
   link in the repo description gives back-link equity.
4. **Answer one question well where someone else already asked it** (e.g. "remove TV Plus on a
   Samsung TV" on Stack Overflow / Reddit) with the numbers and a link. Not a drive-by promo.

What to avoid: star rings, cross-posting the same text to ten subreddits, buying stars, or
"check out my repo" comments. All of it reads as spam and all of it is trivially detectable in a
36-repo niche where every account is visible.

## 6. README structure — what this repo already does right

- hero banner (rendered from `assets/banner.html`, not a stock template) + badge row + one-line pitch
- a **stat strip** above the fold (the thing a scannable reader actually sees)
- **Plain English, no jargon** — the counter-space analogy, plus what you *won't* notice
- **"Do I need a server?"** — the question every reader has, answered with a diagram, not prose
- an **executable quick start** (real clone URL, six ordered steps, no placeholders except the one
  value the reader must supply)
- a **must-not-remove table** with the exact error string each wrong cut produces
- **collapsibles** for the long sections, so the page scans short without losing depth
- measured before/after table, privacy section with an explicit *not claimed* list, restore
  instructions, upstream credits, MIT licence

Gaps worth closing:
- **A FAQ section.** There is `docs/faq.md`, but the README has no short one. Search traffic lands
  on questions ("does it brick", "will Netflix still work", "do I need root") — answer them on the
  page, not one click away.
- **A "what it does not do" line in the very first screen**, not only in the tables further down.
- **Screenshots are impossible** — say so once, near the top, and point at the diagram instead.
- **A first-star ask.** One line at the bottom: "if this saved you an evening, a star tells the
  next person it exists."

## 7. How other agent-skill repos present themselves

The listing form reads `name`, `description`, `summary`, `version`, `tags`, `keywords`,
`use_cases`, `docs_url` from the `SKILL.md` frontmatter. This repo already fills every one of
those. What the strong ones add:

- **use_cases written as sentences a buyer would type**, not feature names ("make a slow Samsung TV
  responsive", "stop ACR on a Tizen TV") — ours already does this;
- **a license stated in the frontmatter** — ours has `license: MIT`;
- **a `docs_url` that resolves** — ours points at the repo, which is correct;
- **a `summary` that contains the numbers**, so the listing card is worth clicking — ours does.

## 8. Top recommended changes, in order

1. Add a short **FAQ** to the README (5–7 questions) and link `docs/faq.md` for the long version.
2. Add a one-line **"what it does not do"** to the first screen.
3. Add a **first-star ask** at the bottom of the README.
4. Post the measured before/after numbers in **one** community where the problem is discussed, with
   a link — no cross-posting.
5. Ask the upstream projects (`free-my-tv`, `TizenTube`, `samsung-tv-root`) whether they will link a
   companion "debloating" page; that is an earned link, not a favour.
6. Submit the **Agensi listing** and put the listing URL in the repo description once it is live.
7. Add `home-theater` as a topic if the media-box framing stays in the README.
8. Keep the **verified-on + reported-by-others** tables current — each new model report is a reason
   for someone to star the repo.
9. Do **not** add fabricated screenshots; the no-capture-path note is more honest and more useful.
10. Revisit the description only when the README's focus changes — wording does not move rank.

## 9. Not done here

A diff of the competitors' actual service lists against ours (quiet-tizen, tizen-tv-control-center,
samsung-tv-tools, samsung-tv-unlock, samsung-tizen-tv-debloat) was interrupted before the fetch
completed. The unit/app inventory in `research/tizen-ecosystem.md` is therefore based on our own
measurements plus the sources listed there, not on a line-by-line competitor comparison.
