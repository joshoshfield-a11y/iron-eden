#!/usr/bin/env python3
"""Pass 34: slice true top-down unit frames from the user's Game Assets
Template (assets/source-sheets/2026-10-26/game-assets-template.jpg).

Chassis column (player): SCOUT / ASSAULT / SUPPORT, plus STRIDER for the
lancer enemy. Enemy factions column: Armored Tank (heavy), Artillery
(shield_heavy), Bloom Swarm green (scout enemy), Swarm entity red spiky
(burrower), Coordinated drone left drone (sapper), Directorate Siege
Platform boss (siege enemy).

Method (same family as assets/qc/p13_slice.py): tight-crop each mech by
distance from the cell's modal panel background, EXCLUDING near-white
pixels so label text can never enter a sprite; flood-fill key the panel
background to transparency from the border (so dark cockpit interiors
that happen to sit near the bg colour are NOT punched through); chassis
frames are rotated 90 deg clockwise so the template's west-facing nose
points image-up, which is the game forward (-Z) for a flat ground quad.
Pixel art is upscaled NEAREST (chassis 2x, small faction cells 4x, boss 2x)
so the template's pixel look survives on a phone screen.

Output: prototype/sprites/p34/p34_*.png (plus a QC contact sheet in /tmp).
"""
from collections import Counter, deque
from PIL import Image
import os

SRC = os.path.expanduser(
    "~/workspace/iron-eden/assets/source-sheets/2026-10-26/game-assets-template.jpg")
OUT = os.path.expanduser("~/workspace/iron-eden/prototype/sprites/p34")
os.makedirs(OUT, exist_ok=True)
im = Image.open(SRC).convert("RGB")

# (name, region, rotate_cw, upscale)
JOBS = [
    # Regions sit INSIDE the art area: header rows (scout header to y~105,
    # assault label from y~320, support label from y~640) and the enemy
    # cells' top border bands / bottom labels are all outside these boxes.
    ("p34_scout", (8, 108, 208, 200), True, 2),
    ("p34_assault", (8, 225, 208, 318), True, 2),
    ("p34_support", (8, 565, 208, 635), True, 2),
    ("p34_enemy_strider", (8, 455, 208, 528), True, 2),
    ("p34_enemy_tank", (1145, 430, 1205, 474), False, 4),
    ("p34_enemy_artillery", (1210, 430, 1270, 474), False, 4),
    ("p34_enemy_swarm_green", (1340, 430, 1400, 474), False, 4),
    ("p34_enemy_spiky", (1145, 494, 1205, 528), False, 4),
    ("p34_enemy_drone", (1275, 494, 1335, 528), False, 4),
    ("p34_enemy_siege", (1145, 654, 1275, 740), False, 2),
]


def dist(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def tight_crop(region):
    crop = im.crop(region)
    bg = Counter(crop.getdata()).most_common(1)[0][0]
    pts = []
    for y in range(2, crop.height - 2):
        for x in range(2, crop.width - 2):
            p = crop.getpixel((x, y))
            if dist(p, bg) > 60 and not all(c > 180 for c in p):
                pts.append((x, y))
    assert pts, f"no mech pixels in {region}"
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    box = (max(0, min(xs) - 3), max(0, min(ys) - 3),
           min(crop.width, max(xs) + 4), min(crop.height, max(ys) + 4))
    return crop.crop(box), bg


def key_bg(img, bg):
    """Flood-fill transparency from the border through bg-coloured pixels."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = set()
    q = deque()
    for x in range(w):
        q += [(x, 0), (x, h - 1)]
    for y in range(h):
        q += [(0, y), (w - 1, y)]
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        if dist(px[x, y][:3], bg) < 60:
            px[x, y] = (px[x, y][0], px[x, y][1], px[x, y][2], 0)
            q += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return img


results = {}
for name, region, cw, scale in JOBS:
    crop, bg = tight_crop(region)
    # NOTE: the Coordinated-drone cell holds a diagonal PAIR; a rectangular
    # split would slice a drone in half, so the sapper keeps the whole pair
    # as one unit (two coordinated drones flying together).
    keyed = key_bg(crop, bg)
    if cw:
        keyed = keyed.rotate(-90, expand=True)  # west nose -> image-up
    keyed = keyed.resize((keyed.width * scale, keyed.height * scale),
                         Image.NEAREST)
    keyed.save(os.path.join(OUT, name + ".png"))
    results[name] = keyed.size
    # QC: opaque-pixel fraction must be sane (mech present, bg gone)
    alpha = keyed.getchannel("A")
    opaque = sum(1 for a in alpha.getdata() if a > 0)
    print(f"{name}: {keyed.size} opaque={opaque / (keyed.width * keyed.height):.2f} bg={bg}")
    assert 0.15 < opaque / (keyed.width * keyed.height) < 0.95, name

# QC contact sheet on a checkerboard so transparency errors show.
sheet = Image.new("RGBA", (6 * 170, 2 * 150), (0, 0, 0, 255))
for i, (name, _r, _c, _s) in enumerate(JOBS):
    tile = Image.open(os.path.join(OUT, name + ".png"))
    tile.thumbnail((160, 140), Image.NEAREST)
    bg_tile = Image.new("RGBA", (160, 140), (90, 90, 90, 255))
    for yy in range(0, 140, 20):
        for xx in range(0, 160, 20):
            if (xx // 20 + yy // 20) % 2:
                for dy in range(20):
                    for dx in range(20):
                        bg_tile.putpixel((xx + dx, yy + dy), (160, 160, 160, 255))
    bg_tile.alpha_composite(tile, ((160 - tile.width) // 2, (140 - tile.height) // 2))
    sheet.alpha_composite(bg_tile, ((i % 6) * 170 + 5, (i // 6) * 150 + 5))
sheet.convert("RGB").save("/tmp/p34work/contact_final.png")
print("contact -> /tmp/p34work/contact_final.png")
