#!/usr/bin/env python3
"""Pass 9 (Overhaul C): slice weapons-sheet.png into individual keyed
weapon/ability icons for the HUD, plus a labelled contact sheet.

weapons-sheet.png is 1920x1280, 3 rows x 4 cols (cells 480 x 426/427).
Cell order follows the generation prompt:
 row0: plasma_rifle, gatling, missile_pod, homing_missile
 row1: railgun, energy_sword, rocket_launcher, flamethrower
 row2: laser_emitter, shield_generator, combat_drone, grenade_launcher
Keying: near-black (<24 on all channels) -> transparent (same as Pass 8).
"""
import json, os
from PIL import Image, ImageDraw

SRC = "/home/hatch/workspace/iron-eden/assets/generated-sprites/weapons-sheet.png"
OUT = "/home/hatch/workspace/iron-eden/prototype/sprites/p9"
QC = "/home/hatch/workspace/iron-eden/assets/qc"
os.makedirs(OUT, exist_ok=True)

NAMES = [
    "plasma_rifle", "gatling", "missile_pod", "homing_missile",
    "railgun", "energy_sword", "rocket_launcher", "flamethrower",
    "laser_emitter", "shield_generator", "combat_drone", "grenade_launcher",
]
sheet = Image.open(SRC).convert("RGB")
W, H = sheet.size
CW, CH = W // 4, H // 3
stats = {}
icons = {}
for i, name in enumerate(NAMES):
    r, c = divmod(i, 4)
    box = (c * CW, r * CH, (c + 1) * CW if c < 3 else W,
           (r + 1) * CH if r < 2 else H)
    cell = sheet.crop(box)
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
    px.save(f"{OUT}/icon_{name}.png")
    icons[name] = px
    stats[name] = {"cell": box, "opaque_px": opaque,
                   "opaque_frac": round(opaque / (px.width * px.height), 3)}

cs = Image.new("RGB", (4 * 480, 3 * (427 + 28)), (20, 20, 24))
d = ImageDraw.Draw(cs)
for i, name in enumerate(NAMES):
    r, c = divmod(i, 4)
    t = icons[name].resize((480, 427))
    cs.paste(t, (c * 480, r * (427 + 28)), t)
    d.text((c * 480 + 8, r * (427 + 28) + 427 + 4), name, fill=(255, 255, 255))
cs.save(f"{QC}/p9-contact.png")
json.dump(stats, open(f"{QC}/p9-slice.json", "w"), indent=1)
print(json.dumps(stats, indent=1))
