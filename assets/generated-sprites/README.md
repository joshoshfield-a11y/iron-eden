# IRON EDEN — Generated sprite sheets (2026-10-25)

Made with image generation, in the style of the user's templates
(`../reference-look/`). QC'd by eye on 2026-10-25: all items present,
no text, no UI, solid black backgrounds (ready for flood-fill keying to
transparency), consistent style across all three sheets.

- `mechs-sheet.png` (2240×1120) — 8 mechs, 2 rows of 4.
  Top (blue/white player side): Heavy Assault (shield + cannon),
  Light Scout (rifle), Artillery (dual shoulder cannons),
  Tank-Legged Defender. Bottom (red enemy side): Spider-Legged Walker,
  Red Raider (blade), Heavy Red Brute, Small Red Drone.
- `tiles-sheet.png` (1920×1280) — 15 isometric tiles, 3 rows of 5.
  Grass, dirt path, rocky cliff, water, shoreline, dark metal platform,
  metal gate, pine trees, rock + glowing blue crystal, burning wreck,
  solar panels, gun turret, supply crate, mossy stone floor, rusted
  metal wall.
- `weapons-sheet.png` (1920×1280) — 12 weapons/modules, 3 rows of 4.
  Plasma Rifle, Heavy Gatling Cannon, Missile Pod Launcher,
  Single Homing Missile, Rail Gun, Energy Sword, Shoulder Rocket
  Launcher, Flamethrower, Laser Beam Emitter, Shield Generator Module,
  Combat Drone, Grenade Launcher.

Not yet in the game. Next step is Loop 2 Passes 7–9 (graphics overhaul):
slice each sheet into individual sprites, key black to transparency,
QC silhouettes from above, then wire them in as unit / terrain / HUD
icon art. Do not generate a second set before slicing this one — these
are the canonical generated set unless the user says otherwise.

## Second batch (2026-10-25 ~03:49 PDT) — the rest of the sprites

- `enemies-sheet.png` (1920×1280) — 8 enemy units, 2 rows of 4.
  Burrower, Siege Platform, Shield-Heavy (cyan shield panel),
  Sapper Drone, Lancer, Bulwark, Swarm Carrier (with launched drones),
  Siege Platform MK2.
- `structures-sheet.png` (2240×1120) — 8 deployables/structures.
  Core Reactor (blue crystal on octagonal platform), Generator,
  Turret, Barricade, Mortar, EMP Pylon, Repair Station, Sensor Tower.
- `effects-sheet.png` (1920×1280) — 12 effects/pickups, 3 rows of 4.
  Autocannon tracer, Railgun beam, Scattergun pellets, Mortar shell,
  EMP pulse ring, Explosion burst, Stun bubble, Shield panel,
  Muzzle flash, Salvage cache, Repair cross, Capture diamond.
- `allies-sheet.png` (1920×1280) — 8 allies/objectives, 2 rows of 4.
  Engineering Drone, Allied Scout/Heavy/Support (green trim),
  Substation, Sealed Tunnel, Salvage Cache, Command Beacon.

Total generated set: 7 sheets, 67 sprites (8 mechs + 15 tiles + 12 weapons
+ 8 enemies + 8 structures + 12 effects + 8 allies, counting the
swarm carrier's launched drones as part of its sprite).
