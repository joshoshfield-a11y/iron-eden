# IRON EDEN — Graphics Overhaul Plan (DRAFT, awaiting user approval)

Status: PLAN ONLY — nothing has been changed in `prototype/`. The Loop 2 backlog
(Pass 6 onward) keeps running unless the user approves one of the options below.
Written 2026-10-25, from a code read of `prototype/scripts/*.gd` (not from screenshots).

## REVISION 2026-10-25 ~03:31 PDT — user reference images (saved untouched in
`assets/reference-look/`)

The user sent two reference images and said graphics "should look like this
ish". They supersede the generic "clean low-poly" direction in §3 where they
conflict. What to take from them, specifically:

**Gameplay image — the target look:**
- Angled isometric view, NOT straight-down top-down. Buildings and ruins
  have visible height and depth; the ground is textured dark stone with
  teal moss, rubble, glowing cyan crystals and purple flora — not a flat
  plane. Camera change is therefore part of the overhaul: pitched camera
  (not ortho size-50 straight down), with ground-point touch mapping and
  aim re-tested after the change.
- Units pop against the dark ground: player/allied mechs detailed blue/white
  with a cyan ring under the player only, green bars over allies, red bars
  over enemies. Enemies are small red spider-like units plus larger red/green
  heavies — silhouette + color, not labels.
- One glowing focal objective: a blue crystal relay tower on an octagonal
  platform. Our equivalent is the Core reactor — it must read the same way
  at a glance.
- HUD, all in one dark-navy + cyan-border panel language: top-left portrait
  + HP (red) + EN (cyan) bars + small icons; top-center objective text;
  top-right wave counter + minimap (dark panel, cyan diamond = player,
  red triangles = enemies, green = allies); bottom-left virtual joystick;
  bottom-right ability cards with icons and counts.
- Palette: deep navy/teal world, cyan UI and glows, warm orange tracers and
  explosions. Moody, but units are brighter than the ground.

**Menu-systems image — the long-term UI direction, NOT the immediate job:**
- The same dark-navy + cyan panel system across main menu, world map,
  character profile (LV/HP/EN/STR/SPD/INT/DEF), equipment loadout,
  quest log, inventory grid, skill tree, base build, crafting, pause menu,
  settings, and faction reputation bars. That is a full UI system for the
  finished game; the current slice only has a hangar panel. Treat it as the
  skin and layout standard for every future UI pass (starting with the
  hangar and pause menu), not as something the graphics overhaul builds
  in full now.

**Honest limit (must be stated, not smoothed over):** recoloring the
existing primitives will only get partway to this look. The reference's
detail comes from painted textures and detailed mech art. The overhaul
therefore needs new texture/sprite work (ground texture, ruin/crystal
props, mech trim/detail textures, UI panel skin) in addition to code —
either generated in this style or drawn from the user's supplied sheets
where they fit. The plan below is updated accordingly: Pass A now includes
the camera pitch + unit detail pass, Pass B includes ground/prop textures,
Pass C includes the full HUD skin + minimap + menu-panel standard. Numbers
in the reference (HP 1240, wave 3/5, etc.) are NOT copied — only the look.

## REVISION 2 — 2026-10-25 ~03:41 PDT — standing sprite rule (user's words)

**Rule, all future games, not just IRON EDEN:** when a game needs sprites,
generate sprite templates with image generation first — in the style of the
templates the user sends — and use those. Never start from coded-up
primitive shapes and ship pong-style graphics. Coded geometry is a
placeholder at most, never the look.

Three new templates saved in `assets/reference-look/` (phone screenshots,
saved untouched — the usable art is the central panel in each; they are
style catalogs, not clean sheets, so they are NOT sliced straight into the
game):
- `tiles-template.png` — isometric tiles: grass, dirt path, cliff, water,
  shoreline, metal platform, gate structures, pine trees, rock + blue
  crystal, burning wreck, solar panels, gun turret, supply crate.
- `weapons-template.png` — Plasma Rifle, Heavy Gatling Cannon, Missile Pod
  Launcher, Single Homing Missile, Rail Gun, Energy Sword, Shoulder Rocket
  Launcher, Flamethrower, Laser Beam Emitter, Shield Generator Module,
  Combat Drone, Grenade Launcher.
- `mechs-template.png` — 1 Heavy Assault Mech, 2 Light Scout Mech,
  3 Artillery Mech, 4 Tank-Legged Defender Mech (blue player side),
  5 Spider-Legged Walker, 6 Red Raider Mech, 7 Heavy Red Brute,
  8 Small Red Drone Mech (red enemy side).

