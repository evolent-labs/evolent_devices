import { shrinkBytes, srgbOf } from './light';
import { PICTURE_SIDE_MAX, publicImageUrl } from './links';
import { unreadLabel } from './unread';

export { pictureLimit, publicImageUrl } from './links';
export { UNREAD_MAX } from './unread';

export type IdleState = 'idle' | 'sleep' | 'oos' | 'off';

export interface IdleLook {
  state: IdleState;
  preset?: string;
  picture?: string;
  url?: string;
  wall?: string;
  plain?: boolean;
  spare?: string;
  name?: string;
  brightness: number;
  dim?: number;
  message?: string;
  unread?: number;
}

export const SLEEP_DIM = 50;

export interface IdleWords {
  oos: string;
  oosLine: string;
  unread: string;
  unreadOne: string;
}

const FAMILY = { sans: 'Poppins, Arial, sans-serif', mono: '"JetBrains Mono", monospace' };
const LEVELS_MIN = 48;
const SHARPEN = 0.9;

export const DEFAULT_WORDS: IdleWords = {
  oos: 'Out of service',
  oosLine: 'This screen is switched off for now.',
  unread: 'New notifications',
  unreadOne: 'New notification',
};

export function fonts() {
  const wanted = ['500 40px Poppins', '600 40px Poppins', '800 40px Poppins', '600 40px "JetBrains Mono"'];

  return Promise.all(wanted.map((font) => document.fonts.load(font).catch(() => []))).then(() => undefined);
}

export class Pyramid {
  levels: (HTMLCanvasElement | HTMLImageElement)[] = [];
  width: number;
  height: number;
  shown: HTMLCanvasElement | null = null;

  constructor(source: HTMLCanvasElement | HTMLImageElement) {
    this.levels = [source];
    this.width = source instanceof HTMLImageElement ? source.naturalWidth : source.width;
    this.height = source instanceof HTMLImageElement ? source.naturalHeight : source.height;
  }

  pick(width: number, height: number) {
    let w = this.width;
    let h = this.height;
    let index = 0;

    while (Math.min(w, h) / 2 >= LEVELS_MIN && Math.floor(w / 2) >= width && Math.floor(h / 2) >= height) {
      w = Math.floor(w / 2);
      h = Math.floor(h / 2);
      index += 1;

      if (!this.levels[index]) {
        const canvas = document.createElement('canvas');

        canvas.width = w;
        canvas.height = h;

        const ctx = canvas.getContext('2d')!;

        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';
        ctx.drawImage(this.levels[index - 1], 0, 0, w, h);
        this.levels[index] = canvas;
      }
    }

    return this.levels[index];
  }
}

export function sharpen(ctx: CanvasRenderingContext2D, width: number, height: number, amount = SHARPEN) {
  let data: ImageData;

  try {
    data = ctx.getImageData(0, 0, width, height);
  } catch {
    return false;
  }

  const src = data.data;
  const out = new Uint8ClampedArray(src);
  const row = width * 4;

  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const i = y * row + x * 4;

      for (let c = 0; c < 3; c++) {
        const k = i + c;
        const n = src[k - row], s = src[k + row], w = src[k - 4], e = src[k + 4];
        const nw = src[k - row - 4], ne = src[k - row + 4], sw = src[k + row - 4], se = src[k + row + 4];
        const centre = src[k];
        const blur = (4 * centre + 2 * (n + s + w + e) + nw + ne + sw + se) / 16;
        const low = Math.min(centre, n, s, w, e, nw, ne, sw, se);
        const high = Math.max(centre, n, s, w, e, nw, ne, sw, se);

        out[k] = Math.min(high, Math.max(low, centre + amount * (centre - blur)));
      }
    }
  }

  data.data.set(out);
  ctx.putImageData(data, 0, 0);

  return true;
}

