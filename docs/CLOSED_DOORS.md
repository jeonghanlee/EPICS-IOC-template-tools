# Closed Doors

Examined-and-kept verdicts, so a later review does not pay to re-open a door
already checked closed. Each entry is a candidate that a coherence sweep looked
at and decided needs no structural change, with the premise that makes the
divergence principled. These are **not** tracked work items; open findings live
in `docs/milestone-574face.md`.

Evidence is given by file and symbol (durable across line-number drift), not by
line number.

## 2026-08-17 — Conceptual-integrity sweep of the base-missing recovery workstream

A whole-workstream coherence review (the `conceptual-integrity` skill) of the
base-missing recovery makefiles. Five agreement-points surfaced; all five
resolved to Keep. The carrying change is the same-day comment pass that made the
three seams visible (cross-reference comments; no behavior change).

- **CI-1 — Keep (seam made visible).** The `configure/RELEASE.local` write
  policy (refuse-unless-`FORCE`, show the current value, write `EPICS_BASE=`) is
  implemented twice: `conf` (`configure/RULES_ALSU`) and the `alsu-base-missing`
  recovery target (`configure/CONFIG_ALSU`). Premise: `conf`'s value is a make
  variable (`ALSU_ENV_BASE`, known at parse time) while the recovery target's is
  a shell variable (`$chosen`, computed at recipe runtime), so a make canned
  recipe cannot serve both; a shared shell function would still have to live
  where a subdirectory recovery sees it (the CI-2 self-containment premise),
  buying little for ~4 shared lines (Ockham). Kept as two copies with
  cross-reference comments in both files instead of consolidated.

- **CI-2 — Keep (principled duplication).** The RELEASE.local path is held in two
  variables: `RELEASE_LOCAL` (`configure/RULES_ALSU`) and `ALSU_REL_LOCAL`
  (`configure/CONFIG_ALSU`). Premise: a subdirectory recovery (`make -C
  configure`) does not include `RULES_ALSU`, so `CONFIG_ALSU` must define its own
  copy or the recovery write path would expand an empty path. Real constraint,
  not an invented one. Kept, with a "why two" note added.

- **CI-3 — Keep (seam made visible).** The site-target set is enumerated in two
  places: the stray-goal exemption `ALSU_SITE_GOALS` (`configure/CONFIG_ALSU`)
  and the `##` annotations that `site-help` scans (`conf`, `site-help` in
  `configure/RULES_ALSU`). Premise: deriving one from the other needs a
  parse-time `$(shell)` grep; the hardcoded two-word list plus a cross-reference
  comment is lower entropy. Kept, with a "keep in sync" comment added.

- **CI-4 — Keep (cosmetic).** The tracked `configure/RELEASE` substitution writes
  `EPICS_BASE = <path>` (spaces) while `conf` and the recovery target write
  `EPICS_BASE=<path>` (no spaces). Premise: make parses both identically. No
  change.

- **CI-5 — Keep (single-source, verified agreeing).** The recovery guard flag
  `ALSU_BASE_FOUND` is defined once in `configure/CONFIG` and consumed at five
  sites — `configure/CONFIG` (`ifeq`), `RULES`, `RULES_TOP`, `RULES_DIRS`,
  `RULES.ioc` (all `ifneq`) — with consistent polarity. Verified all five
  reference the same variable and agree. Principled single source; no change.
