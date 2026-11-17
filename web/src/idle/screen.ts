import { accentOf, colours, DEFAULT_ACCENT } from '$lib/brand.svelte';
import { tinted, tintedCanvas } from '$lib/tint';
import { WALLPAPER_PICTURE } from '$lib/walls';
import {
  DEFAULT_WORDS,
  drawIdle,
  fonts,
  loadPicture,
  pictureLimit,
  publicImageUrl,
  Pyramid,
  sharpen,
  shrink,
  type IdleLook,
  type IdleWords,
  UNREAD_MAX,
} from './render';

const query = new URLSearchParams(location.search);
const fragment = new URLSearchParams(location.hash.replace(/^#/, ''));

const clean = (value: string | null, pattern: RegExp, limit: number) => (value ?? '').replace(pattern, '').slice(
  0,
  limit
);

const host = clean(query.get('host'), /[^\w-]/g, 64);
const browser = clean(query.get('browser'), /[^\w-]/g, 64);
const secret = clean(fragment.get('s'), /[^0-9a-f]/gi, 64);
export const W = Math.max(64, Math.min(4096, Number(query.get('width')) || innerWidth));
export const H = Math.max(64, Math.min(4096, Number(query.get('height')) || innerHeight));
const STATES = new Set(['idle', 'sleep', 'oos', 'off']);

let screen: CanvasRenderingContext2D;
let upscale: 'sharp' | 'smooth' = 'smooth';
const layers = [document.createElement('canvas'), document.createElement('canvas')];
const scratch = document.createElement('canvas');

let words: IdleWords = DEFAULT_WORDS;
let accent = DEFAULT_ACCENT;
let base: IdleLook | null = null;
let look: IdleLook | null = null;
let size = { w: W, h: H };
let mix = 0;
let target = 0;
let fadeMs = 350;
let fadeFrom = 0;
let fadeStart = 0;
let frame = 0;
let pending: number | null = null;
let fontsReady = false;
const pictures = new Map<string, Promise<Pyramid | null>>();
const ready = new Map<string, Pyramid | null>();

function cleanLook(value: any): IdleLook | null {
  if (!value || typeof value !== 'object') return null;

  const text = (input: unknown, limit: number) => (typeof input === 'string' ? input.slice(0, limit) : undefined);
  const url = typeof value.url === 'string' && publicImageUrl(value.url) ? value.url : undefined;

  const file = (input: unknown) => (typeof input === 'string' && /^web\/build\/[\w/-]+\.\w+$/.test(input) ? input : undefined);
  const picture = file(value.picture);

  return {
    state: STATES.has(value.state) ? value.state : 'idle',
    preset: text(value.preset, 32),
    picture,
    url,
    wall: text(value.wall, 32),
    plain: value.plain === true && picture !== undefined ? true : undefined,
    spare: file(value.spare),
    name: text(value.name, 40),
    brightness: Number.isFinite(Number(value.brightness)) ? Number(value.brightness) : 100,
    dim: Number.isFinite(Number(value.dim)) ? Math.max(0, Math.min(90, Number(value.dim))) : undefined,
    message: text(value.message, 160),
    unread: Number.isInteger(Number(value.unread)) && Number(value.unread) > 0 ? Math.min(UNREAD_MAX, Number(value.unread)) : undefined,
  };
}

function cleanWords(value: any): IdleWords {
  if (!value || typeof value !== 'object') {
    return DEFAULT_WORDS;
  }

  const pick = (key: keyof IdleWords) => (typeof value[key] === 'string' && value[key]
    ? value[key]
    : DEFAULT_WORDS[key]);

  return {
    oos: pick('oos'),
    oosLine: pick('oosLine'),
    unread: pick('unread'),
    unreadOne: pick('unreadOne'),
  };
}

function sourceOf(value: IdleLook) {
  if (value.url) {
    return value.url;
  }

  return value.picture ? value.picture.replace(/^web\/build\//, '') : null;
}

function fallback(value: IdleLook): IdleLook {
  return { ...value, picture: value.spare ?? WALLPAPER_PICTURE, plain: undefined };
}

function unscaled(width: number, height: number) {
  return Math.max(W / width, H / height) === 1 && (width - W) % 2 === 0 && (height - H) % 2 === 0;
}

async function tintedPicture(src: string, shade: string) {
  const canvas = await tintedCanvas(src, shade, unscaled);

  return canvas ? new Pyramid(canvas) : loadPicture(await tinted(src, shade), pictureLimit(W, H));
}

function want(value: IdleLook | null) {
  const src = value && sourceOf(value);

  if (!src || pictures.has(src)) return;

  const stock = !value.url && !value.plain && accent !== DEFAULT_ACCENT;
  const loading = stock ? tintedPicture(src, accent) : loadPicture(src, pictureLimit(W, H));

  pictures.set(src, loading);

  loading.then((picture) => {
    ready.set(src, picture);

    if (!picture && value.plain) {
      want(fallback(value));
    }

    paint();
  });
}

function forget(...keep: (IdleLook | null)[]) {
  const wanted = new Set(keep.map((value) => value && sourceOf(value)));

  if (keep.some((value) => value?.plain)) {
    wanted.add(sourceOf(fallback(keep.find((value) => value?.plain)!)));
  }

  for (const src of [...pictures.keys()]) {
    if (!wanted.has(src)) {
      pictures.delete(src);
      ready.delete(src);
    }
  }
}

function pictureOf(value: IdleLook) {
  const src = sourceOf(value);

  return src ? ready.get(src) ?? null : null;
}

function shown(value: IdleLook): IdleLook {
  const src = sourceOf(value);

  if (value.plain && src && ready.has(src) && !ready.get(src)) {
    return fallback(value);
  }

  if (value.url && src && ready.has(src) && !ready.get(src) && base) {
    return { ...base, state: value.state, name: value.name, brightness: value.brightness, message: value.message, unread: value.unread };
  }

  return value;
}

function wantFonts() {
  if (!base || !fontsReady) return;

  const ctx = scratch.getContext('2d')!;

  for (const value of [base, look]) {
    if (value) {
      drawIdle(ctx, W, H, {
        look: shown(value),
        words,
        picture: null,
        accent: colours(accent).text,
        accentOn: colours(accent).on,
      });
    }
  }
}

function draw(layer: HTMLCanvasElement, value: IdleLook) {
  const visible = shown(value);
  const full = document.createElement('canvas');

  full.width = W;
  full.height = H;

  drawIdle(full.getContext('2d', { willReadFrequently: true })!, W, H, {
    look: visible,
    words,
    picture: pictureOf(visible),
    accent: colours(accent).text,
    accentOn: colours(accent).on,
  });

  layer.width = size.w;
  layer.height = size.h;

  const ctx = layer.getContext('2d', { willReadFrequently: true })!;

  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';

  if (size.w === W && size.h === H) {
    ctx.drawImage(full, 0, 0);

    return;
  }

  ctx.drawImage(shrink(full, size.w, size.h), 0, 0);
  sharpen(ctx, size.w, size.h);
}

function compose() {
  screen.imageSmoothingEnabled = upscale === 'smooth' || (size.w === W && size.h === H);
  screen.imageSmoothingQuality = 'low';
  screen.globalAlpha = 1;
  screen.drawImage(layers[0], 0, 0, W, H);

  if (mix > 0) {
    screen.globalAlpha = mix;
    screen.drawImage(layers[1], 0, 0, W, H);
    screen.globalAlpha = 1;
  }
}

function paint() {
  if (!base || !fontsReady) return;

  draw(layers[0], base);

  if (look && JSON.stringify(look) === JSON.stringify(base)) {
    layers[1].width = layers[0].width;
    layers[1].height = layers[0].height;
    layers[1].getContext('2d')!.drawImage(layers[0], 0, 0);
  } else if (look) draw(layers[1], look);

  compose();
  report();
}

function post(name: string, body: Record<string, unknown>, attempt = 0) {
  if (!host || !browser) return;

  fetch(`https://${host}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ browser, s: secret, ...body }),
  }).catch(() => {
    if (attempt < 5) {
      setTimeout(() => post(name, body, attempt + 1), 500);
    }
  });
}

function waiting() {
  for (const value of [base, look]) {
    const src = value && sourceOf(value);
    const drawn = value && src && ready.has(src) ? sourceOf(shown(value)) : src;

    if ((src && !ready.has(src)) || (drawn && !ready.has(drawn))) return true;
  }

  return false;
}

function report() {
  if (pending === null || !base || waiting()) return;

  const serial = pending;

  pending = null;
  post('device:painted', { serial });
}

function step(now: number) {
  frame = 0;

  const share = fadeMs > 0 ? Math.min(1, (now - fadeStart) / fadeMs) : 1;

  mix = fadeFrom + (target - fadeFrom) * share;
  compose();

  if (share < 1) frame = requestAnimationFrame(step);
}

function fadeTo(value: number) {
  target = value;
  fadeFrom = mix;
  fadeStart = performance.now();

  if (!frame) {
    frame = requestAnimationFrame(step);
  }
}

function onMessage(event: MessageEvent) {
  const message = event.data;

  if (!message || typeof message !== 'object' || (secret && message.__s !== secret)) return;

  switch (message.type) {
    case 'look': {
      const colour = message.brand && typeof message.brand === 'object' ? message.brand.accent : message.accent;

      if (colour !== undefined && accentOf(colour) !== accent) {
        accent = accentOf(colour);
        pictures.clear();
        ready.clear();
      }

      base = cleanLook(message.base) ?? base;
      look = cleanLook(message.look);

      if (message.words) {
        words = cleanWords(message.words);
      }

      if (message.upscale === 'smooth' || message.upscale === 'sharp') {
        upscale = message.upscale;
      }

      if (Number.isFinite(Number(message.fadeMs))) {
        fadeMs = Math.max(0, Math.min(2000, Number(message.fadeMs)));
      }

      pending = Number.isInteger(message.serial) ? message.serial : null;
      forget(base, look);
      want(base);
      want(look);
      mix = message.show === true ? mix : 0;

      if (message.show === true || !waiting()) paint();
      else wantFonts();

      if (message.show === true) fadeTo(1);
      else {
        target = 0;
        compose();
      }

      break;
    }
    case 'detail': {
      const w = Math.round(Number(message.w));
      const h = Math.round(Number(message.h));

      if (w >= 16 && h >= 16 && w <= W && h <= H && (w !== size.w || h !== size.h)) {
        size = { w, h };
        paint();
      }

      break;
    }
    case 'leave':
      fadeTo(0);
      break;
    case 'show':
      fadeTo(1);
      break;
  }
}

export function start(canvas: HTMLCanvasElement) {
  screen = canvas.getContext('2d', { alpha: false })!;
  window.addEventListener('message', onMessage);
  screen.fillStyle = '#070708';
  screen.fillRect(0, 0, W, H);

  fonts().then(() => {
    fontsReady = true;
    paint();

    requestAnimationFrame(() => requestAnimationFrame(() => post('device:ready', {
      width: innerWidth,
      height: innerHeight,
    })));
  });
}
