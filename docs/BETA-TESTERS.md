# IRON EDEN — Beta Testers

Human beta-tester logic, translated into checks that can actually run in this
sandbox. Four testers, each with a persona, a checklist, and a verdict.
The sandbox proves geometry, files, numbers, and error-freedom — never the
in-hand look on the S25. Anything under "Device-only" stays the user's job
on his phone; it is listed, not silently dropped.

## Roster

### 1. Pixel — Graphics tester
Human logic: "Does it look right? Are sprites actually showing? Does the
ground tile? Does anything float or sink?"
- Every texture path referenced in `scripts/*.gd` resolves to a real file.
- Every PNG shipped in `sprites/` has a matching `.import` file (missing
  imports were the Pass 27/34 failure class — the game fails its own test
  without them).
- Every PNG parses, is non-empty, and has sane dimensions (1–4096 px).
- Ground repeat value in code is the Pass 39 value (2x), not the old 6x.
- Pass 34/35 art dirs (`sprites/p34/`, `sprites/p35/`) are present.
- Device-only: in-hand look, readability at arm's length, whether walk
  cycles read as moving limbs, whether the ground still wallpapers.

### 2. Crash — Stability / errors tester
Human logic: "Does anything crash, freeze, or throw errors?"
- Runs the real headless auto test (`-- --iron-eden-test`) with a timeout.
  A hang is a FAIL, not a skip (parse errors hang this harness by design).
- Zero `SCRIPT ERROR` lines and the `IRON EDEN AUTO TEST: PASS` line.
- The built APK on disk passes `apksigner verify` and its zip is intact.
- Hard gate, never waived: any error fails the whole run.

### 3. Rules — Gameplay / bug tester
Human logic: "Can I break the numbers? Does anything go negative, stall,
or disagree with itself?"
- Auto test PASS with zero `TEST FAIL` lines.
- Version-stamp bug class: the in-code version stamp matches
  `export_presets.cfg` (this lag recurred on Passes 24, 42, 43, 44).
- APK badging matches the expected package (`com.dogbyte.ironeden`),
  version, and code for the build under test.
- No `TEST FAIL` lines anywhere in the test log.

### 4. Flow — UI / UX tester
Human logic: "Can I reach everything? Does anything clip off-screen?
Is the HUD within its budget?"
- HUD budget math from code constants: top bar + bottom panel (+ message
  + preview when visible) under the Pass 40 caps (typical ≤ 208 px,
  worst case ≤ 286 px on the phone viewport).
- Icon buttons carry `expand_icon = true` (the Pass 40 bug class: ~480 px
  icons rendered at 488x434 in 50x44 slots).
- Touch hint text contains no WASD directions.
- Build-bar width fits the viewport width.
- Device-only: touch feel, button readability at arm's length, whether
  the consolidated HUD actually feels roomier.

## Harness

`prototype/tools/beta-testers.py` — read-only against the project tree.
It runs the headless auto test once, audits the tree and the built APK,
and writes one report per run to `qa/`:

`qa/beta-report-<version>-<yyyymmdd-hhmm>.md`

Report format: overall PASS/FAIL, one section per tester with PASS/FAIL/
WARN per check plus evidence (file, line, or log excerpt), the build
identifier (version/code/md5), and the device-only list. A FAIL in any
tester fails the run. Warnings are listed separately, never folded into
PASS.

## Loop wiring (user-approved 2026-10-26)

The loop cron (`iron-eden-loop2`) runs the beta testers as step 10 of
every pass, after the pass's lock is cleared: `python3
prototype/tools/beta-testers.py`, verdict appended to that pass's REPORT.md
section and reported in the pass report. A beta FAIL or SKIPPED never
halts the loop and never overrides a gate PASS — it is a signal for the
next pass or the parent to follow up.

1. Test the build on disk, never a stale APK: the harness records the
   APK's bytes + md5 and refuses to report a version it cannot match to
   `export_presets.cfg`.
2. Same build, same harness, same verdict — reruns are comparable; a
   changed build is a new baseline.
3. Harness bugs are not game bugs: if a check itself is wrong, fix the
   harness, note it, and re-run before reporting anything about the game.
4. Sandbox fps/render time is never presented as S25 performance.
5. A beta run never edits game code, presets, docs, or saves.
6. Never audit a moving tree: if LOOP-STATE.md shows a loop lock
   IN_PROGRESS, the harness writes a SKIPPED report and issues no verdict.
   Otherwise it snapshots the tree first and tests the snapshot, so a
   worker starting mid-run cannot turn a verdict into a race artifact.
