# Listing copy for Agensi (paste into the submit form)

## Name
Tizen Lite

## Short description (one line)
Slim a Samsung Tizen TV without breaking playback — reversible, boot-verified cuts with a symptom-to-cause map.

## Summary (used as the listing summary)
Removes the ad, telemetry, ACR and promo services that fight for one weak SoC on a Samsung Tizen TV:
idle RAM 340 → 635 MB, apps 51 → 33, and the content-recognition service that fingerprints what is on
screen is gone. Every cut is reversible, and the skill knows which ones silently break DRM or the
settings panel.

## Long description
Most "debloat your smart TV" advice is a list of package names and a hope. This one is a method.

- **It knows what must not be touched.** `aaa_tvs_deamon` is DRM: remove it and Prime Video opens but
  every video fails with *"Something went wrong. Please try again later."* The sidebar pair is the
  quick-settings panel: remove either and every control reads *"Preparing… Please try again later."*
  Neither name hints at its job, and this firmware keeps no logs to tell you.
- **It proves changes with cold boots.** Live changes hide boot-time dependencies — an acquired licence
  or a rendered panel keeps working, so a live test says "fine" when it isn't. One variable per boot.
- **It measures.** Idle RAM 340 → 635 MB, swap 768 → 513 MB, apps 51 → 33, CMA (video memory) 6 → 112 MB
  — on a 2024 Q60D, repeated cold boots.
- **It is honest about limits.** Most interface lag goes away, not all of it. Cold app launches are still
  SoC-bound. YouTube ads are not handled here.

Includes: the method, the load-bearing list with the exact error string each wrong cut produces, the
bisect protocol, the two different removal mechanics (systemd units vs package records), seven platform
traps, a machine-readable manifest, and four playbooks. Free, MIT, source on GitHub.

## Tags
samsung, tizen, smart-tv, debloat, root, privacy, sdb, performance

## Use cases
- Make a slow Samsung TV responsive by removing background services and heavy apps
- Stop ACR content recognition, telemetry and the OTA updater on a Tizen TV
- Diagnose which debloat change broke Prime Video or the quick-settings panel
- Find out whether a Tizen TV can be rooted and what root actually enables

## Price
Free. (Paid needs Stripe Connect + KYC; not worth it for this audience.)

## Link
https://github.com/tw0m8/tizenlite

## Upload
`dist/tizen-lite-agensi.zip` — 42 KB, 18 files, one SKILL.md, passes SkillSpector at 8/LOW.
Do **not** upload `dist/tizen-lite-agensi-full.zip`: it adds the host tools and the rooting notes, which
their scanner reads as credential exfiltration plus an exploit guide (100/CRITICAL).
