# Sprite drop-in spec — IRON EDEN slice v0.1
Drop files here with these exact names; the game will prefer them over procedural placeholders when present.
All PNG, transparent background unless noted.

- player_mech.png — top-down mech, facing UP (-Y), 256x256, centered, feet/base in middle 60%
- enemy_scout.png — fast light machine, facing UP, 192x192
- enemy_heavy.png — heavy armored machine, facing UP, 256x256
- enemy_burrower.png — burrowing machine, facing UP, 192x192
- turret_autocannon.png — turret top-down, base centered, barrel UP, 192x192
- core_reactor.png — reactor / objective, 256x256 (can be non-transparent)
- ground_tile.png — seamless ground tile, 256x256, non-transparent (optional)

If a file is missing, the procedural low-poly placeholder is used — game never breaks on missing art.

## Already sliced from your sheets (2026-10-23)
player_mech.png, enemy_scout.png, enemy_heavy.png, support_mech_td.png are in this folder, keyed + QC'd.
Note: enemy_scout.png is side-oriented in its slice (rotate in engine). Front-view frames live in sliced/.
Full catalog: ../../assets/SPRITE-CATALOG.md
