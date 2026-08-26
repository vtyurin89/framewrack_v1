"""Remove solid/near-black backgrounds from sprites via edge flood-fill."""
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

PATHS = [
	Path(r"c:\stuff\godot staff\crawler\assets\sprites\items\sticky_grenade.png"),
	Path(r"c:\stuff\godot staff\crawler\assets\sprites\enemies\synthet\arbiter_guard.png"),
	Path(r"c:\stuff\godot staff\crawler\assets\sprites\enemies\synthet\grenadier_drone.png"),
	Path(r"c:\stuff\godot staff\crawler\assets\sprites\enemies\synthet\warden.png"),
]

# Pure/near-black key. Subjects use dark brown/gray metal, not pure black.
HARD = 10   # max(R,G,B) <= HARD → background seed / flood
SOFT = 28   # fringe near background → fade alpha


def is_hard_bg(r: int, g: int, b: int) -> bool:
	return max(r, g, b) <= HARD


def is_soft_bg(r: int, g: int, b: int) -> bool:
	return max(r, g, b) <= SOFT


def remove_bg(path: Path) -> None:
	im = Image.open(path).convert("RGBA")
	w, h = im.size
	px = im.load()
	marked = [[False] * h for _ in range(w)]
	q: deque[tuple[int, int]] = deque()

	def seed(x: int, y: int) -> None:
		r, g, b, a = px[x, y]
		if a == 0 or marked[x][y]:
			return
		if is_soft_bg(r, g, b):
			marked[x][y] = True
			q.append((x, y))

	for x in range(w):
		seed(x, 0)
		seed(x, h - 1)
	for y in range(h):
		seed(0, y)
		seed(w - 1, y)

	while q:
		x, y = q.popleft()
		for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
			if nx < 0 or ny < 0 or nx >= w or ny >= h or marked[nx][ny]:
				continue
			r, g, b, a = px[nx, ny]
			if a == 0 or is_hard_bg(r, g, b):
				marked[nx][ny] = True
				q.append((nx, ny))
			elif is_soft_bg(r, g, b):
				# Soft fringe only one step from hard/already-marked bg.
				marked[nx][ny] = True
				# Do not continue flooding through soft-only pixels aggressively.
				# Re-queue only if neighbor hard would — already marked as fringe.

	cleared = 0
	faded = 0
	for x in range(w):
		for y in range(h):
			if not marked[x][y]:
				continue
			r, g, b, a = px[x, y]
			m = max(r, g, b)
			if m <= HARD:
				px[x, y] = (0, 0, 0, 0)
				cleared += 1
			elif m <= SOFT:
				t = (m - HARD) / float(SOFT - HARD)
				px[x, y] = (r, g, b, int(a * t))
				faded += 1

	im.save(path)
	print(f"{path.name}: cleared={cleared} faded={faded}")


def main() -> None:
	for path in PATHS:
		if not path.exists():
			print(f"missing: {path}")
			continue
		remove_bg(path)
		im = Image.open(path).convert("RGBA")
		c0 = im.getpixel((0, 0))
		print(f"  corner={c0} mode={im.mode}")


if __name__ == "__main__":
	main()
