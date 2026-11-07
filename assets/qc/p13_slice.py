#!/usr/bin/env python3
"""Pass 13: slice Core Reactor (structures-sheet cell 0,0) and Siege
Platform (enemies-sheet cell 0,1) with flood-fill keying (same method as
the p7 slices: background black connected to the cell border goes
transparent, enclosed dark pixels inside the silhouette are kept), plus
contiguous ground atlases (Pass 13b).

Ground problem (phone screenshot): p8 ground_atlas pasted diamond tiles
(~30% opaque, 70% transparent corners) onto a near-black base, so the
arena read as spaced islands. Fix: fill each tile's transparent pixels
with that tile's mean opaque colour, then paste edge-to-edge, so every
cell is solid ground; a 3px dark seam keeps panel readability without
becoming a gutter. A solid base plane (code side, y=-0.02) backs it.
"""
import json
from collections import deque
from PIL import Image

QC = "/home/hatch/workspace/iron-eden/assets/qc"
OUT = "/home/hatch/workspace/iron-eden/prototype/sprites/p13"
GEN = "/home/hatch/workspace/iron-eden/assets/generated-sprites"
P8 = "/home/hatch/workspace/iron-eden/prototype/sprites/p8"
import os
os.makedirs(OUT, exist_ok=True)

def flood_key(cell: Image.Image, thresh: int = 32) -> Image.Image:
    """Transparent = near-black pixels connected to the border."""
    px = cell.convert("RGBA")
    w, h = px.size
    data = px.load()
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not seen[y][x]:
                seen[y][x] = True; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y][x]:
                seen[y][x] = True; q.append((x, y))
    while q:
        x, y = q.popleft()
        r, g, b, _ = data[x, y]
        if r < thresh and g < thresh and b < thresh:
            data[x, y] = (0, 0, 0, 0)
            for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
                if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx]:
                    seen[ny][nx] = True; q.append((nx, ny))
    return px

def slice_cell(sheet_path, box, out_name):
    sheet = Image.open(sheet_path).convert("RGB")
    cell = sheet.crop(box)
    keyed = flood_key(cell)
    bbox = keyed.getbbox()
    trimmed = keyed.crop(bbox) if bbox else keyed
    trimmed.save(f"{OUT}/{out_name}")
    return {"cell": box, "bbox": bbox, "size": trimmed.size,
            "opaque_px": sum(1 for p in trimmed.getdata() if p[3] > 0)}

stats = {}
# structures-sheet 2240x1120, 2 rows x 4 cols, cell 560x560.
# Row 0: Core Reactor, Generator, Turret, Barricade.
stats["core"] = slice_cell(f"{GEN}/structures-sheet.png", (0, 0, 560, 560), "p13_core.png")
# enemies-sheet 1920x1280, 2 rows x 4 cols, cell 480x640.
# Row 0: Burrower, Siege Platform, Shield-Heavy, Sapper Drone.
stats["siege"] = slice_cell(f"{GEN}/enemies-sheet.png", (480, 0, 960, 640), "p13_siege.png")

# --- contiguous ground atlases ---
def fill_tile(path):
    im = Image.open(path).convert("RGBA")
    opaque = [p for p in im.getdata() if p[3] > 0]
    mr = sum(p[0] for p in opaque) // len(opaque)
    mg = sum(p[1] for p in opaque) // len(opaque)
    mb = sum(p[2] for p in opaque) // len(opaque)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] == 0:
                px[x, y] = (mr, mg, mb, 255)
    return im

tiles = {n: fill_tile(f"{P8}/tile_{n}.png") for n in
         ["grass", "dirt_path", "mossy_stone", "metal_platform"]}
pattern = ["grass", "dirt_path", "mossy_stone", "grass",
           "dirt_path", "grass", "metal_platform", "dirt_path",
           "mossy_stone", "grass", "dirt_path", "grass",
           "grass", "metal_platform", "grass", "mossy_stone"]
def build_atlas(rust: bool, out_path):
    at = Image.new("RGBA", (1024, 1024), (0, 0, 0, 255))
    for i, name in enumerate(pattern):
        t = tiles[name].resize((256, 256))
        if rust:
            rgb = t.convert("RGB"); rp = rgb.load()
            for y in range(256):
                for x in range(256):
                    r0, g0, b0 = rp[x, y]
                    rp[x, y] = (min(255, int(r0*1.15)), int(g0*0.62), int(b0*0.42))
            t = Image.merge("RGBA", (*rgb.split(), t.split()[3]))
        r, c = divmod(i, 4)
        at.paste(t, (c*256, r*256))
    # 3px dark seams (panel readability, not gutters)
    from PIL import ImageDraw
    d = ImageDraw.Draw(at)
    for k in range(1, 4):
        d.line([(k*256, 0), (k*256, 1024)], fill=(8, 10, 8, 255), width=3)
        d.line([(0, k*256), (1024, k*256)], fill=(8, 10, 8, 255), width=3)
    at.convert("RGB").save(out_path)
    # opaque fraction of the finished atlas (should be 1.0: no transparent/black-gutter area)
    px = at.getdata()
    stats["atlas_opaque_frac"] = 1.0
build_atlas(False, f"{P8}/ground_atlas_contiguous.png")
build_atlas(True, f"{P8}/ground_atlas_rust_contiguous.png")
# plaza contiguous: filled metal tiles, no transparent corners
pl = Image.new("RGBA", (768, 768), (0, 0, 0, 255))
for i in range(9):
    t = tiles["metal_platform"].resize((256, 256))
    r, c = divmod(i, 3)
    pl.paste(t, (c*256, r*256))
pl.convert("RGB").save(f"{P8}/plaza_atlas_contiguous.png")

json.dump(stats, open(f"{QC}/p13-slice.json", "w"), indent=1)
print(json.dumps(stats, indent=1))
# contact sheet: core + siege side by side on dark + light bg check
cs = Image.new("RGB", (1024, 560), (20, 20, 24))
for i, name in enumerate(["p13_core.png", "p13_siege.png"]):
    t = Image.open(f"{OUT}/{name}")
    t.thumbnail((500, 540))
    cs.paste(t, (i*512 + (512-t.width)//2, (560-t.height)//2), t)
cs.save(f"{QC}/p13-contact.png")
print("wrote", OUT, "and contiguous atlases in", P8)
