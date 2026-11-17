export type Rgb = readonly [number, number, number];
export type Box = readonly [number, number, number, number];

export const LIME: Rgb = [196, 255, 1];

const SPAN = LIME[1] - LIME[2];
const FLOOR = 3;
const LIME_HUE = 75;
const WHOLE: readonly Box[] = [[0, 0, 1, 1]];

const DESIGNS: readonly { name: RegExp; boxes: readonly Box[] }[] = [
  { name: /(^|\/)idle\/(pc|laptop|terminal)(_evolent)?\.webp([?#]|$)/, boxes: WHOLE },
  { name: /(^|\/)wallpapers\/evolent\.webp([?#]|$)/, boxes: WHOLE },
];

export function designOf(src: string): readonly Box[] | null {
  for (const entry of DESIGNS) {
    if (entry.name.test(src)) return entry.boxes;
  }

  return null;
}

const smooth = (from: number, to: number, value: number) => {
  const t = Math.min(1, Math.max(0, (value - from) / (to - from)));

  return t * t * (3 - 2 * t);
};

function limeLike(r: number, g: number, b: number) {
  const max = Math.max(r, g, b),
    min = Math.min(r, g, b);

  if (max === min || b >= r) return 0;

  const sum = (max + min) / 255;
  const sat = (max - min) / 255 / (sum > 1 ? 2 - sum : sum);
  const hue = (max === r ? (g - b) / (max - min) : (b - r) / (max - min) + 2) * 60;

  return (1 - smooth(13, 25, Math.abs(hue - LIME_HUE))) * smooth(0.12, 0.3, sat);
}

function swap(data: Uint8ClampedArray, from: number, to: number, shift: Rgb, gated: boolean) {
  for (let i = from; i < to; i += 4) {
    const g = data[i + 1],
      b = data[i + 2];
    const amount = g - b;

    if (amount < FLOOR || !data[i + 3]) continue;

    const r = data[i];
    let share = Math.min(1, amount / SPAN);

    if (gated) {
      share *= limeLike(r, g, b);

      if (share <= 0) continue;
    }

    data[i] = Math.round(r + share * shift[0]);
    data[i + 1] = Math.round(g + share * shift[1]);
    data[i + 2] = Math.round(b + share * shift[2]);
  }
}

export function recolour(data: Uint8ClampedArray, width: number, height: number, target: Rgb, boxes: readonly Box[] | null) {
  const shift: Rgb = [target[0] - LIME[0], target[1] - LIME[1], target[2] - LIME[2]];

  if (!boxes) {
    swap(data, 0, width * height * 4, shift, true);

    return;
  }

  for (const [left, top, right, bottom] of boxes) {
    const x0 = Math.max(0, Math.floor(left * width)),
      x1 = Math.min(width, Math.ceil(right * width));
    const y0 = Math.max(0, Math.floor(top * height)),
      y1 = Math.min(height, Math.ceil(bottom * height));

    for (let y = y0; y < y1; y++) {
      swap(data, (y * width + x0) * 4, (y * width + x1) * 4, shift, false);
    }
  }
}