export function shrink(source: HTMLCanvasElement, width: number, height: number) {
  const target = document.createElement('canvas');

  target.width = width;
  target.height = height;

  const ctx = target.getContext('2d', { willReadFrequently: true })!;
  let data: ImageData;

  try {
    data = source.getContext('2d', { willReadFrequently: true })!.getImageData(0, 0, source.width, source.height);
  } catch {
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(source, 0, 0, width, height);

    return target;
  }

  ctx.putImageData(
    new ImageData(srgbOf(shrinkBytes(data.data, data.width, data.height, width, height)), width, height),
    0,
    0
  );

  return target;
}

function cover(ctx: CanvasRenderingContext2D, pyramid: Pyramid, width: number, height: number) {
  let shown = pyramid.shown;

  if (!shown || shown.width !== width || shown.height !== height) {
    shown = document.createElement('canvas');
    shown.width = width;
    shown.height = height;

    const own = shown.getContext('2d', { willReadFrequently: true })!;
    const scale = Math.max(width / pyramid.width, height / pyramid.height);
    const w = pyramid.width * scale;
    const h = pyramid.height * scale;

    own.imageSmoothingEnabled = true;
    own.imageSmoothingQuality = 'high';
    own.drawImage(pyramid.pick(w, h), (width - w) / 2, (height - h) / 2, w, h);

    if (width < pyramid.width) {
      sharpen(own, width, height);
    }

    pyramid.shown = shown;
  }

  ctx.drawImage(shown, 0, 0);
}

function outOfService(ctx: CanvasRenderingContext2D, width: number, height: number, look: IdleLook, words: IdleWords, accent: string) {
  ctx.fillStyle = 'rgba(6, 6, 9, 0.82)';
  ctx.fillRect(0, 0, width, height);

  const unit = height / 100;

  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = accent;
  ctx.font = `600 ${5.6 * unit}px ${FAMILY.mono}`;
  ctx.letterSpacing = `${0.6 * unit}px`;
  ctx.fillText(words.oos.toUpperCase(), width / 2, height * 0.36);
  ctx.letterSpacing = '0px';
  ctx.fillStyle = '#f4f4f5';

  const line = look.message || words.oosLine;
  let size = 10 * unit;

  ctx.font = `600 ${size}px ${FAMILY.sans}`;

  const words1 = line.split(/\s+/);
  const lines: string[] = [];
  const max = width * 0.82;
  let current = '';

  for (const word of words1) {
    const next = current ? current + ' ' + word : word;

    if (ctx.measureText(next).width > max && current) {
      lines.push(current);
      current = word;
    } else current = next;
  }

  if (current) {
    lines.push(current);
  }

  if (lines.length > 3) {
    size *= 0.75;
    ctx.font = `600 ${size}px ${FAMILY.sans}`;
  }

  lines.slice(0, 4).forEach((text, index) => ctx.fillText(
    text,
    width / 2,
    height * 0.36 + 11 * unit + index * size * 1.22
  ));
}

export interface DrawInput {
  look: IdleLook;
  words: IdleWords;
  picture: Pyramid | null;
  accent: string;
  accentOn?: string;
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + width, y, x + width, y + height, radius);
  ctx.arcTo(x + width, y + height, x, y + height, radius);
  ctx.arcTo(x, y + height, x, y, radius);
  ctx.arcTo(x, y, x + width, y, radius);
  ctx.closePath();
}

