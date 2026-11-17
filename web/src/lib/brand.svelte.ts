import { hexToRgb } from './hex';
import { t } from './state.svelte';
import { cleanIdle, cleanWalls, DEFAULT_WALL, isIdleKind, wallChoices, wallId, wallOr, type IdlePictures, type OwnWall } from './wallIds';

type Rgb = [number, number, number];

export interface Brand {
  accent: string;
  logo: string;
  name: string;
  wallpaper: string;
  idle: IdlePictures;
  walls: OwnWall[];
  wall: string;
}

export interface BrandColours {
  fill: string;
  text: string;
  on: string;
  hover: string;
  adjusted: boolean;
}

export const DEFAULT_ACCENT = '#C3FF00';
export const PICTURE_SOURCE = /^(https:\/\/|data:image\/)/i;
export const BRAND_PRESETS = [
  DEFAULT_ACCENT,
  '#00BFFF',
  '#3B82F6',
  '#8B5CF6',
  '#EC4899',
  '#F82834',
  '#F97316',
  '#FACC15',
  '#22C55E',
  '#14B8A6',
  '#F4F4F5',
];

const BACKGROUND: Rgb = [10, 10, 15];
const DARK_TEXT = '#0A0A0F';
const LIGHT_TEXT = '#F4F4F5';
const NAMES = [
  '--accent',
  '--accent-rgb',
  '--accent-hover',
  '--accent-content',
  '--accent-bg',
  '--accent-line',
  '--accent-strong',
  '--accent-halo',
  '--accent-glow',
  '--accent-soft',
  '--accent-focus',
  '--accent-dark',
];

export const brand = $state<Brand>({ accent: DEFAULT_ACCENT, logo: '', name: '', wallpaper: DEFAULT_WALL, idle: cleanIdle(null), walls: [], wall: '' });

export const validHex = (value: unknown) => /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(String(value));

export const fullHex = (value: string) =>
  (value.length === 4 ? '#' + [...value.slice(1)].map((c) => c + c).join('') : value).toUpperCase();

export const accentOf = (value: unknown) => (validHex(value) ? fullHex(String(value)) : DEFAULT_ACCENT);

const channel = (value: number) => {
  const c = value / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
};
const luminance = ([r, g, b]: Rgb) => 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
const contrast = (a: Rgb, b: Rgb) => {
  const x = luminance(a),
    y = luminance(b);
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

const toHex = (rgb: number[]) =>
  '#' +
  rgb
    .map((v) => Math.round(v).toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase();
const rgba = ([r, g, b]: Rgb, alpha: number) => `rgba(${r}, ${g}, ${b}, ${alpha})`;

export function colours(accent: unknown): BrandColours {
  const rgb = hexToRgb(accentOf(accent));
  let text: number[] = rgb;

  for (let t = 0.05; contrast(text as Rgb, BACKGROUND) < 4.5 && t <= 1; t += 0.05) {
    text = rgb.map((v) => v + (255 - v) * t);
  }

  const shown = hexToRgb(toHex(text));
  const dark = hexToRgb(DARK_TEXT),
    light = hexToRgb(LIGHT_TEXT);

  return {
    fill: toHex(rgb),
    text: toHex(shown),
    on: contrast(shown, dark) >= contrast(shown, light) ? DARK_TEXT : LIGHT_TEXT,
    hover: toHex(shown.map((v) => v + (255 - v) * 0.3)),
    adjusted: toHex(shown) !== toHex(rgb),
  };
}

export function applyAccent(accent: unknown, root: HTMLElement = document.documentElement) {
  const colour = colours(accent);
  const rgb = hexToRgb(colour.text);
  const hover = hexToRgb(colour.hover);
  const values: Record<string, string> = {
    '--accent': colour.text,
    '--accent-rgb': rgb.join(', '),
    '--accent-hover': colour.hover,
    '--accent-content': colour.on,
    '--accent-bg': rgba(rgb, 0.08),
    '--accent-line': rgba(rgb, 0.25),
    '--accent-strong': rgba(rgb, 0.35),
    '--accent-halo': rgba(rgb, 0.16),
    '--accent-glow': rgba(rgb, 0.55),
    '--accent-soft': rgba(rgb, 0.05),
    '--accent-focus': rgba(hover, 0.35),
    '--accent-dark': toHex(rgb.map((v) => v * 0.8)),
  };
  const plain = colour.fill === DEFAULT_ACCENT;

  for (const name of NAMES) {
    if (plain) root.style.removeProperty(name);
    else root.style.setProperty(name, values[name]);
  }

  return colour;
}

export function cleanBrand(value: unknown, known: OwnWall[] = []): Brand {
  const input = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const walls = 'walls' in input ? cleanWalls(input.walls) : known;

  return {
    accent: accentOf(input.accent),
    logo: typeof input.logo === 'string' && PICTURE_SOURCE.test(input.logo) ? input.logo : '',
    name: typeof input.name === 'string' ? input.name.replace(/[<>]/g, '').trim().slice(0, 40) : '',
    wallpaper: wallId(input.wallpaper, walls) ?? DEFAULT_WALL,
    idle: cleanIdle(input.idle, walls),
    walls,
    wall: wallOr(input.wall, walls),
  };
}

export const osName = () => brand.name || t('os_name');

export const wallpapers = () => wallChoices(brand.walls);

export const wallName = (id: string) => brand.walls.find((entry) => entry.id === id)?.name ?? t('os_wall_' + DEFAULT_WALL);

export const idlePicture = (kind: string) => (isIdleKind(kind) ? brand.idle[kind] : '');

export function setBrand(value: unknown) {
  if (!value || typeof value !== 'object') return;

  Object.assign(brand, cleanBrand(value, $state.snapshot(brand.walls)));
  applyAccent(brand.accent);
}

export function brandLook(value: unknown) {
  if (!value || typeof value !== 'object') return;

  const { walls: _, ...shown } = $state.snapshot(brand);

  setBrand({ ...shown, ...(value as Record<string, unknown>) });
}
