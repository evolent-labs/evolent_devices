import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / 'preview' / 'wallpapers'
SCALE = 2


def ramp(stops, size):
    positions = np.array([stop[0] for stop in stops], dtype=np.float64)
    colours = np.array([stop[1] for stop in stops], dtype=np.float64)
    at = np.linspace(0.0, 1.0, size)

    return np.stack([np.interp(at, positions, colours[:, channel]) for channel in range(3)], axis=1)


def glow(width, height, x, y, radius, colour, power=2.0):
    ys, xs = np.mgrid[0:height, 0:width]
    distance = np.sqrt((xs - x) ** 2 + (ys - y) ** 2) / radius
    share = np.clip(1.0 - distance, 0.0, 1.0) ** power

    return share[:, :, None] * np.array(colour, dtype=np.float64)[None, None, :]


def shapes(width, height, draw):
    layer = Image.new('RGBA', (width * SCALE, height * SCALE), (0, 0, 0, 0))
    draw(ImageDraw.Draw(layer), SCALE)

    return np.asarray(layer.resize((width, height), Image.LANCZOS), dtype=np.float64)


def over(base, layer):
    alpha = layer[:, :, 3:4] / 255.0

    return base * (1.0 - alpha) + layer[:, :, :3] * alpha


def finish(pixels, rng, name):
    grain = rng.normal(0.0, 1.1, pixels.shape[:2])[:, :, None]
    image = Image.fromarray(np.clip(pixels + grain, 0, 255).astype(np.uint8), 'RGB')

    OUT.mkdir(parents=True, exist_ok=True)
    image.save(OUT / name, 'WEBP', quality=90, method=6)

    return OUT / name


