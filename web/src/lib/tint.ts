import { accentOf, brand, colours, DEFAULT_ACCENT } from './brand.svelte';
import { hexToRgb } from './hex';
import { designOf, recolour } from './recolour';

const SHADES = 5;

interface Shade {
  jobs: Map<string, Promise<string>>;
  ready: Map<string, string>;
  made: string[];
  used: number;
}

const shades = new Map<string, Shade>();
let clock = 0;
let stale: string[] = [];

function dropOldest(keep: string) {
  const pinned = accentOf(brand.accent);
  let oldest = '';
  let when = Infinity;

  for (const [hex, entry] of shades) {
    if (hex !== keep && hex !== pinned && entry.used < when) {
      oldest = hex;
      when = entry.used;
    }
  }

  const entry = shades.get(oldest);

  if (!entry) return;

  for (const url of stale) URL.revokeObjectURL(url);

  stale = entry.made;
  shades.delete(oldest);
}

function shadeOf(hex: string) {
  let entry = shades.get(hex);

  if (!entry) {
    if (shades.size >= SHADES) dropOldest(hex);

    entry = { jobs: new Map(), ready: new Map(), made: [], used: 0 };
    shades.set(hex, entry);
  }

  entry.used = ++clock;

  return entry;
}

function cached(hex: string, key: string) {
  const entry = shades.get(hex);
  const url = entry?.ready.get(key);

  if (!entry || !url) return null;

  entry.used = ++clock;

  return url;
}

function remember(hex: string, key: string, fallback: string, make: () => Promise<string>) {
  const entry = shadeOf(hex);
  let job = entry.jobs.get(key);

  if (!job) {
    job = make()
      .then((url) => {
        if (url === fallback) return url;

        if (shades.get(hex) === entry) {
          entry.made.push(url);
          entry.ready.set(key, url);
        } else {
          stale.push(url);
        }

        return url;
      })
      .catch(() => fallback);
    entry.jobs.set(key, job);
  }

  return job;
}

export function tintedNow(src: string, accent: string): string | null {
  const hex = accentOf(accent);

  if (hex === DEFAULT_ACCENT || !src) return src;

  return cached(hex, src);
}

export function tinted(src: string, accent: string): Promise<string> {
  const hex = accentOf(accent);

  if (hex === DEFAULT_ACCENT || !src) return Promise.resolve(src);

  return remember(hex, src, src, () => paint(src, hex));
}

export async function tintedCanvas(src: string, accent: string, fits: (width: number, height: number) => boolean) {
  const hex = accentOf(accent);

  if (hex === DEFAULT_ACCENT || !src) return null;

  try {
    const image = await decoded(src);

    return fits(image.naturalWidth, image.naturalHeight) ? recoloured(image, hex, src) : null;
  } catch {
    return null;
  }
}

async function decoded(src: string) {
  const image = new Image();
  image.src = src;
  await image.decode();

  return image;
}

function recoloured(image: HTMLImageElement, hex: string, src: string) {
  const canvas = document.createElement('canvas');
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;

  const context = canvas.getContext('2d', { willReadFrequently: true });

  if (!context || !canvas.width || !canvas.height) return null;

  context.drawImage(image, 0, 0);

  const frame = context.getImageData(0, 0, canvas.width, canvas.height);
  recolour(frame.data, canvas.width, canvas.height, hexToRgb(colours(hex).text), designOf(src));
  context.putImageData(frame, 0, 0);

  return canvas;
}

async function paint(src: string, hex: string) {
  const canvas = recoloured(await decoded(src), hex, src);

  if (!canvas) return src;

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));

  if (!blob) return src;

  return URL.createObjectURL(blob);
}