**How this changes Passes 7–9 (LOOP-STATE already updated):** Pass A
generates unit sprite templates in the mechs-template style and uses them
for player/enemy bodies; Pass B generates terrain/prop sprites in the
tiles-template style for the ground; Pass C generates weapon/ability icons
in the weapons-template style for the HUD cards. Every generated sheet
gets sliced, keyed to transparency, and QC'd (silhouette readable from
above, friend/foe color unambiguous) before it ships in an APK — same
gate as every other pass. If image generation is unavailable in a given
run, the fallback is the user's supplied sheets, not primitives.

## 1. The problem, as it stands in v1.7

The current look is placeholder art in two languages at once, and it fails the
one test that matters on a phone: at a glance, can you tell what is you, what
is an enemy, what is a building, and where everything is facing?

- **Mixed unit rendering.** The player mech is a flat top-down sprite plane
  (`player.gd`) with a boxy 3D hull built on top of it. Scouts and heavies are
  flat sprite planes; burrowers, siege platforms and bosses are primitive
  boxes/cylinders/spheres (`enemy.gd`). Silhouettes are inconsistent, and the
  sprite-plus-hull double image is the single most confusing thing on screen.
- **Indicator soup.** Power radii (28 m core / 22 m generator, faint huge
  discs), EMP radius disc, cyan stun bubble, orange disabled bubble, cyan
  shield panel, cyan power lines rebuilt 2x/s, muzzle/explosion flashes —
  mostly cyan and orange, all on at once, all similar shapes.
- **Floating 3D labels.** "SUPPORT MECH (offline)", "SUBSTATION [E]",
  "SEALED TUNNEL", "REGION 2 — RUST FLATS" billboard over the action.
- **Flat, low-contrast world.** One dark ground plane (0.14, 0.15, 0.18) with
  faint stripes, 30 randomly scattered grey/brown ruin boxes, glowing cyan
  arena walls. Units, props and ground sit in the same dark value range.
- **Small on a phone.** Orthographic camera, size 50, whole arena in view.
  HUD labels are plain top-left text; nothing scales its importance by
  distance or danger.

## 2. Overhaul principles (in priority order)

1. **Readability beats fidelity.** A player at arm's length must read
   friend / foe / building / direction in under a second.
2. **One visual language.** All in-game units are low-poly 3D. Sprites stay
   only where they already work: hangar portraits (Sheet-1 front/side art).
3. **One color code, used everywhere.** Player = cyan/white trim. Allies
   (drone, turrets) = green trim. Enemies = red/orange. Core = blue glow.
   Shields = cyan, stun = cyan ring, disabled = orange diamond — never the
   same shape twice for two different states.
4. **Silhouette before detail.** Each class reads by outline alone, from
   directly above: Scout slim and long, Assault broad, Support with a beacon
   mast, Heavy blocky, Shield-heavy with a front panel, Burrower low wedge,
   Siege Platform huge rectangle.
5. **Show state only when it matters.** Power rings and power lines appear
   in build/placement mode or on selection, not permanently. Labels appear
   only in range, or move to the HUD/minimap.
6. **No perf regression.** S25 budget stands: ≤150 draw calls, 30 fps floor.
   Every overhaul pass reports headless draw-call / object / primitive counts
   before and after (same `measure_perf()` monitors Pass 4 added). If a visual
   upgrade blows the budget, it gets cut or gated to the Forward+ tier.

## 3. The work, in three loop passes

Splitting it keeps the loop gate green at each step instead of one giant
all-or-nothing rewrite. No gameplay numbers change in any of these passes:
no damage, HP, speed, salvage, spawn or balance edits — visuals only.

### Overhaul Pass A — Units (the biggest win)
- Remove the flat sprite planes from player and enemy bodies
  (`player.gd`, `enemy.gd`). Keep the existing 3D hull/box construction and
  extend it into distinct per-class low-poly bodies: hull, turret/head,
  barrel(s), tread or leg hints, trim stripe in the class color.
- Add a facing indicator to every unit: a short nose/barrel chevron on the
  front, plus a subtle ground-facing wedge under the player. This also
  retires the known scout-sprite facing question (+90° offset) — facing
  becomes geometry, not a sprite rotation guess.
