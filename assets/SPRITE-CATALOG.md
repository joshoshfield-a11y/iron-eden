# IRON EDEN — user sprite sheets, catalog (received 2026-10-23 20:15 PDT)

Originals archived in `assets/source-sheets/` (never edited in place).

| File | Sheet | Contents |
|---|---|---|
| sheet1-mech-sprite-template.png (1024x1536) | Mech Sprite Template, 64x64/frame | 5 classes (Scout/Assault/Tank/Sniper/Support) x 4 directions (Front/Side/Back/3/4) x 7 states (Idle/Walk1/Walk2/Attack/Dash/Hurt/Destroyed). FRONT/SIDE hybrid view — best for billboards, portraits, hangar UI, or a future 2D mode. Not top-down. |
| sheet2-game-assets-v1.jpg (1408x768) | Game Assets Template v1 | Top-down chassis (Scout/Assault/Siege/Strider/Support/Experimental), components, weapons, deployables, blueprints, constructions, allies, environments, resources, faction terrain, base modules, UI icons, enemy factions, bosses (Directorate Siege Platform, Deep Network boss). |
| sheet3-game-assets-v2.jpg (1408x768) | Game Assets Template v2 (variant) | Same layout, different chassis set: spider Scout, tank Assault/Siege, Strider, Ghost (triangular stealth), Titan; bosses = Scalping Tank + Network Fractal Mech. Slight-variation pair with v1 — both kept. |
| sheet4-weapons-customization.jpg (1408x768) | Weapons & Customization | Melee/primary/secondary/heavy weapons, energy/sensor/defense/utility modules, mastery frames, AI profiles, pilot disciplines, faction tech. Uploaded TWICE (two files, byte-identical, 100% pixels same) — one copy archived. |
| sheet6-chassis.jpg (1408x768) | Mech Chassis Sprite Sheet | 20 chassis variants in 5 classes: Light (hover-bike, spider scout, infiltrator drone, light biped), Medium (assault/vanguard/support biped, assault hover), Heavy (tracked siege, siege biped, juggernaut, multi-track artillery), Special (strider, ghost, hybrid, cloaked sniper), Massive (walker fortress, titan siege, multi-track colossus, experimental titan). Mostly front view; hover/ghost are top-down. |

## Sliced for the slice build (prototype/sprites/, 256x256, flood-fill keyed, QC'd on dark contact sheet)
- `player_mech.png` — Assault top-down (sheet2). Upright orientation.
- `enemy_scout.png` / `player_scout_td.png` — Scout top-down (sheet2). SIDE orientation in the slice (nose/thruster horizontal) — engine must apply a rotation offset for this one.
- `enemy_heavy.png` — Siege top-down (sheet2). Upright.
- `support_mech_td.png` — Support top-down (sheet2). Upright.
- `sliced/front_assault_idle.png`, `front_scout_idle.png`, `front_tank_idle.png` — sheet1 front-idle frames. Keyed, chunkier edges, some dark-detail loss on scout/tank — alternates/portraits only, not primary in-game sprites.

## Sliced 2026-10-23 (second pass, on the user's word)
- Full sheet1 animation sets: 140 frames (5 classes x 4 dirs x 7 states), 160x160 keyed, in `prototype/sprites/anim/` with manifest.json + README (method + caveats). QC contact sheets in `assets/qc/anim-<class>.png`. 138/140 clean on auto pass; support_side_attack + sniper_front_idle hand-repaired and re-verified.

## Still to slice on demand (not blocking the slice)
Turret/generator/core from sheet2, deployables + boss sprites, all of sheet3's variant chassis, weapon/module icons from sheet4 for the hangar UI.

## 2026-10-26 re-send (user's "game should look like this" batch)
- `source-sheets/2026-10-26/mech-chassis-sprite-sheet.jpg` — 5 chassis classes x 4 variants, 3/4-view bipeds/tracked/striders. NOTE: the top-down frames the game needs are in the Game Assets Template's chassis column, not this sheet's bipeds.
- `source-sheets/2026-10-26/mech-weapons-customization.jpg` — weapons/modules/progression icons (dup of the other weapons sheet in this batch).
- `source-sheets/2026-10-26/game-assets-template.jpg` — KEY SHEET: left column "MECH CHASSIS (Frames)" = true top-down SCOUT/ASSAULT/SIEGE/STRIDER/SUPPORT/EXPERIMENTAL frames; also deployables, scenery, resources, base modules, enemy factions, bosses. This is the target look for in-game units.
- Re-sends of existing reference-look images: menu-systems-template, gameplay-reference, gameplay-wave-reference (identical bytes to reference-look/).
- User verdict on Pass 28 (2026-10-26 ~03:35 PDT): procedural bob/lean reads as "weird bouncy animation, flat paper that bounces, sprite otherwise static" — NOT accepted as walking. Real walk cycles must be frame-based with moving limbs.
- User verdict on Pass 26 hangar (same message): selection only works via the small SELECT button at the card base; portrait/panel taps do nothing. Tap target must be the whole card.
