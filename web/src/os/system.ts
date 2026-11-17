export const BUILTIN_IDS = ['files', 'notes', 'photos', 'store', 'settings'] as const;

export type BuiltinId = (typeof BUILTIN_IDS)[number];

export type DateOrder = 'dm' | 'md';

export interface Prefs {
  volume: number;
  clock24: boolean;
  dnd: boolean;
  quiet: string[];
  sound: boolean;
  seconds: boolean;
  dateFormat: DateOrder;
  reduceMotion: boolean;
  bright: number;
  sleep: number;
  lock: number;
  gamePopup: boolean;
  gameSound: boolean;
}

export const SLEEP_CHOICES = [0, 1, 2, 5, 10];
export const LOCK_CHOICES = [0, 1, 2, 5, 10, 30];

export const lockChoices = (deviceMinutes: number) => LOCK_CHOICES.filter((value) => value === 0 || !(deviceMinutes > 0) || value < deviceMinutes);

export const lockShown = (lock: number, deviceMinutes: number) => (lockChoices(deviceMinutes).includes(lock) ? lock : 0);

export interface Limits {
  notes: number;
  title: number;
  body: number;
  trash: number;
  photos: number;
  photoName: number;
  links: boolean;
  passwordMin: number;
  passwordMax: number;
}

export interface SystemInfo {
  apps: BuiltinId[];
  password: boolean;
  owner: boolean;
  canPassword: boolean;
  canWall: boolean;
  canManage: boolean;
  keeps: boolean;
  version: string;
  serial: string;
  ownerName: string;
  limits: Limits;
}

export const DEFAULT_PREFS: Prefs = {
  volume: 100,
  clock24: true,
  dnd: false,
  quiet: [],
  sound: true,
  seconds: false,
  dateFormat: 'dm',
  reduceMotion: false,
  bright: 100,
  sleep: 0,
  lock: 0,
  gamePopup: true,
  gameSound: true,
};

export const DEFAULT_LIMITS: Limits = {
  notes: 40,
  title: 60,
  body: 3000,
  trash: 20,
  photos: 24,
  photoName: 40,
  links: true,
  passwordMin: 4,
  passwordMax: 32,
};

const ID = /^[a-z][a-z0-9_]{1,31}$/;
const QUIET_MAX = 32;
const CONTROL = /[\u0000-\u001f\u007f]/g;
export const LINE = ' ';

export const isBuiltin = (id: string): id is BuiltinId => (BUILTIN_IDS as readonly string[]).includes(id);

const whole = (value: unknown, low: number, high: number, fallback: number) => {
  const number = Number(value);

  return Number.isFinite(number) ? Math.round(Math.min(high, Math.max(low, number))) : fallback;
};

const flag = (value: unknown, fallback: boolean) => (typeof value === 'boolean' ? value : fallback);
const choice = <T>(value: unknown, list: readonly T[], fallback: T) => (list.includes(value as T) ? (value as T) : fallback);

export function cleanPrefs(value: unknown): Prefs {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const quiet: string[] = [];

  if (Array.isArray(raw.quiet)) {
    for (const id of raw.quiet) {
      if (quiet.length >= QUIET_MAX) break;

      if (typeof id === 'string' && ID.test(id) && !quiet.includes(id)) {
        quiet.push(id);
      }
    }
  }

  return {
    volume: whole(raw.volume, 0, 100, DEFAULT_PREFS.volume),
    clock24: flag(raw.clock24, DEFAULT_PREFS.clock24),
    dnd: flag(raw.dnd, DEFAULT_PREFS.dnd),
    quiet,
    sound: flag(raw.sound, DEFAULT_PREFS.sound),
    seconds: flag(raw.seconds, DEFAULT_PREFS.seconds),
    dateFormat: choice(raw.dateFormat, ['dm', 'md'] as const, DEFAULT_PREFS.dateFormat),
    reduceMotion: flag(raw.reduceMotion, DEFAULT_PREFS.reduceMotion),
    bright: whole(raw.bright, 30, 100, DEFAULT_PREFS.bright),
    sleep: choice(raw.sleep, SLEEP_CHOICES, DEFAULT_PREFS.sleep),
    lock: choice(raw.lock, LOCK_CHOICES, DEFAULT_PREFS.lock),
    gamePopup: flag(raw.gamePopup, DEFAULT_PREFS.gamePopup),
    gameSound: flag(raw.gameSound, DEFAULT_PREFS.gameSound),
  };
}

