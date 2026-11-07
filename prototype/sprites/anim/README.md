# Sheet 1 animation sets — sliced 2026-10-23

140 frames: 5 classes (scout, assault, tank, sniper, support) x 4 directions
(front, side, back, threequarter) x 7 states (idle, walk1, walk2, attack,
dash, hurt, destroyed). 160x160 transparent PNGs, flood-fill keyed from
`assets/source-sheets/sheet1-mech-sprite-template.png`.
Naming: `<class>_<dir>_<state>.png`; `manifest.json` maps the full grid.

Method notes: grid detected from the sheet itself (row-split minima +
component assignment), NOT hand coordinates. First pass ate dark armor
(brightness threshold) — caught on contact-sheet QC, re-run with a
distance-from-background mask. Two frames hand-repaired after QC:
support_side_attack (auto pass caught a text block), sniper_front_idle
(class-label glyph bled into the cell).

Usage notes:
- Frames are individually trimmed + centered, so apparent scale varies
  slightly frame to frame. Anchor by bottom-center for walk cycles.
- Dash frames read smaller/distant in the SOURCE art (esp. tank) — that is
  the sheet, not a slicing error.
- These are front/side-view sprites: hangar portraits, billboards, or a 2D
  mode. The top-down chassis in ../ remain the in-game top-down sprites.
