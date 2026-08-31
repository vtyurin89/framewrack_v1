from PIL import Image
from collections import deque
import os

ITEMS_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "items")
TARGET_SIZE = 128
FILES = ["palladium_core.png", "aberrant_tentacle.png", "cryo_core.png"]


def is_background_pixel(r: int, g: int, b: int, threshold: int = 28) -> bool:
	return r <= threshold and g <= threshold and b <= threshold


def remove_background(im: Image.Image, threshold: int = 28) -> Image.Image:
	im = im.convert("RGBA")
	w, h = im.size
	pixels = im.load()
	visited = [[False] * w for _ in range(h)]
	queue: deque[tuple[int, int]] = deque()

	def try_add(x: int, y: int) -> None:
		if 0 <= x < w and 0 <= y < h and not visited[y][x]:
			r, g, b, _a = pixels[x, y]
			if is_background_pixel(r, g, b, threshold):
				visited[y][x] = True
				queue.append((x, y))

	for x in range(w):
		try_add(x, 0)
		try_add(x, h - 1)
	for y in range(h):
		try_add(0, y)
		try_add(w - 1, y)

	while queue:
		x, y = queue.popleft()
		for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
			if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
				r, g, b, _a = pixels[nx, ny]
				if is_background_pixel(r, g, b, threshold):
					visited[ny][nx] = True
					queue.append((nx, ny))

	for y in range(h):
		for x in range(w):
			if visited[y][x]:
				pixels[x, y] = (0, 0, 0, 0)

	return im


def fit_to_canvas(im: Image.Image, size: int = TARGET_SIZE) -> Image.Image:
	bbox = im.getbbox()
	if not bbox:
		return Image.new("RGBA", (size, size), (0, 0, 0, 0))

	cropped = im.crop(bbox)
	cw, ch = cropped.size
	scale = min(size / cw, size / ch)
	nw = max(1, int(round(cw * scale)))
	nh = max(1, int(round(ch * scale)))
	resized = cropped.resize((nw, nh), Image.Resampling.NEAREST)

	canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	ox = (size - nw) // 2
	oy = (size - nh) // 2
	canvas.paste(resized, (ox, oy), resized)
	return canvas


def main() -> None:
	for filename in FILES:
		path = os.path.normpath(os.path.join(ITEMS_DIR, filename))
		im = Image.open(path)
		print(f"Processing {filename}: {im.size} {im.mode}")
		processed = remove_background(im)
		final = fit_to_canvas(processed)
		final.save(path, "PNG")
		alpha = final.split()[3]
		print(f"  -> {final.size} RGBA, alpha={alpha.getextrema()}, bbox={final.getbbox()}")


if __name__ == "__main__":
	main()