function unreadPill(ctx: CanvasRenderingContext2D, width: number, height: number, look: IdleLook, words: IdleWords, accent: string, on: string) {
  const label = unreadLabel(look.unread, words);

  if (!label) return;

  const unit = height / 100;
  const tall = 8.8 * unit;
  const pad = 1.25 * unit;
  const disc = tall - pad * 2;

  ctx.save();
  ctx.font = `600 ${3.5 * unit}px ${FAMILY.sans}`;
  ctx.letterSpacing = '0px';

  const measured = ctx.measureText(label.text).width;
  const wide = pad + disc + 2.2 * unit + measured + 3.2 * unit;
  const x = (width - wide) / 2;
  const y = height * 0.875 - tall / 2;

  ctx.globalAlpha = look.state === 'sleep' ? 0.9 : 1;
  ctx.shadowColor = 'rgba(0, 0, 0, 0.5)';
  ctx.shadowBlur = 3 * unit;
  roundRect(ctx, x, y, wide, tall, tall / 2);
  ctx.fillStyle = 'rgba(10, 10, 15, 0.84)';
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.lineWidth = Math.max(1, 0.22 * unit);
  ctx.strokeStyle = accent;
  ctx.globalAlpha *= 0.6;
  ctx.stroke();
  ctx.globalAlpha = look.state === 'sleep' ? 0.9 : 1;
  ctx.beginPath();
  ctx.arc(x + pad + disc / 2, y + tall / 2, disc / 2, 0, Math.PI * 2);
  ctx.fillStyle = accent;
  ctx.fill();
  ctx.fillStyle = on;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = `700 ${(label.badge.length > 2 ? 2.8 : 3.5) * unit}px ${FAMILY.sans}`;
  ctx.fillText(label.badge, x + pad + disc / 2, y + tall / 2 + 0.2 * unit);
  ctx.font = `600 ${3.5 * unit}px ${FAMILY.sans}`;
  ctx.textAlign = 'left';
  ctx.fillStyle = '#f4f4f5';
  ctx.fillText(label.text, x + pad + disc + 2.2 * unit, y + tall / 2 + 0.2 * unit);
  ctx.restore();
}

export function drawIdle(ctx: CanvasRenderingContext2D, width: number, height: number, input: DrawInput) {
  const { look, words, picture, accent, accentOn } = input;

  ctx.save();
  ctx.fillStyle = '#070708';
  ctx.fillRect(0, 0, width, height);

  if (look.state === 'off') {
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, width, height);
    ctx.restore();

    return;
  }

  if (picture) {
    cover(ctx, picture, width, height);
  }

  if (look.state === 'oos') {
    outOfService(ctx, width, height, look, words, accent);
  }

  const bright = Math.min(100, Math.max(20, look.brightness || 100)) / 100;
  const rest = look.state === 'sleep' ? 1 - Math.min(90, Math.max(0, look.dim ?? SLEEP_DIM)) / 100 : 1;
  const dim = 1 - bright * rest;

  if (dim > 0) {
    ctx.fillStyle = `rgba(0, 0, 0, ${dim.toFixed(3)})`;
    ctx.fillRect(0, 0, width, height);
  }

  if (look.state === 'idle' || look.state === 'sleep') {
    unreadPill(ctx, width, height, look, words, accent, accentOn ?? '#0a0a0f');
  }

  ctx.restore();
}

function loadImage(src: string, cors: boolean, timeoutMs: number): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();

    img.decoding = 'async';
    img.referrerPolicy = 'no-referrer';

    if (cors) {
      img.crossOrigin = 'anonymous';
    }

    const timer = setTimeout(() => {
      img.onload = img.onerror = null;
      img.removeAttribute('src');
      resolve(null);
    }, timeoutMs);

    img.onload = () => {
      clearTimeout(timer);
      resolve(img.naturalWidth > 0 ? img : null);
    };

    img.onerror = () => {
      clearTimeout(timer);
      resolve(null);
    };

    img.src = src;
  });
}

export async function loadPicture(src: string, maxPixels = 0, timeoutMs = 8000): Promise<Pyramid | null> {
  const remote = /^https:\/\//.test(src);

  if (remote && !publicImageUrl(src)) return null;

  let img = remote ? await loadImage(src, true, timeoutMs) : null;

  if (!img) {
    img = await loadImage(src, false, timeoutMs);
  }

  if (!img) return null;
  if (remote && (Math.max(img.naturalWidth, img.naturalHeight) > PICTURE_SIDE_MAX || (maxPixels > 0 && img.naturalWidth * img.naturalHeight > maxPixels))) return null;

  return new Pyramid(img);
}
