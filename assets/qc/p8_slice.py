#!/usr/bin/env python3
"""Pass 8 (Overhaul B): slice tiles-sheet.png into individual keyed tiles,
build ground atlases (region1 + rust region2) and a labelled contact sheet.

tiles-sheet.png is 1920x1280, 3 rows x 5 cols (cells 384 x 426/427).
Cell order follows the generation prompt:
 row0: grass, dirt_path, cliff, water, shoreline
 row1: metal_platform, gate, pine_trees, crystal, wreck
 row2: solar, turret, crate, mossy_stone, rust_wall
Keying: near-black (<24 on all channels) -> transparent.
Atlas: 1024x1024, 4x4 grid of 256px diamond tiles on a dark base, so the
ground plane shows readable panel seams. Rust atlas multiplies tile RGB
by (1.15, 0.62, 0.42) and uses a rust base.
"""
import json, random
from PIL import Image, ImageDraw

SRC = "/home/hatch/workspace/iron-eden/assets/generated-sprites/tiles-sheet.png"
OUT = "/home/hatch/workspace/iron-eden/prototype/sprites/p8"
QC = "/home/hatch/workspace/iron-eden/assets/qc"
import os
os.makedirs(OUT, exist_ok=True)

NAMES = [
    "grass", "dirt_path", "cliff", "water", "shoreline",
    "metal_platform", "gate", "pine_trees", "crystal", "wreck",
    "solar", "turret", "crate", "mossy_stone", "rust_wall",
]
sheet = Image.open(SRC).convert("RGB")
W, H = sheet.size
CW, CH = W // 5, H // 3
stats = {}
tiles = {}
for i, name in enumerate(NAMES):
    r, c = divmod(i, 5)
    box = (c * CW, r * CH, (c + 1) * CW if c < 4 else W,
           (r + 1) * CH if r < 2 else H)
    cell = sheet.crop(box)
    # key near-black to transparent
    px = cell.convert("RGBA")
    data = px.load()
    opaque = 0
    for y in range(px.height):
        for x in range(px.width):
            r0, g0, b0, _ = data[x, y]
            if r0 < 24 and g0 < 24 and b0 < 24:
                data[x, y] = (0, 0, 0, 0)
            else:
                opaque += 1
    px.save(f"{OUT}/tile_{name}.png")
    tiles[name] = px
    stats[name] = {"cell": box, "opaque_px": opaque,
                   "opaque_frac": round(opaque / (px.width * px.height), 3)}

# contact sheet: 5 cols, labels under each tile
cs = Image.new("RGB", (5 * 384, 3 * (427 + 28)), (20, 20, 24))
d = ImageDraw.Draw(cs)
for i, name in enumerate(NAMES):
    r, c = divmod(i, 5)
    t = tiles[name].resize((384, 427))
    cs.paste(t, (c * 384, r * (427 + 28)), t)
    d.text((c * 384 + 8, r * (427 + 28) + 427 + 4), name, fill=(255, 255, 255))
cs.save(f"{QC}/p8-contact.png")

# ground atlas: 4x4 pattern, dark base, diamond tiles pasted centred in cells
rng = random.Random(20261025)
pattern = ["grass", "dirt_path", "mossy_stone", "grass",
           "dirt_path", "grass", "metal_platform", "dirt_path",
           "mossy_stone", "grass", "dirt_path", "grass",
           "grass", "metal_platform", "grass", "mossy_stone"]
def build_atlas(rust: bool) -> Image.Image:
    base = (52, 26, 14) if rust else (16, 17, 20)
    at = Image.new("RGB", (1024, 1024), base)
    for i, name in enumerate(pattern):
        t = tiles[name].resize((256, 256))
        if rust:
            rgb = t.convert("RGB")
            rp = rgb.load()
            for y in range(256):
                for x in range(256):
                    r0, g0, b0 = rp[x, y]
                    rp[x, y] = (min(255, int(r0 * 1.15)), int(g0 * 0.62), int(b0 * 0.42))
            t = Image.merge("RGBA", (*rgb.split(), t.split()[3]))
        r, c = divmod(i, 4)
        at.paste(t, (c * 256, r * 256), t)
    return at
build_atlas(False).save(f"{OUT}/ground_atlas.png")
build_atlas(True).save(f"{OUT}/ground_atlas_rust.png")
# plaza atlas: metal platform tiles on a lighter base
pl = Image.new("RGB", (768, 768), (30, 32, 38))
for i in range(9):
    t = tiles["metal_platform"].resize((256, 256))
    r, c = divmod(i, 3)
    pl.paste(t, (c * 256, r * 256), t)
pl.save(f"{OUT}/plaza_atlas.png")
json.dump(stats, open(f"{QC}/p8-slice.json", "w"), indent=1)
print(json.dumps(stats, indent=1))
print("atlas pattern:", pattern)
