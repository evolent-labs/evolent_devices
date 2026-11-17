export interface Mapping {
  inverse: number[];
  width: number;
  height: number;
  side: number;
}

const TINY = 1e-12;

export function buildMapping(screen: unknown): Mapping | null {
  if (!Array.isArray(screen) || screen.length < 10) return null;

  const values = screen.map(Number);

  if (!values.every(Number.isFinite)) return null;

  const [x0, y0, x1, y1, x3, y3, x2, y2, width, height] = values;
  const sx = x0 - x1 + x2 - x3;
  const sy = y0 - y1 + y2 - y3;
  let a, b, c, d, e, f, g, h;

  if (Math.abs(sx) < TINY && Math.abs(sy) < TINY) {
    a = x1 - x0;
    b = x3 - x0;
    c = x0;
    d = y1 - y0;
    e = y3 - y0;
    f = y0;
    g = 0;
    h = 0;
  } else {
    const dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    const den = dx1 * dy2 - dx2 * dy1;

    if (Math.abs(den) < TINY) return null;

    g = (sx * dy2 - dx2 * sy) / den;
    h = (dx1 * sy - sx * dy1) / den;
    a = x1 - x0 + g * x1;
    b = x3 - x0 + h * x3;
    c = x0;
    d = y1 - y0 + g * y1;
    e = y3 - y0 + h * y3;
    f = y0;
  }

  const det = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g);

  const inverse = [
    e - f * h,
    c * h - b,
    b * f - c * e,
    f * g - d,
    a - c * g,
    c * d - a * f,
    d * h - e * g,
    b * g - a * h,
    a * e - b * d,
  ];

  if (!(Math.abs(det) > TINY) || !inverse.every(Number.isFinite) || width < 2 || height < 2) return null;

  const side = Math.sign(inverse[6] * x0 + inverse[7] * y0 + inverse[8]);

  return { inverse, width: Math.floor(width), height: Math.floor(height), side };
}

export function pixelFor(mapping: Mapping | null, x: number, y: number, clamp = false): [number, number] | null | undefined {
  if (!mapping) return null;

  const m = mapping.inverse;
  const w = m[6] * x + m[7] * y + m[8];

  if (Math.abs(w) < TINY) return null;

  let u = (m[0] * x + m[1] * y + m[2]) / w;
  let v = (m[3] * x + m[4] * y + m[5]) / w;

  if (clamp && Math.sign(w) === mapping.side) {
    u = Math.max(0, Math.min(1, u));
    v = Math.max(0, Math.min(1, v));
  }

  if (!(u >= 0 && u <= 1 && v >= 0 && v <= 1)) return undefined;

  return [
    Math.min(mapping.width - 1, Math.floor(u * mapping.width)),
    Math.min(mapping.height - 1, Math.floor(v * mapping.height)),
  ];
}

export const TEXT_CHUNK = 64;

export function textChunks(value: string): string[] {
  const clean = Array.from(value.replace(/[\r\n\t]+/g, ' ').replace(/[\u0000-\u001f\u007f]/g, ''));
  const chunks: string[] = [];

  for (let at = 0; at < clean.length; at += TEXT_CHUNK) {
    chunks.push(clean.slice(at, at + TEXT_CHUNK).join(''));
  }

  return chunks;
}

export const CONTROL_KEYS = [
  'Backspace',
  'Delete',
  'Enter',
  'Tab',
  'Escape',
  'ArrowLeft',
  'ArrowRight',
  'ArrowUp',
  'ArrowDown',
  'Home',
  'End',
];

export const OS_SHORTCUTS = ['a', 'l'];

export type OverlayKey = { action: 'close' } | { action: 'key'; key: string; ctrl: boolean } | null;

export function overlayKey(key: string, ctrl: boolean, alt: boolean, os: boolean, editing: boolean): OverlayKey {
  if (!os && !editing && (key === 'Escape' || key === 'Backspace')) {
    return { action: 'close' };
  }

  const letter = key.length === 1 ? key.toLowerCase() : '';

  if (ctrl && !alt && (letter === 'a' || (os && OS_SHORTCUTS.includes(letter)))) {
    return { action: 'key', key: letter, ctrl: true };
  }

  if (CONTROL_KEYS.includes(key)) {
    return { action: 'key', key, ctrl };
  }

  return null;
}
