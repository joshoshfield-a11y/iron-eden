# IRON EDEN — Full Build Loop

## LOOP 2 — 66 PASSES (authorized 2026-10-23 ~21:05 PDT; expanded 2026-10-25, 2026-10-26)

The user escalated the loop: after Loop 1's waves, run **50 upgrade passes**
with bug testing, error correction, and code audit woven through, then on
2026-10-25 ~03:34 PDT approved the revised graphics overhaul as passes 7–9,
shifting the original passes 7–50 to 10–53 — **53 passes total**, then on 2026-10-25 ~08:45 PDT the phone-screenshot hangar/HUD hotfix was inserted as Pass 11, shifting passes 11–53 to 12–54 — **54 passes total**, then on 2026-10-25 ~08:51 PDT the battlefield-readability fix was inserted as Pass 12, shifting passes 12–54 to 13–55 — **55 passes total**, then on 2026-10-25 ~09:32 PDT the phone gameplay-video bugfix was inserted as Pass 13, shifting passes 13–55 to 14–56 — **56 passes total**, then on 2026-10-25 ~14:52 PDT the user picked a seamless-ground + phone-HUD rebuild (his video feedback: tiles still disconnected, UI incoherent) as Pass 20, shifting passes 20–56 to 21–57 — **57 passes total**, then on 2026-10-26 ~01:22 PDT the user approved five fixes (hangar overhaul, class skins, unit animation, tiles + props expansion, destructibles + item animations) as Passes 26–30, shifting passes 26–57 to 31–62 — **62 passes total**, then on 2026-10-26 ~03:36 PDT the user approved four fixes from his phone feedback (hangar whole-card tap target, template-sourced top-down unit sprites, real frame-based walk cycles, menu-template restyle) as Passes 33–36, inserted behind the already-in-flight Pass 32 (Repair Station) so its run is not disturbed, shifting passes 33–62 to 37–66 — **66 passes total**. Loop 2, then on 2026-10-26 ~10:14 PDT the user approved two fixes from his v1.39 phone screenshot (ground repetition still visible, HUD crowded/oversized with bottom content clipped off-screen) as Passes 39–40, shifting passes 39–66 to 41–68 — **68 passes total**. Loop 2
runs as cron job `iron-eden-loop2` (every 2h, one pass per run, reports to
the originating side chat). Pass list and live status: `docs/LOOP-STATE.md`.

Rules for Loop 2 passes (on top of the discipline below):
- Passes 1–4 are Loop 1's remaining Waves 3–6. Passes 5–6 are the audit and
  bug-hunt already done. Passes 7–9 are the graphics overhaul (A Units +
  camera, B World + effects, C HUD + labels + camera + perf; visuals only,
  per `docs/GRAPHICS-OVERHAUL-PLAN.md` and `assets/reference-look/`).
  Passes 10–62 follow the shifted numbered backlog in LOOP-STATE.md, in
  order. Pass 11 is the hangar/HUD phone-layout hotfix. Pass 12 is the battlefield-readability fix. Pass 13 is the gameplay-video bugfix (flat sprites, island ground, primitive core/siege, HUD clipping). Pass 20 is the seamless-ground + phone-HUD rebuild (continuous floor, no tile borders; smaller bottom panel + camera safe-area; touch instructions; high-contrast bars; bigger minimap dots + border; opaque numbered level-up; version stamp). Passes 26–30 are the 2026-10-26 user-flagged fixes (hangar overhaul, class skins, unit animation, tiles + props expansion, destructibles + item animations), in that order. One pass per run, no more.
- BUG-HUNT passes: run the auto test 10× plus any pass-specific stress
  check; log every failure/flake found in REPORT.md even if fixed in-pass;
  fix what's reproducible, file the rest as explicit known issues.
- AUDIT passes: read every script end-to-end, list findings by severity in
  REPORT.md, fix the top findings in-pass, carry the rest forward in the
  backlog notes. Never silently drop a finding.
- Versioning: pass N ships version/code = 3 + N, version/name = "1." +
  (2 + N); Pass 68 ships as 2.0 instead (code 71). Every pass runs the full gate
  script and uploads its zip; every pass reports pass number, what changed,
  test evidence, APK bytes + md5, and the download link.
- Locking: a run writes `IN_PROGRESS pass N <timestamp>` into LOOP-STATE.md
  first; if a fresh (<3h) IN_PROGRESS entry already exists, exit quietly.
