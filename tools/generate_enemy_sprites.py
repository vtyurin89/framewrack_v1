#!/usr/bin/env python3
"""Generate enemy card sprites via OpenAI DALL-E 3.

Reads enemy rows from data/enemies.csv, builds Fear & Hunger-inspired prompts,
calls dall-e-3, strips white/solid backgrounds, and writes 512x512 PNGs to
assets/sprites/enemies/{enemy_id}.png.

Usage:
  set OPENAI_API_KEY=sk-...
  pip install -r tools/requirements-sprites.txt
  python tools/generate_enemy_sprites.py
  python tools/generate_enemy_sprites.py --only desperate_rebel,scrap_drone
  python tools/generate_enemy_sprites.py --dry-run
"""

from __future__ import annotations

import argparse
import base64
import csv
import io
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

try:
	from openai import OpenAI
except ImportError:  # pragma: no cover
	OpenAI = None  # type: ignore

try:
	from PIL import Image
except ImportError as exc:  # pragma: no cover
	raise SystemExit("Pillow is required. pip install -r tools/requirements-sprites.txt") from exc

try:
	from rembg import remove as rembg_remove
except ImportError:  # pragma: no cover
	rembg_remove = None


ROOT = Path(__file__).resolve().parents[1]
ENEMIES_CSV = ROOT / "data" / "enemies.csv"
TRANSLATIONS_CSV = ROOT / "translations" / "translations.csv"
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"
OUTPUT_SIZE = (512, 512)

STYLE_PREFIX = (
	"Fear & Hunger aesthetic, dark fantasy, post-apocalyptic grimdark, "
	"high-contrast muted colors, grotesque cybernetics and scrap machinery, "
	"filthy industrial horror, lonely figure, game character portrait, "
	"isolated subject on a pure solid white background, no ground, no scenery, "
	"no text, no UI, no watermark"
)


def _load_translations(path: Path) -> Dict[str, str]:
	"""Map translation keys -> English message (column 1)."""
	out: Dict[str, str] = {}
	if not path.is_file():
		return out
	with path.open("r", encoding="utf-8-sig", newline="") as fh:
		reader = csv.reader(fh)
		header = next(reader, None)
		if not header:
			return out
		for row in reader:
			if not row or not str(row[0]).strip():
				continue
			key = str(row[0]).strip()
			en = str(row[1]).strip() if len(row) > 1 else ""
			if key and en:
				out[key] = en
	return out


def _resolve_text(raw: str, translations: Dict[str, str]) -> str:
	token = (raw or "").strip()
	if not token:
		return ""
	if token in translations:
		return translations[token]
	return token.replace("_", " ")


def load_enemies(path: Path, translations: Dict[str, str]) -> List[dict]:
	rows: List[dict] = []
	with path.open("r", encoding="utf-8-sig", newline="") as fh:
		reader = csv.DictReader(fh)
		for row in reader:
			enemy_id = (row.get("id") or "").strip()
			if not enemy_id:
				continue
			rows.append(
				{
					"id": enemy_id,
					"name": _resolve_text(row.get("name", ""), translations),
					"description": _resolve_text(row.get("description", ""), translations),
					"faction": (row.get("faction") or "").strip().lower(),
					"combat_tier": (row.get("combat_tier") or "").strip().lower(),
					"role": (row.get("role") or "").strip().lower(),
					"sprite_path": (row.get("sprite_path") or "").strip(),
					"_raw": row,
				}
			)
	return rows


def build_prompt(enemy: dict) -> str:
	faction = enemy.get("faction") or "unknown"
	tier = enemy.get("combat_tier") or "normal"
	role = enemy.get("role") or "fighter"
	name = enemy.get("name") or enemy["id"]
	desc = enemy.get("description") or name
	subject = (
		f"Full-body portrait of '{name}' ({enemy['id']}), a {tier} {faction} {role} enemy. "
		f"Character concept: {desc}."
	)
	return f"{STYLE_PREFIX}. {subject}"


def generate_dalle_image(client: "OpenAI", prompt: str, size: str = "1024x1024") -> Image.Image:
	## DALL-E 3: request white-background character art, then strip locally.
	result = client.images.generate(
		model="dall-e-3",
		prompt=prompt,
		size=size,
		quality="standard",
		n=1,
	)
	payload = result.data[0].b64_json
	if not payload:
		raise RuntimeError("DALL-E returned empty image payload")
	raw = base64.b64decode(payload)
	return Image.open(io.BytesIO(raw)).convert("RGBA")


