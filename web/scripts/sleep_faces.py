import colorsys
import re
import shutil
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
RESOURCE = SOURCE.parent
SCREEN = (RESOURCE / 'shared/screen.lua').read_text(encoding='utf-8')
KINDS = (RESOURCE / 'config/kinds.lua').read_text(encoding='utf-8')
DIM = int(re.search(r'SLEEP_DIM = (\d+)', SCREEN).group(1))
SUFFIX = re.search(r"SLEEP_SUFFIX = '([^']+)'", SCREEN).group(1)
NEUTRAL_SUFFIX = re.search(r"NEUTRAL_SUFFIX = '([^']+)'", SCREEN).group(1)
NEUTRAL_SLEEP_SUFFIX = re.search(r"NEUTRAL_SLEEP_SUFFIX = '([^']+)'", SCREEN).group(1)
PICTURES = sorted(set(re.findall(r"picture = 'web/build/(idle/[\w/-]+\.\w+)'", KINDS)))
NEUTRAL = sorted(set(re.findall(r"picture = 'web/build/(idle/[\w/-]+\.\w+)', neutral = true", KINDS)))
BASE_HUE = 75
GREY_LIGHT = 0.62


def smooth(low, high, value):
    t = min(1.0, max(0.0, (value - low) / (high - low)))

    return t * t * (3 - 2 * t)


def dimmed(image):
    return image.convert('RGB').point(lambda value: int(value * DIM / 100 + 0.5)).convert('RGBA')


def neutral(image):
    image = image.convert('RGBA')
    data = bytearray(image.tobytes())

    for at in range(0, len(data), 4):
        r, g, b, a = data[at], data[at + 1], data[at + 2], data[at + 3]

        if not a or b >= r or b >= g:
            continue

        hue, light, sat = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        weight = (1 - smooth(13, 25, abs(hue * 360 - BASE_HUE))) * smooth(0.12, 0.3, sat)

        if weight <= 0:
            continue

        grey = min(1.0, max(0.0, light + (GREY_LIGHT - 0.5) * weight)) * 255
        data[at] = round(r + (grey - r) * weight)
        data[at + 1] = round(g + (grey - g) * weight)
        data[at + 2] = round(b + (grey - b) * weight)

    return Image.frombytes('RGBA', image.size, bytes(data))


def write(image, target):
    if image.mode == 'RGBA' and image.getextrema()[3] == (255, 255):
        image = image.convert('RGB')

    image.save(target, 'PNG', optimize=True)
    built = SOURCE / 'build' / target.relative_to(SOURCE / 'public')

    if built.parent.is_dir():
        shutil.copyfile(target, built)

    print(f'{target.relative_to(RESOURCE).as_posix()}')


def main():
    for rel in PICTURES:
        source = SOURCE / 'public' / rel
        picture = Image.open(source)
        write(dimmed(picture), source.with_name(source.stem + SUFFIX))

        if rel in NEUTRAL:
            grey = neutral(picture)
            write(grey, source.with_name(source.stem + NEUTRAL_SUFFIX))
            write(dimmed(grey), source.with_name(source.stem + NEUTRAL_SLEEP_SUFFIX))


if __name__ == '__main__':
    main()