- Stop: two consecutive gate failures on the same pass = mark HALTED in
  LOOP-STATE.md, disable the cron job, report. After Pass 68: mark LOOP 2
  COMPLETE, disable the cron job, deliver the final summary.
- The user's DOGBYTE keystore step (Pass 4) is prep-only: wire the preset
  fields, never invent or generate a keystore in the user's name.

---

Started 2026-10-23 ~20:46 PDT on the user's word ("begin full build loop").
This loop takes the vertical slice to the Phase 2 core defined in
`docs/SCOPED-PLAN.md` §4. The GDD stays the vision; the scoped plan stays the
scope contract; this file is the execution queue.

## Canonical tree

- **Canonical: `~/workspace/iron-eden/prototype/`** — the fuller slice
  (free placement, power radius, heat, directional armor, disable→capture,
  burrowers, Siege Platform, substation choice, Mech Memory, world save).
- **Reference: `~/workspace/iron-eden/` (root tree)** — the earlier prototype.
  Its proven features (XP/level-up, salvage caches, adaptation report,
  endless continue, right-stick aim) are ported into the canonical tree by
  the loop, wave by wave. Root tree is not built or shipped anymore.
- User sprites live in the canonical tree at `prototype/sprites/`
  (top-down set in-game; full Sheet-1 animation sets at `sprites/anim/`).

## Loop discipline (every wave, no exceptions)

1. Implement the wave's listed features only. Scope creep goes to the queue.
2. Extend the automated test (`-- --iron-eden-test`) to cover every new
   mechanic with a direct, falsifiable check.
3. Gate: headless auto test PASS with zero script errors → Android debug
   export → apksigner verify → zip deliverable with exact byte count.
4. Update `prototype/REPORT.md` (wave section) + `docs/LOOP-STATE.md`.
5. **Stop condition:** two consecutive gate failures on the same wave =
   halt the loop, report the failure honestly, do not paper over it.
6. Nothing is published, pushed, or release-signed by the loop. APKs are
   debug-signed until the DOGBYTE keystore step (Wave 6, user's pass).
7. Every feature must serve a pillar (SCOPED-PLAN §2) or it doesn't ship.

## Wave queue

### Wave 1 — Progression & Adaptation (port the root prototype's RPG layer)
- XP from kills/captures; level-up with 1-of-3 upgrades
  (+25% damage / +20% fire rate / +30 hull & repair) — pause-and-pick panel
- Third weapon: **Scattergun** [3] — 5-pellet spread, mechanically distinct
- Kill-split tracking (mech vs turret) → telegraphed **adaptation report**
  on the victory screen + saved `adaptation` flag in the world save
- Salvage caches in the arena (+20 salvage, +1 XP, respawn at new spots)
- **Endless defense** continue after victory (procedural waves 4+)

### Wave 2 — Hangar & Loadout
- Pre-run hangar screen: chassis pick (Scout / Assault / Support — data-
  driven stats + the sliced top-down sprites), utility pick
  (Repair Pulse first; Grapple if it proves cheap), weapon loadout confirm
- Loadout persists in the world save; Sheet-1 anim portraits in the hangar

### Wave 3 — Deployables II + Shield Heavy
- Mortar turret (indirect AoE) as a salvage-funded unlock; EMP pylon
  (periodic disable pulse, powered)
- Shield-heavy enemy variant in wave 2+ (frontal shield generator —
  flank or focus it, per scoped plan)
- Power-line visuals between generator and powered turrets

### Wave 4 — Allied Drone + Doctrines Lite
- Engineering drone ally: auto-repairs structures / fetches salvage
  caches, command-lite (follow / hold) — proves the allied-unit pillar
- Three doctrine presets (Iron Wall / Hunting Pack / Ghost Protocol)
  as run modifiers chosen in the hangar

### Wave 5 — World Expansion
- Region 2 arena (variant layout + palette, picked from the hangar)
- Recovery contract: a Damaged Outpost save unlocks a repair-the-outpost
  run; adaptation flag from the save actually spawns its counter in-game

### Wave 6 — Touch, Tiers, Signing Prep
- Right virtual stick aim/fire (port the root tree's joystick UI)
- S25 perf pass: draw-call count, adaptive quality toggle;
  Forward+ desktop tier switch
- Release signing prep: wire DOGBYTE keystore if provided (user's step)

### Phase 2 gate
After Wave 6: full review against SCOPED-PLAN §4 with the user.
Phase 2 content (Bloom faction, base modules, crafting) is a new
commission, not a loop assumption.

## Versioning

Wave N ships as version 1.N (code N+1). Wave 1 = v1.1.
