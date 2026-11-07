# IRON EDEN: MOBILE — v0.1 Prototype Report

Built 2026-10-23 (PDT) in this chat, following the scoped plan in `docs/SCOPED-PLAN.md`
and the mobile GDD the user delivered the same evening.

## What this is

Phase 1 core-combat prototype (GDD §23) with the tower-defense and RPG loops
wired in, set in the scoped plan's "Defend the Last Reactor" operation:

- **Top-down 3D** in Godot 4.8 (Mobile renderer), angled orthographic camera
  that follows the mech. Procedural low-poly mechs/terrain, no external assets.
- **Twin-stick combat** — WASD/arrows + mouse on desktop; left virtual stick
  moves, right virtual stick aims and fires on touch. Smart targeting
  assistance (GDD §3.1) auto-fires at the nearest hostile when the aim stick
  is not held. Dodge/dash on Space/Shift or the DODGE button.
- **Active tower defense** — enemies march on the reactor core. 8 glowing
  build pads; tap/click a pad, press 1-8, or use BUILD TURRET to place an
  auto-turret for 50 salvage. The player fights inside the defense, never in
  a separate TD mode.
- **3 enemy types** — runner (fast/fragile), grunt, brute (slow/tanky),
  scaling HP per wave.
- **Waves** — the operation is 3 waves. Clearing wave 3 is a victory.
- **RPG progression** — kills and salvage caches grant XP; level-up pauses
  for a 1-of-3 upgrade (+25% damage / faster fire / +30 hull + repair).
- **Explore → Salvage** — glowing salvage caches scattered across the arena
  (+20 salvage, +1 XP), respawning at new locations.
- **Persistent consequence (Pillar 3, lite)** — victory writes
  `user://ironeden_save.json`: facility state (forward base if core ≥ 60%,
  else damaged outpost), core %, level, kill split. The victory screen shows
  the outcome plus a telegraphed adaptation scout report based on whether
  turrets or the mech did most of the killing (tunneling units vs shielded
  heavies). Endless defense can be continued after victory.

## Verification (all run headless in the sandbox, 2026-10-23)

- Automated playtest `-- --ironeden-test`: **PASS**, zero script errors.
  Exercises: world/pads exist, turret builds on 2 pads + occupied-pad refusal,
  wave director starts, auto-fire/turrets score kills, XP and a level-up,
  damage upgrade applies, core takes damage, victory triggers and the
  world-state save file is written (sample run: kills 3-6, level 1-2,
  victory state `forward_base` at 93% core).
- Android export (debug preset): **PASS**. APK verified with apksigner
  (exit 0) and aapt2 badging.

## APK

- Package: `com.dogbyte.ironeden`, version 1.0 (code 1), minSdk 24, compileSdk 36
- Size: **27,571,946 bytes**, md5 `99c97b23fc1d992da1a3c3d4b864c68f`
- Signing: Godot debug keystore (auto-generated). A release build needs the
  DOGBYTE keystore wired in — same step STARFALL/DUSKFALL took later.
- On-device run on the S25 is still the user's pass; nothing here proves
  phone FPS or touch feel.

## Not in v0.1 yet (sequenced, per scoped plan §3-§5)

Free placement (pads first), generator + power network, barricade/mortar/EMP
deployables, weapon mounts/swapping (autocannon only), heat/reactor system,
component damage and disable-vs-destroy salvage, directional armor, the
substation choice, hangar/loadout screen, allied drone, burrower and siege
platform enemy types, Forward+ desktop tier switch.