def remove_background(img: Image.Image) -> Image.Image:
	"""Prefer rembg; fall back to near-white chroma key via Pillow."""
	rgba = img.convert("RGBA")
	if rembg_remove is not None:
		buf = io.BytesIO()
		rgba.save(buf, format="PNG")
		cut = rembg_remove(buf.getvalue())
		return Image.open(io.BytesIO(cut)).convert("RGBA")

	## Pillow near-white key (thresholded).
	pixels = rgba.load()
	w, h = rgba.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = pixels[x, y]
			if r >= 245 and g >= 245 and b >= 245:
				pixels[x, y] = (r, g, b, 0)
	return rgba


def fit_square(img: Image.Image, size: Tuple[int, int] = OUTPUT_SIZE) -> Image.Image:
	"""Contain-fit onto a transparent square canvas."""
	src = img.convert("RGBA")
	src.thumbnail(size, Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", size, (0, 0, 0, 0))
	ox = (size[0] - src.size[0]) // 2
	oy = (size[1] - src.size[1]) // 2
	canvas.paste(src, (ox, oy), src)
	return canvas


def update_enemies_csv_sprite_paths(path: Path, updates: Dict[str, str]) -> None:
	if not updates:
		return
	with path.open("r", encoding="utf-8-sig", newline="") as fh:
		reader = csv.DictReader(fh)
		fieldnames = list(reader.fieldnames or [])
		rows = list(reader)
	if "sprite_path" not in fieldnames:
		fieldnames.append("sprite_path")
	for row in rows:
		eid = (row.get("id") or "").strip()
		if eid in updates:
			row["sprite_path"] = updates[eid]
	with path.open("w", encoding="utf-8", newline="") as fh:
		writer = csv.DictWriter(fh, fieldnames=fieldnames, lineterminator="\n")
		writer.writeheader()
		writer.writerows(rows)


def parse_only(raw: str) -> Optional[set]:
	if not raw.strip():
		return None
	return {part.strip() for part in raw.split(",") if part.strip()}


def main(argv: Optional[Iterable[str]] = None) -> int:
	parser = argparse.ArgumentParser(description="Generate Framewrack enemy card sprites (DALL-E 3).")
	parser.add_argument("--enemies-csv", type=Path, default=ENEMIES_CSV)
	parser.add_argument("--translations-csv", type=Path, default=TRANSLATIONS_CSV)
	parser.add_argument("--out-dir", type=Path, default=OUT_DIR)
	parser.add_argument("--only", type=str, default="", help="Comma-separated enemy ids to generate.")
	parser.add_argument("--skip-existing", action="store_true", help="Skip ids that already have a PNG.")
	parser.add_argument("--dry-run", action="store_true", help="Print prompts only; no API calls.")
	parser.add_argument("--size", type=str, default="1024x1024", choices=["1024x1024", "1792x1024", "1024x1792"])
	parser.add_argument("--no-update-csv", action="store_true", help="Do not write sprite_path back to enemies.csv.")
	args = parser.parse_args(list(argv) if argv is not None else None)

	api_key = os.environ.get("OPENAI_API_KEY", "").strip()
	if not args.dry_run and not api_key:
		print("ERROR: OPENAI_API_KEY is not set.", file=sys.stderr)
		return 1
	if not args.dry_run and OpenAI is None:
		print("ERROR: openai package missing. pip install -r tools/requirements-sprites.txt", file=sys.stderr)
		return 1

	translations = _load_translations(args.translations_csv)
	enemies = load_enemies(args.enemies_csv, translations)
	only = parse_only(args.only)
	if only is not None:
		enemies = [e for e in enemies if e["id"] in only]

	if not enemies:
		print("No enemies matched.")
		return 0

	args.out_dir.mkdir(parents=True, exist_ok=True)
	client = None if args.dry_run else OpenAI(api_key=api_key)
	csv_updates: Dict[str, str] = {}

	for enemy in enemies:
		enemy_id = enemy["id"]
		out_path = args.out_dir / f"{enemy_id}.png"
		rel_res = f"res://assets/sprites/enemies/{enemy_id}.png"
		prompt = build_prompt(enemy)
		print(f"\n=== {enemy_id} ===")
		print(prompt)

		if args.skip_existing and out_path.is_file():
			print(f"skip existing: {out_path}")
			csv_updates[enemy_id] = rel_res
			continue
		if args.dry_run:
			continue

		assert client is not None
		print("calling dall-e-3…")
		image = generate_dalle_image(client, prompt, size=args.size)
		print(f"removing background ({'rembg' if rembg_remove else 'pillow-white-key'})…")
		cutout = remove_background(image)
		final = fit_square(cutout, OUTPUT_SIZE)
		final.save(out_path, format="PNG")
		print(f"saved {out_path}")
		csv_updates[enemy_id] = rel_res

	if not args.dry_run and not args.no_update_csv:
		update_enemies_csv_sprite_paths(args.enemies_csv, csv_updates)
		print(f"\nUpdated sprite_path in {args.enemies_csv}")

	print("\nDone.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
