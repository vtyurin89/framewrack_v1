#!/usr/bin/env python3
"""Procedural placeholder enemy sprites (Pillow only, no API key).

Draws 512x512 RGBA silhouettes for the Chimera enemies so they read as distinct
subjects until real DALL-E art is generated via tools/generate_enemy_sprites.py.

Usage:
  py tools/generate_placeholder_enemy_sprites.py
  py tools/generate_placeholder_enemy_sprites.py --only scavenger_chimera,trembling_corpse
"""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path
from typing import Iterable, Optional

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies" / "chimera"
SIZE = 512


def _jitter(points, amount: float, rng: random.Random):
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points]


def _taper(draw, x0, y0, x1, y1, w0, w1, fill):
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length, dx / length
    draw.polygon(
        [
            (x0 + nx * w0, y0 + ny * w0),
            (x1 + nx * w1, y1 + ny * w1),
            (x1 - nx * w1, y1 - ny * w1),
            (x0 - nx * w0, y0 - ny * w0),
        ],
        fill=fill,
    )


def _grime(img: Image.Image, rng: random.Random, strength: float = 0.10):
    px = img.load()
    w, h = img.size
    for _ in range(int(w * h * 0.02)):
        x, y = rng.randrange(w), rng.randrange(h)
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        k = rng.uniform(-strength, strength)
        px[x, y] = (
            max(0, min(255, int(r * (1 + k)))),
            max(0, min(255, int(g * (1 + k)))),
            max(0, min(255, int(b * (1 + k)))),
            a,
        )
    return img


def generate_scavenger_chimera(path: Path) -> None:
    rng = random.Random(614)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    body = (58, 52, 44, 255)
    shade = (34, 30, 26, 255)
    organic = (110, 125, 74, 255)
    rust = (122, 59, 42, 255)
    metal = (96, 92, 88, 255)
    bone = (207, 198, 168, 255)
    glow = (216, 224, 74, 255)

    cx = SIZE // 2

    # Hind legs.
    _taper(d, cx - 60, 330, cx - 120, 470, 30, 14, shade)
    _taper(d, cx + 55, 330, cx + 125, 470, 30, 14, shade)
    # Front forelimbs (one raised, feral).
    _taper(d, cx - 70, 300, cx - 150, 400, 26, 12, shade)
    _taper(d, cx + 70, 300, cx + 120, 440, 26, 12, shade)

    # Hunched torso.
    torso = _jitter(
        [
            (cx - 95, 300),
            (cx - 80, 225),
            (cx - 40, 180),
            (cx + 45, 178),
            (cx + 92, 230),
            (cx + 100, 300),
            (cx + 70, 350),
            (cx - 72, 352),
        ],
        6,
        rng,
    )
    d.polygon(torso, fill=body)

    # Spine ridge spikes.
    for i in range(7):
        x = cx - 60 + i * 20
        y = 205 - math.sin(i * 0.9) * 10
        d.polygon([(x - 9, y + 16), (x, y - 26 - rng.randint(0, 14)), (x + 9, y + 16)], fill=bone)

    # Metal shoulder plate + cables.
    d.polygon(_jitter([(cx + 30, 196), (cx + 96, 214), (cx + 92, 268), (cx + 30, 258)], 3, rng), fill=metal)
    d.line([(cx + 40, 205), (cx + 20, 150)], fill=rust, width=6)
    d.line([(cx + 60, 205), (cx + 80, 150)], fill=rust, width=6)

    # Organic graft patch.
    d.ellipse([cx - 92, 226, cx - 30, 292], fill=organic)
    d.line([(cx - 70, 230), (cx - 60, 288)], fill=(70, 82, 48, 255), width=4)

    # Low head + jaw.
    d.ellipse([cx - 58, 232, cx + 34, 306], fill=body)
    d.polygon(_jitter([(cx + 8, 268), (cx + 92, 286), (cx + 30, 312), (cx + 2, 300)], 3, rng), fill=shade)
    # Teeth.
    for i in range(5):
        x = cx + 20 + i * 13
        d.polygon([(x, 288), (x + 5, 306), (x + 10, 288)], fill=bone)
    # Eyes.
    d.ellipse([cx - 34, 252, cx - 16, 268], fill=glow)
    d.ellipse([cx - 4, 250, cx + 14, 266], fill=glow)
    d.ellipse([cx - 28, 256, cx - 22, 264], fill=(20, 20, 16, 255))
    d.ellipse([cx + 0, 254, cx + 6, 262], fill=(20, 20, 16, 255))

    # Tail.
    _taper(d, cx + 96, 320, cx + 190, 360, 16, 4, shade)

    img = img.filter(ImageFilter.GaussianBlur(0.6))
    _grime(img, rng, 0.12)
    img.save(path, format="PNG")


