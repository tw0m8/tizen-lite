#!/usr/bin/env bash
# Assemble the marketplace submission package (Agensi-compatible ZIP).
#
#   ./scripts/package-agensi.sh            -> dist/tizen-lite-agensi.zip      (method only)
#   MODE=full ./scripts/package-agensi.sh  -> dist/tizen-lite-agensi-full.zip (adds tools + exploit notes)
#
# Two modes exist because the full package is 100/CRITICAL to SkillSpector: the polling
# agent sends an env token over the network (looks like exfiltration) and the rooting notes
# read as an exploit guide. The marketplace gets the method; the tools stay on GitHub.
#
# Rules enforced here, so a rejection can't come from the packaging:
#   * exactly one top SKILL.md, with `name` + `description` frontmatter
#   * no file over 20 KB (their guidance), no executables, no __pycache__/.git
#   * only text formats - agents on the marketplace receive text only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$ROOT/dist/agensi/tizen-lite"
MODE="${MODE:-listing}"
if [ "$MODE" = full ]; then
  ZIP="$ROOT/dist/tizen-lite-agensi-full.zip"
else
  ZIP="$ROOT/dist/tizen-lite-agensi.zip"
fi
LIMIT=20480

rm -rf "$ROOT/dist/agensi"; mkdir -p "$STAGE"/{references,scripts,tools,templates}

# 1. the skill itself
cp "$ROOT/skills/tizen-lite/SKILL.md" "$STAGE/SKILL.md"

# 2. long-form references (the exploit-flavoured rooting notes are full-mode only)
for f in "$ROOT"/docs/*.md; do
  case "$(basename "$f")" in
    rooting*.md) [ "$MODE" = full ] || continue ;;
  esac
  cp "$f" "$STAGE/references/"
done
cp "$ROOT/agent/manifest.json" "$STAGE/references/manifest.json"
cp "$ROOT"/agent/playbooks/*.md "$STAGE/references/" 2>/dev/null || true

if [ "$MODE" = full ]; then
  # 3. scripts the buyer's agent may run (they execute as shipped)
  cp "$ROOT"/scripts/*.sh "$STAGE/scripts/"
  cp "$ROOT/install.sh" "$ROOT/restore.sh" "$STAGE/scripts/"
  # 4. the host-side tools, for people who want the automation
  for f in "$ROOT"/bin/*; do [ -f "$f" ] && cp "$f" "$STAGE/tools/"; done
else
  rmdir "$STAGE/scripts" "$STAGE/tools"
fi

# 5. editable state templates
cp "$ROOT"/config/*.example "$STAGE/templates/"
cp "$ROOT/AGENTS.md" "$STAGE/AGENTS.md"
cp "$ROOT/LICENSE" "$STAGE/"

# a short package README - the long repo README exceeds the per-file limit and is
# redundant with the listing description anyway
cat >"$STAGE/README.md" <<'RM'
# Tizen Lite

A skill for slimming down a Samsung Tizen TV: remove the ad, telemetry, ACR and promo services that
compete for one weak SoC, without breaking playback — and with every removal reversible.

- Idle RAM on the reference set: **340 → 635 MB**; swap **768 → 513 MB**; apps **51 → 33**
- Verified over repeated cold boots on a 2024 Q60D (Tizen 9.0). Unit names and app ids differ per model
  year, so treat any cut as a hypothesis on your own set.
- SkillSpector: **8/LOW** for this package (one MEDIUM finding: wording in a reference); the
  `SKILL.md` on its own scans **0/100, no findings**.

## Read in this order

1. `SKILL.md` — the method, the load-bearing list, the boot-bisect protocol, the report format
2. `references/manifest.json` — the same rules machine-readable, with the error string each wrong cut causes
3. `references/` — rooting, boot timing, debloat specifics, app uninstall, sdb audit, compatibility, FAQ
4. `AGENTS.md` — operating contract for an agent driving the work
5. `tools/` — the `tv` CLI, state applier, watchdog and polling agent (Linux host)

## Hard rules

Never remove `aaa_tvs_deamon` (DRM), `home.sidebar` + `contentservicemanager` (quick settings),
`dta-agent` (CDM), `sdbd` (root transport), `csfs`, or the configured home app.

Change one thing per cold boot — a live change cannot reveal a boot-time dependency.

## Requirements

Linux host on the same LAN (Pi or NAS is fine), `sdb` from the Tizen SDK, TV in Developer Mode with the
host's IP whitelisted. No internet service, no account.

MIT licensed. Source and issues: https://github.com/tw0m8/tizenlite
RM

# --- checks -----------------------------------------------------------------
fail=0
front="$(head -1 "$STAGE/SKILL.md")"
[ "$front" = "---" ] || { echo "FAIL: SKILL.md does not start with frontmatter"; fail=1; }
grep -q '^name: tizen-lite' "$STAGE/SKILL.md" || { echo "FAIL: SKILL.md has no name"; fail=1; }
grep -q '^description: ' "$STAGE/SKILL.md" || { echo "FAIL: SKILL.md has no description"; fail=1; }

while IFS= read -r f; do
  sz=$(wc -c <"$f")
  if [ "$sz" -gt "$LIMIT" ]; then echo "FAIL: ${f#$STAGE/} is $sz bytes (> $LIMIT)"; fail=1; fi
done < <(find "$STAGE" -type f)

if find "$STAGE" -type f \( -name '*.exe' -o -name '*.so' -o -name '*.dll' -o -name '*.bin' \
     -o -name '*.class' -o -name '*.jar' -o -name '*.wasm' -o -name '*.pyc' \) | grep -q .; then
  echo "FAIL: executable/binary file types present"; fail=1
fi
find "$STAGE" -name '__pycache__' -o -name '.git' | grep -q . && { echo "FAIL: cache/vcs dirs present"; fail=1; }

n_skill=$(find "$STAGE" -name 'SKILL.md' | wc -l)
[ "$n_skill" = "1" ] || { echo "FAIL: expected 1 SKILL.md, found $n_skill"; fail=1; }

[ "$fail" = "0" ] || { echo "packaging aborted"; exit 1; }

# --- zip --------------------------------------------------------------------
rm -f "$ZIP"
# python's zipfile instead of the `zip` binary, which is not everywhere
python3 - "$ROOT/dist/agensi" "$ZIP" <<'PY'
import os, sys, zipfile
base, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for root, dirs, files in os.walk(os.path.join(base, "tizen-lite")):
        dirs[:] = [d for d in dirs if d not in ("__pycache__", "__MACOSX", ".git")]
        for f in sorted(files):
            if f == ".DS_Store":
                continue
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, base))
PY

printf 'ok  %s\n' "${ZIP#$ROOT/}"
printf '    files %s · SKILL.md 1 · largest %s bytes · zip %s KB\n' \
  "$(find "$STAGE" -type f | wc -l)" \
  "$(find "$STAGE" -type f -printf '%s\n' | sort -n | tail -1)" \
  "$(( $(wc -c <"$ZIP") / 1024 ))"
printf '    top-level: %s\n' "$(cd "$STAGE" && ls | tr '\n' ' ')"