- Health: thin arc/ring under each unit (green → amber → red), replacing
  reliance on the 3D body tint change. Disabled units keep the orange
  diamond marker; stunned units keep the cyan ring — different shapes,
  different colors, no overlap.
- Turrets, generators, barricades, mortar, EMP pylon, repair station:
  same treatment — one trim color per type, a clear barrel/dish direction,
  a small powered/unpowered lamp (on = lit, off = dark) instead of a
  permanent radius disc.
- Hangar portraits unchanged (Sheet-1 art already reads well there).
- Tests: new falsifiable checks that each class builds a body with a
  facing marker, the correct trim color, and no sprite plane child.

### Overhaul Pass B — World and effects
- Ground: replace the single flat plane with a readable ground — subtle
  grid + panel seams + a lighter core plaza around the reactor, so the
  player's position and the core's position read instantly. Keep the
  Region 2 rust tint, but as ground color, not as a translucent overlay
  plane (the current overlay washes everything out).
- Props: cluster the 30 ruin boxes into 4–6 readable ruin groups with gaps
  between them (cover that reads as cover), instead of random scatter.
  Arena walls lose the cyan glow; they become dark retaining walls with a
  thin top edge.
- Effects declutter: power lines thinner, drawn only core/generator →
  powered structures, and dimmed outside build mode. Muzzle flashes and
  explosions smaller and shorter. Shield panel opacity now tracks shield
  strength (full = solid, breaking = faint).
- Lighting: sun angle and ambient tuned for contrast (units lighter than
  ground, not the same dark range). Fog density checked so distant units
  do not wash out.
- Tests: ground grid present, ruin groups clustered (max nearest-neighbor
  distance asserted), power-line count and opacity rules, shield opacity
  vs shield HP.

### Overhaul Pass C — HUD, labels, camera, perf verification
- Labels: remove floating 3D labels except the core and the substation
  prompt, and show those only within interaction range. Everything else
  (tunnel gate, parked support mech, region name) moves to the hangar text
  or the wave line, or is deleted.
- HUD: regroup into three zones — top-left status (hull/heat/core),
  top-right wave + doctrine + region, bottom build bar — with a dark
  backing strip for contrast. Larger, bolder numbers for salvage and core HP.
  This dovetails with Pass 10 (minimap) and Pass 44 (colorblind palette):
  the overhaul uses shapes as well as colors, so the colorblind pass has
  something to build on.
- Camera: add a small zoom step (pinch or a hangar toggle) so phone players
  can pull in closer than the current size-50 full-arena view. Default view
  unchanged for laptop.
- Perf verification: full before/after table (draw calls, objects,
  primitives, headless FPS monitors) in REPORT.md, S25 vs Balanced vs
  Forward+ tiers. Any regression over the S25 budget is fixed in-pass or
  the offending visual is cut.
- Device checklist for the user (cannot be proven in the sandbox): at
  arm's length, can you tell player/enemy/building/facing in under a
  second? Is the core visible at all times? Do power lines still make
  sense in build mode?

## 4. What this plan deliberately does NOT do

- No new weapons, enemies, mechanics, or balance changes.
- No new art assets to commission (all procedural low-poly, same as now).
- No sprite-only rewrite: going all-sprite would throw away the Godot 3D
  decision (2026-10-23) and the existing 3D structures, for a look the
  supplied sheets were not drawn for (Sheet-1 is front/side, not top-down).
- No change to the hangar portraits, which already work.
- No release signing, no publishing, no keystore (unchanged loop rules).

## 5. How it slots into Loop 2 (decision needed)

Option 1 — **Next, as three passes.** Insert Overhaul A/B/C ahead of Pass 6,
then resume the backlog. Loop version numbering continues as normal
(one version bump per pass). Cost: three loop cycles before Flak Cannon
and the rest of the backlog resume.

Option 2 — **After Pass 50.** Finish the current 50-pass backlog first,
then run A/B/C as a follow-up track. Cost: the confusing visuals stay
until v2.0 ships.

Option 3 — **Revise this plan.** The user names what is wrong or what
style they want (e.g. darker, brighter, more neon, more military), and
the plan is rewritten before anything is built.

## 6. If the user sends a screenshot

A phone screenshot of the exact confusing screen would still help: it
would confirm which screen is worst (hangar vs in-game vs wave 3 chaos)
and whether the problem is units, terrain, or HUD. It is not a blocker —
the code read already justifies Passes A–C — but it would let Pass A
target the worst offender first.
