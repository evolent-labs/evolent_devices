export type Category = 'dealership' | 'work' | 'tools' | 'fun';

export interface Ability {
  icon: string;
  text: string;
}

export interface StoreApp {
  id: string;
  label: string;
  icon?: { path: string; color: string };
  description: string;
  size: number;
  version: string;
  builtin: boolean;
  fixed: boolean;
  installed: boolean;
  category?: Category;
  about?: string;
  can?: Ability[];
  pictures?: string[];
  cover?: string;
  accent?: string;
  publisher?: string;
  kinds?: string[];
  network?: boolean;
  watch?: string;
}

export const FIXED_APPS = ['store', 'settings', 'files', 'photos'];
export const STORE_BUILTINS = ['notes'];
export const CATEGORIES: Category[] = ['dealership', 'work', 'tools', 'fun'];
export const CAN_ICONS = ['check', 'wifi', 'offline', 'eye', 'cover', 'bell', 'key', 'lock', 'shield', 'devices', 'pin', 'disk'];
export const STORE_KINDS = ['laptop', 'pc', 'tablet'];
export const MAX_PICTURES = 5;
export const MAX_ABILITIES = 6;
export const MAX_SUGGESTED = 5;
export const ABOUT_LENGTH = 400;

const FULL_BARS = 4;
const MIN_MS = 1400;
const MAX_MS = 6000;
const MS_PER_MB = 18;
const SLOWEST = 2.4;
const PICTURE = /^https:\/\/[^\s"'<>\\()]+$/;
const LOCAL_PICTURE = /^[\w-]+(\/[\w.-]+)*\.(webp|png|jpe?g)$/i;
const PUBLISHER = /^[\w-]{1,64}$/;
const HEX = /^#[0-9a-f]{6}$/i;
const GREY_SPREAD = 0.2;
const DARKEST = 40;

export const isFixed = (id: string) => FIXED_APPS.includes(id);

export const inStore = (app: StoreApp) => !app.builtin || STORE_BUILTINS.includes(app.id);

export function sizeOf(id: string, given?: number) {
  if (typeof given === 'number' && Number.isFinite(given) && given > 0) {
    return Math.round(given);
  }

  let sum = 0;

  for (const char of id) {
    sum = (sum * 31 + char.charCodeAt(0)) % 997;
  }

  return 16 + (sum % 140);
}

export function sizeText(size: number) {
  return size >= 1000 ? (Math.round(size / 100) / 10).toString() + ' GB' : size + ' MB';
}

export function downloadMs(size: number, bars: number, wired: boolean) {
  const signal = wired ? FULL_BARS : Math.max(1, Math.min(FULL_BARS, Math.round(bars)));
  const slow = 1 + ((FULL_BARS - signal) / (FULL_BARS - 1)) * (SLOWEST - 1);

  return Math.round(Math.min(MAX_MS, Math.max(MIN_MS, MIN_MS + size * MS_PER_MB) * slow));
}

export function progressAt(elapsed: number, total: number) {
  if (total <= 0 || elapsed >= total) return 100;

  const share = Math.max(0, elapsed / total);

  return Math.min(99, Math.round((1 - (1 - share) * (1 - share)) * 100));
}

export function sortApps(list: StoreApp[]) {
  return [...list].sort((a, b) => {
    if (a.builtin !== b.builtin) return a.builtin ? 1 : -1;

    return a.label.localeCompare(b.label);
  });
}

export function findApps(list: StoreApp[], query: string, onlyInstalled: boolean, category: Category | '' = '') {
  const wanted = query.trim().toLowerCase();

  return list.filter((app) => {
    if (onlyInstalled && !app.installed) return false;
    if (category && app.category !== category) return false;
    if (!wanted) return true;

    return [app.label, app.description, app.category ?? '', app.publisher ?? ''].some((text) => text.toLowerCase().includes(wanted));
  });
}

export function suggestions(list: StoreApp[], max = MAX_SUGGESTED) {
  const open = list.filter((app) => !app.installed && !app.fixed);
  const hosted = open.filter((app) => !app.builtin);

  return (hosted.length ? hosted : open).slice(0, Math.max(0, max));
}

export function countBy(list: StoreApp[], category: Category) {
  return list.filter((app) => app.category === category).length;
}

export function cleanIds(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;

  return value.filter((id): id is string => typeof id === 'string' && /^[a-z][a-z0-9_]{1,31}$/.test(id));
}

export function cleanCategory(value: unknown, fallback: Category = 'tools'): Category {
  return CATEGORIES.includes(value as Category) ? (value as Category) : fallback;
}

export const categoryOf = (value: unknown, publisher: string) =>
  cleanCategory(value, /dealer/i.test(publisher) ? 'dealership' : 'tools');

export const isLocalPicture = (value: string) => LOCAL_PICTURE.test(value) && !value.includes('..');

export function cleanPictures(value: unknown): string[] {
  if (!Array.isArray(value)) return [];

  const list: string[] = [];

  for (const entry of value) {
    if (typeof entry === 'string' && entry.length <= 512 && (PICTURE.test(entry) || isLocalPicture(entry)) && !list.includes(entry)) {
      list.push(entry);
    }
  }

  return list.slice(0, MAX_PICTURES);
}

export function cleanAbilities(value: unknown): Ability[] {
  if (!Array.isArray(value)) return [];

  const list: Ability[] = [];

  for (const entry of value) {
    const raw = typeof entry === 'string' ? { icon: 'check', text: entry } : entry && typeof entry === 'object' ? (entry as Record<string, unknown>) : null;
    const text = typeof raw?.text === 'string' ? raw.text.replace(/\s+/g, ' ').trim().slice(0, 80) : '';

    if (!text) continue;

    list.push({ icon: CAN_ICONS.includes(String(raw?.icon)) ? String(raw?.icon) : 'check', text });
  }

  return list.slice(0, MAX_ABILITIES);
}

export function cleanCover(value: unknown) {
  return typeof value === 'string' && value.length <= 512 && (PICTURE.test(value) || isLocalPicture(value)) ? value : undefined;
}

export const cleanAccent = (value: unknown) => (typeof value === 'string' && HEX.test(value) ? value.toUpperCase() : undefined);

export function isGrey(hex: string) {
  const value = parseInt(hex.slice(1), 16);
  const channels = [value >> 16, (value >> 8) & 255, value & 255];
  const high = Math.max(...channels);

  return high < DARKEST || (high - Math.min(...channels)) / high < GREY_SPREAD;
}

export function toneOf(app: Pick<StoreApp, 'accent' | 'icon'>, fallback: string) {
  const own = cleanAccent(app.accent);

  if (own) return own;

  const icon = cleanAccent(app.icon?.color);

  return icon && !isGrey(icon) ? icon : fallback;
}

export const cleanAbout = (value: unknown) => (typeof value === 'string' ? value.replace(/\s+/g, ' ').trim().slice(0, ABOUT_LENGTH) : '');

export const cleanPublisher = (value: unknown) => (typeof value === 'string' && PUBLISHER.test(value) ? value : '');

export function parts(text: string, query: string): { text: string; hit: boolean }[] {
  const wanted = query.trim().toLowerCase();

  if (!wanted) return [{ text, hit: false }];

  const out: { text: string; hit: boolean }[] = [];
  let rest = text;
  let at = rest.toLowerCase().indexOf(wanted);

  while (at >= 0) {
    if (at > 0) out.push({ text: rest.slice(0, at), hit: false });

    out.push({ text: rest.slice(at, at + wanted.length), hit: true });
    rest = rest.slice(at + wanted.length);
    at = rest.toLowerCase().indexOf(wanted);
  }

  if (rest) out.push({ text: rest, hit: false });

  return out;
}

export function storeInfo(raw: Record<string, unknown>) {
  const publisher = cleanPublisher(raw.resource);

  return {
    category: categoryOf(raw.category, publisher),
    about: cleanAbout(raw.about) || undefined,
    can: cleanAbilities(raw.can),
    pictures: cleanPictures(raw.pictures),
    cover: cleanCover(raw.cover),
    accent: cleanAccent(raw.accent),
    publisher: publisher || undefined,
    kinds: Array.isArray(raw.kinds) ? STORE_KINDS.filter((kind) => (raw.kinds as unknown[]).includes(kind)) : undefined,
  };
}

export function rgbOf(hex: unknown) {
  const match = typeof hex === 'string' ? /^#([0-9a-f]{6})$/i.exec(hex) : null;

  if (!match) return '';

  const value = parseInt(match[1], 16);

  return `${value >> 16}, ${(value >> 8) & 255}, ${value & 255}`;
}
