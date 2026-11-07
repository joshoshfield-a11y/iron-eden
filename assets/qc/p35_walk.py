#!/usr/bin/env python3
"""Pass 35: real frame-based walk cycles from the Pass 34 template frames.

Method (stated plainly, no new AI art claimed): each p34 template frame is
the unit's silhouette, and a top-down walk cycle reads as the lateral
limb/tread zones striding alternately along the body axis while the torso
stays put. So each walk set is 4 frames derived from its p34 base:
  walk0 = base exactly (idle/contact frame)
  walk1 = left zone shifted forward (image-up) by d, right zone back by d
  walk2 = both zones shifted forward by d//2 (passing pose)
  walk3 = left zone back by d, right zone forward by d
Zones are the outer 38% strips on each side (legs/treads/spikes live there;
the centre 24% — torso, turret, cockpit — is copied pixel-for-pixel, so
the silhouette and the template look never change). d scales with height
(round(H*0.025), clamped 3..10). Vacated pixels go transparent, which reads
as the joint gap of a striding limb at phone scale.

This is NOT bob/scale animation: the runtime swaps textures, the holder
never moves and never scales. QC asserts: centre zone identical in every
frame, side zones actually differ (limb motion, not a duplicate), opaque
fraction stays within 6% of base (no limb lost off-canvas).

Output: prototype/sprites/p35/p35_<stem>_walk{0..3}.png + contact sheet.
"""
import os
from PIL import Image

SRC = os.path.expanduser("~/workspace/iron-eden/prototype/sprites/p34")
OUT = os.path.expanduser("~/workspace/iron-eden/prototype/sprites/p35")
QC = os.path.expanduser("~/workspace/iron-eden/assets/qc/p35-contact.png")
os.makedirs(OUT, exist_ok=True)


def make_frames(base):
    w, h = base.size
    d = max(4, min(14, round(h * 0.04)))
    lx, rx = int(w * 0.38), int(w * 0.62)
    shifts = [(0, 0), (-d, d), (-(d // 2), -(d // 2)), (d, -d)]  # (left_dy, right_dy)
    frames = []
    for ldy, rdy in shifts:
        fr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        px, fp = base.load(), fr.load()
        for y in range(h):
            for x in range(w):
                # Copy every pixel, including alpha-0 ones: p34 PNGs carry
                # RGB in fully-transparent pixels (flood-fill keying), and
                # dropping them would make walk0 differ from base in RGB
                # even though it is visually identical.
                p = px[x, y]
                if x < lx:
                    ny = y + ldy
                elif x > rx:
                    ny = y + rdy
                else:
                    ny = y
                if 0 <= ny < h:
                    fp[x, ny] = p
        frames.append(fr)
    return frames, d, lx, rx


def diff_stats(a, b, lx, rx):
    w, h = a.size
    pa, pb = a.load(), b.load()
    side = centre = 0
    for y in range(h):
        for x in range(w):
            # Visible difference only: alpha change, or an RGB change on a
            # pixel that is opaque in both frames (alpha-0 RGB is invisible).
            va = pa[x, y]
            vb = pb[x, y]
            if va[3] != vb[3] or (va[3] > 0 and vb[3] > 0 and va[:3] != vb[:3]):
                if x < lx or x > rx:
                    side += 1
                else:
                    centre += 1
    return side, centre


def opaque_frac(im):
    a = im.getchannel("A")
    return sum(1 for v in a.getdata() if v > 0) / (im.width * im.height)


results = {}
for fn in sorted(os.listdir(SRC)):
    if not fn.endswith(".png"):
        continue
    stem = fn[:-4].replace("p34_", "p35_", 1)  # p35_scout, p35_enemy_tank, ...
    base = Image.open(os.path.join(SRC, fn)).convert("RGBA")
    frames, d, lx, rx = make_frames(base)
    base_frac = opaque_frac(base)
    for i, fr in enumerate(frames):
        fr.save(os.path.join(OUT, f"{stem}_walk{i}.png"))
        side, centre = diff_stats(base, fr, lx, rx)
        frac = opaque_frac(fr)
        print(f"{stem}_walk{i}: {fr.size} d={d} side_diff={side} "
              f"centre_diff={centre} opaque={frac:.3f} (base {base_frac:.3f})")
        assert centre == 0, f"centre moved in {stem}_walk{i}"
        if i in (1, 3):
            assert side > 200, f"no limb motion in {stem}_walk{i} (side_diff {side})"
        assert abs(frac - base_frac) < 0.06, f"opaque drift in {stem}_walk{i}"
    results[stem] = frames

# QC contact sheet: scout, assault, tank — 4 frames each on a checkerboard.
show = ["p35_scout", "p35_assault", "p35_enemy_tank"]
sheet = Image.new("RGBA", (4 * 170, 3 * 170), (0, 0, 0, 255))
for r, stem in enumerate(show):
    for c in range(4):
        tile = results[stem][c].copy()
        tile.thumbnail((160, 160), Image.NEAREST)
        cell = Image.new("RGBA", (170, 170), (60, 60, 60, 255))
        for yy in range(0, 170, 20):
            for xx in range(0, 170, 20):
                if (xx // 20 + yy // 20) % 2 == 0:
                    cell.paste((110, 110, 110, 255), (xx, yy, xx + 20, yy + 20))
        cell.alpha_composite(tile, ((170 - tile.width) // 2, (170 - tile.height) // 2))
        sheet.paste(cell, (c * 170, r * 170))
sheet.save(QC)
print(f"contact sheet: {QC}  sets: {len(results)} x 4 frames")