export function cleanSystem(value: unknown): SystemInfo {
  const raw = value && typeof value === 'object' ? (value as Record<string, any>) : {};
  const limits = raw.limits && typeof raw.limits === 'object' ? raw.limits : {};
  const apps = Array.isArray(raw.apps) ? BUILTIN_IDS.filter((id) => raw.apps.includes(id)) : [];
  const text = (entry: unknown, max: number) => (typeof entry === 'string' ? entry.slice(0, max) : '');

  return {
    apps,
    password: raw.password === true,
    owner: raw.owner === true,
    canPassword: raw.canPassword === true,
    canWall: raw.canWall === true,
    canManage: raw.canManage === true,
    keeps: raw.keeps !== false,
    version: text(raw.version, 32),
    serial: text(raw.serial, 16),
    ownerName: text(raw.ownerName, 64),
    limits: {
      notes: whole(limits.notes, 1, 500, DEFAULT_LIMITS.notes),
      title: whole(limits.title, 8, 200, DEFAULT_LIMITS.title),
      body: whole(limits.body, 100, 20000, DEFAULT_LIMITS.body),
      trash: whole(limits.trash, 0, 500, DEFAULT_LIMITS.trash),
      photos: whole(limits.photos, 0, 200, DEFAULT_LIMITS.photos),
      photoName: whole(limits.photoName, 8, 64, DEFAULT_LIMITS.photoName),
      links: limits.links !== false,
      passwordMin: whole(limits.passwordMin, 1, 64, DEFAULT_LIMITS.passwordMin),
      passwordMax: whole(limits.passwordMax, 1, 64, DEFAULT_LIMITS.passwordMax),
    },
  };
}

const UNPRINTABLE = /[\u0000-\u001f\u007f-\u009f]/;

export function passwordValid(password: string, limits: Limits) {
  const length = [...password].length;

  return length >= limits.passwordMin && length <= limits.passwordMax && !UNPRINTABLE.test(password);
}

export const bytesOf = (text: string) => new TextEncoder().encode(text).length;

export function clipBytes(text: string, max: number) {
  let out = '';
  let used = 0;

  for (const char of text) {
    const size = bytesOf(char);

    if (used + size > max) break;

    out += char;
    used += size;
  }

  return out;
}

export function flat(text: string, max: number) {
  return clipBytes(text.replace(/\r\n?/g, '\n').replace(/\n/g, LINE).replace(CONTROL, ' '), max);
}

export function fileName(title: string, fallback: string) {
  const base = title.trim().replace(/[\\/:*?"<>|]/g, '').slice(0, 60) || fallback;

  return base.toLowerCase().endsWith('.txt') ? base : base + '.txt';
}

export function sizeText(bytes: number) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (Math.round((bytes / 1024) * 10) / 10).toString() + ' KB';

  return (Math.round((bytes / 1048576) * 10) / 10).toString() + ' MB';
}

export function firstLine(body: string, max = 48) {
  return (body.split('\n').find((line) => line.trim() !== '') ?? '').trim().slice(0, max);
}

export function linkName(url: string) {
  const path = url.split(/[?#]/)[0];
  const last = path.slice(path.lastIndexOf('/') + 1);

  try {
    return decodeURIComponent(last) || url;
  } catch {
    return last || url;
  }
}

export function photoLink(value: string) {
  const text = value.trim();

  if (text.length < 12 || text.length > 300 || !/^https:\/\/[^/?#@\s]+(\/[^\s]*)?$/.test(text)) return null;

  return text;
}