def harbour():
    width, height = 1920, 1080
    rng = np.random.default_rng(11)
    horizon = int(height * 0.6)
    sky = ramp([(0.0, (9, 12, 34)), (0.45, (38, 30, 78)), (0.78, (148, 70, 96)), (0.93, (240, 138, 76)), (1.0, (255, 196, 120))], horizon)
    sea = ramp([(0.0, (120, 74, 84)), (0.12, (52, 40, 78)), (0.5, (16, 20, 48)), (1.0, (6, 8, 22))], height - horizon)
    pixels = np.concatenate([np.repeat(sky[:, None, :], width, axis=1), np.repeat(sea[:, None, :], width, axis=1)], axis=0)
    sun = (int(width * 0.66), horizon - 26)

    pixels += glow(width, height, sun[0], sun[1], 620, (120, 60, 20), 2.4)
    pixels += glow(width, height, sun[0], sun[1], 150, (255, 190, 110), 1.6)

    stars = np.zeros((height, width, 3))

    for _ in range(260):
        x, y = int(rng.integers(0, width)), int(rng.integers(0, int(horizon * 0.62)))
        stars[y, x] = rng.uniform(70, 190) * (1.0 - y / horizon)

    pixels += np.asarray(Image.fromarray(np.clip(stars, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float64) * 2.2

    xs = np.arange(width)
    ridge = horizon - 34 - 26 * np.sin(xs / 210.0 + 0.6) - 14 * np.sin(xs / 73.0 + 2.1) - 7 * np.sin(xs / 31.0)

    for x in range(width):
        top = int(ridge[x])
        pixels[top:horizon, x] = pixels[top:horizon, x] * 0.18 + np.array((24, 18, 44)) * 0.82

    ripple = rng.normal(0.0, 1.0, (height - horizon, width // 6))
    ripple = np.asarray(Image.fromarray(((ripple - ripple.min()) / (ripple.max() - ripple.min()) * 255).astype(np.uint8)).resize((width, height - horizon), Image.BICUBIC).filter(ImageFilter.GaussianBlur((7, 0.6))), dtype=np.float64) / 255.0 - 0.5
    depth = np.linspace(0.25, 1.0, height - horizon)[:, None]
    column = np.exp(-(((xs - sun[0]) / (70.0 + 260.0 * depth)) ** 2))

    pixels[horizon:] += (ripple * 26.0 * depth)[:, :, None]
    pixels[horizon:] += (column * (0.55 + ripple * 1.6) * (1.15 - depth))[:, :, None] * np.array((255, 150, 80)) * 0.62

    quay = int(height * 0.86)
    stacks = [
        (70, 3, [(226, 96, 52), (38, 124, 138), (196, 255, 1)]),
        (330, 2, [(52, 78, 150), (214, 178, 64)]),
        (590, 4, [(170, 52, 60), (38, 124, 138), (226, 96, 52), (96, 104, 120)]),
        (1180, 2, [(196, 255, 1), (52, 78, 150)]),
        (1440, 3, [(214, 178, 64), (170, 52, 60), (38, 124, 138)]),
    ]
    lamps = [(250, quay - 250), (880, quay - 250), (1090, quay - 250), (1700, quay - 250)]

    def draw(pen, s):
        pen.rectangle([0, quay * s, width * s, height * s], fill=(10, 11, 22, 255))
        pen.rectangle([0, quay * s, width * s, (quay + 5) * s], fill=(44, 40, 66, 255))

        for left, _, colours in stacks:
            for level, colour in enumerate(colours):
                top = quay - 58 * (level + 1)
                shade = tuple(int(value * 0.5) for value in colour)

                pen.rectangle([left * s, top * s, (left + 236) * s, (top + 56) * s], fill=shade + (255,))
                pen.rectangle([left * s, top * s, (left + 236) * s, (top + 5) * s], fill=tuple(int(value * 0.82) for value in colour) + (255,))

                for rib in range(1, 12):
                    x = left + rib * 19.6
                    pen.line([x * s, (top + 8) * s, x * s, (top + 54) * s], fill=tuple(int(value * 0.38) for value in colour) + (255,), width=2 * s)

        for base in (960, 1640):
            dark = (14, 14, 30, 255)

            pen.rectangle([(base - 86) * s, (quay - 330) * s, (base - 72) * s, quay * s], fill=dark)
            pen.rectangle([(base + 72) * s, (quay - 330) * s, (base + 86) * s, quay * s], fill=dark)
            pen.rectangle([(base - 250) * s, (quay - 346) * s, (base + 150) * s, (quay - 328) * s], fill=dark)
            pen.line([(base - 79) * s, (quay - 330) * s, (base + 79) * s, (quay - 150) * s], fill=dark, width=7 * s)
            pen.line([(base + 79) * s, (quay - 330) * s, (base - 79) * s, (quay - 150) * s], fill=dark, width=7 * s)
            pen.line([(base - 40) * s, (quay - 346) * s, (base - 250) * s, (quay - 430) * s], fill=dark, width=6 * s)
            pen.line([(base - 40) * s, (quay - 346) * s, (base - 40) * s, (quay - 470) * s], fill=dark, width=9 * s)
            pen.line([(base - 40) * s, (quay - 470) * s, (base + 150) * s, (quay - 346) * s], fill=dark, width=5 * s)
            pen.line([(base - 190) * s, (quay - 340) * s, (base - 190) * s, (quay - 236) * s], fill=dark, width=3 * s)
            pen.rectangle([(base - 214) * s, (quay - 236) * s, (base - 166) * s, (quay - 214) * s], fill=dark)

        for x, y in lamps:
            pen.line([x * s, y * s, x * s, quay * s], fill=(16, 16, 32, 255), width=5 * s)
            pen.rectangle([(x - 26) * s, (y - 6) * s, (x + 26) * s, y * s], fill=(16, 16, 32, 255))

    pixels = over(pixels, shapes(width, height, draw))

    for x, y in lamps:
        pixels += glow(width, height, x, y + 6, 170, (120, 96, 54), 2.6)
        pixels += glow(width, height, x, y + 4, 16, (255, 236, 190), 1.2)

    return finish(pixels, rng, 'harbour.webp')


def night_drive():
    width, height = 2400, 900
    rng = np.random.default_rng(23)
    horizon = int(height * 0.52)
    sky = ramp([(0.0, (4, 6, 18)), (0.6, (16, 20, 52)), (0.9, (52, 36, 96)), (1.0, (112, 58, 122))], horizon)
    ground = ramp([(0.0, (20, 18, 36)), (0.2, (12, 12, 22)), (1.0, (6, 6, 12))], height - horizon)
    pixels = np.concatenate([np.repeat(sky[:, None, :], width, axis=1), np.repeat(ground[:, None, :], width, axis=1)], axis=0)
    centre = width // 2

    pixels += glow(width, height, centre, horizon, 760, (70, 30, 80), 2.2)

    stars = np.zeros((height, width, 3))

    for _ in range(420):
        x, y = int(rng.integers(0, width)), int(rng.integers(0, int(horizon * 0.8)))
        stars[y, x] = rng.uniform(60, 200) * (1.0 - y / horizon)

    pixels += np.asarray(Image.fromarray(np.clip(stars, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float64) * 2.4

    towers = []
    x = 40

    while x < width - 40:
        wide = int(rng.integers(34, 92))
        tall = int(rng.integers(36, 150) * (0.55 + 0.75 * np.exp(-(((x - centre) / 620.0) ** 2))))

        towers.append((x, wide, tall))
        x += wide + int(rng.integers(2, 16))

    windows = []

    for left, wide, tall in towers:
        for row in range(horizon - tall + 8, horizon - 6, 9):
            for column in range(left + 5, left + wide - 6, 8):
                if rng.random() < 0.3:
                    windows.append((column, row, (255, 214, 140) if rng.random() < 0.72 else (140, 208, 255)))

    def near(row, lane):
        depth = (row - horizon) / (height - horizon)

        return centre + lane * (40 + 1500 * depth)

    def draw(pen, s):
        for left, wide, tall in towers:
            pen.rectangle([left * s, (horizon - tall) * s, (left + wide) * s, horizon * s], fill=(11, 12, 28, 255))

        for column, row, colour in windows:
            pen.rectangle([column * s, row * s, (column + 3) * s, (row + 4) * s], fill=colour + (220,))

        pen.polygon([(near(horizon, -1) * s, horizon * s), (near(horizon, 1) * s, horizon * s), (near(height, 1) * s, height * s), (near(height, -1) * s, height * s)], fill=(15, 15, 24, 255))

        for side in (-1, 1):
            pen.line([near(horizon, side) * s, horizon * s, near(height, side) * s, height * s], fill=(210, 210, 220, 255), width=4 * s)

        dash = 0.0

        while dash < 1.0:
            start, end = dash ** 2.2, min(1.0, dash + 0.045) ** 2.2
            top, bottom = horizon + start * (height - horizon), horizon + end * (height - horizon)
            thick = 1.5 + 11 * start

            pen.polygon([((centre - thick) * s, top * s), ((centre + thick) * s, top * s), ((centre + thick * 1.25) * s, bottom * s), ((centre - thick * 1.25) * s, bottom * s)], fill=(226, 196, 96, 255))
            dash += 0.1

    pixels = over(pixels, shapes(width, height, draw))

    trails = np.zeros((height, width, 3))
    rows = np.arange(horizon + 2, height)

    for lane, colour, strength in ((-0.62, (255, 44, 40), 1.0), (-0.34, (255, 60, 48), 0.8), (0.3, (255, 240, 214), 0.9), (0.6, (255, 246, 228), 1.0)):
        for row in rows:
            depth = (row - horizon) / (height - horizon)
            at = int(near(row, lane) + 14 * np.sin(depth * 9.0 + lane * 4.0) * depth)
            wide = max(1, int(1 + 7 * depth))

            trails[row, max(0, at - wide):min(width, at + wide)] += np.array(colour) * strength * (0.35 + 0.65 * depth)

    blurred = np.asarray(Image.fromarray(np.clip(trails, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9)), dtype=np.float64)
    pixels += trails * 0.55 + blurred * 1.5

    return finish(pixels, rng, 'night_drive.webp')


if __name__ == '__main__':
    for build in (harbour, night_drive):
        path = build()
        print(f'{path.name}: {path.stat().st_size // 1024} KB')

    sys.exit(0)