def generate_trembling_corpse(path: Path) -> None:
    rng = random.Random(616)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    mass = (107, 111, 90, 255)
    dark = (59, 61, 51, 255)
    blood = (122, 47, 47, 255)
    bone = (207, 198, 168, 255)
    glow = (184, 68, 68, 255)

    cx, cy = SIZE // 2, 360

    # Irregular twitching mass.
    base = []
    steps = 46
    for i in range(steps):
        a = (i / steps) * math.tau
        r = 150 + math.sin(a * 3.1) * 22 + rng.uniform(-16, 16)
        base.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.62))
    d.polygon(base, fill=mass)
    # Top lump.
    d.polygon(_jitter([(cx - 90, 300), (cx - 40, 236), (cx + 30, 246), (cx + 80, 306)], 10, rng), fill=mass)

    # Protruding broken limbs.
    for (x0, y0, x1, y1, w) in [
        (cx - 90, 330, cx - 190, 250, 20),
        (cx + 80, 340, cx + 200, 300, 22),
        (cx - 20, 250, cx - 60, 150, 16),
        (cx + 40, 250, cx + 130, 170, 18),
        (cx + 10, 430, cx + 90, 500, 20),
    ]:
        _taper(d, x0, y0, x1, y1, w, 6, dark)
        d.ellipse([x1 - 8, y1 - 8, x1 + 8, y1 + 8], fill=bone)

    # Gaping wounds with glow.
    for _ in range(6):
        wx, wy = cx + rng.randint(-110, 110), cy + rng.randint(-70, 70)
        rr = rng.randint(10, 26)
        d.ellipse([wx - rr, wy - rr, wx + rr, wy + rr], fill=blood)
        d.ellipse([wx - rr * 0.5, wy - rr * 0.5, wx + rr * 0.5, wy + rr * 0.5], fill=glow)

    # Trembling echo (ghost copies of the contour).
    echo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ed = ImageDraw.Draw(echo)
    for off in (-6, 6):
        pts = [(x + off, y) for x, y in base]
        ed.polygon(pts, outline=(80, 84, 66, 90))
    img = Image.alpha_composite(img, echo)

    img = img.filter(ImageFilter.GaussianBlur(0.7))
    _grime(img, rng, 0.14)
    img.save(path, format="PNG")


GENERATORS = {
    "scavenger_chimera": (generate_scavenger_chimera, "scavenger_chimera.png"),
    "trembling_corpse": (generate_trembling_corpse, "trembling_corpse.png"),
}


def parse_only(raw: str) -> Optional[set]:
    if not raw.strip():
        return None
    return {p.strip() for p in raw.split(",") if p.strip()}


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Generate procedural Chimera placeholder sprites.")
    parser.add_argument("--only", type=str, default="", help="Comma-separated ids.")
    args = parser.parse_args(list(argv) if argv is not None else None)

    only = parse_only(args.only)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for key, (fn, filename) in GENERATORS.items():
        if only is not None and key not in only:
            continue
        out = OUT_DIR / filename
        fn(out)
        print(f"saved {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
