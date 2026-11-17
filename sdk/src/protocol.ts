export const PROTOCOL = 1;
export const SDK_VERSION = '1.0.1';
export const HOST_RESOURCE = 'evolent_devices';
export const HOST_ORIGIN = 'https://cfx-nui-' + HOST_RESOURCE;

export const HOST_TYPES = [
  'os:open',
  'os:intent',
  'os:visibility',
  'os:key',
  'os:dblclick',
  'os:state',
  'os:close',
  'os:reply',
] as const;

export const APP_TYPES = [
  'hello',
  'ready',
  'activity',
  'editing',
  'unhandled',
  'cursor',
  'publish',
  'privatePointer',
  'notify',
  'recent',
  'badge',
  'close',
  'leave',
  'post',
] as const;

export type HostType = (typeof HOST_TYPES)[number];
export type AppType = (typeof APP_TYPES)[number];
export type StateValue = string | number | boolean;
export type FlatState = Record<string, StateValue>;

export const STATE_KEYS = 16;
export const STATE_BYTES = 2048;
const STATE_TEXT = 512;
const KEY = /^[A-Za-z][A-Za-z0-9_]{0,23}$/;
const CONTROL = /[\u0000-\u001f\u007f]/;

export function cleanFlatState(value: unknown): FlatState | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;

  const clean: FlatState = {};
  let keys = 0;
  let bytes = 2;

  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    if (!KEY.test(key)) return null;

    keys += 1;

    if (keys > STATE_KEYS) return null;

    if (typeof entry === 'number') {
      if (!Number.isFinite(entry)) return null;

      bytes += key.length + 24;
    } else if (typeof entry === 'boolean') {
      bytes += key.length + 8;
    } else if (typeof entry === 'string') {
      if (entry.length > STATE_TEXT || CONTROL.test(entry)) return null;

      bytes += key.length + new TextEncoder().encode(entry).length + 6;
    } else {
      return null;
    }

    clean[key] = entry;
  }

  return bytes <= STATE_BYTES ? clean : null;
}

export interface Notice {
  id?: string;
  title: string;
  body?: string;
  action?: string;
  intent?: Record<string, unknown>;
  at?: number;
}

const text = (value: unknown, max: number) => (typeof value === 'string'
  ? value.replace(/\s+/g, ' ').trim().slice(0, max)
  : '');

export function cleanNotice(value: unknown): Notice | null {
  if (!value || typeof value !== 'object') return null;

  const raw = value as Record<string, unknown>;
  const title = text(raw.title, 80);

  if (!title) return null;

  const notice: Notice = { title };
  const id = typeof raw.id === 'number' ? String(raw.id) : text(raw.id, 64);

  if (id) {
    notice.id = id;
  }

  const body = text(raw.body, 240);

  if (body) {
    notice.body = body;
  }

  const action = text(raw.action, 32);

  if (action) {
    notice.action = action;
  }

  if (raw.intent && typeof raw.intent === 'object' && !Array.isArray(raw.intent) && JSON.stringify(raw.intent).length <= 2048) {
    notice.intent = raw.intent as Record<string, unknown>;
  }

  if (typeof raw.at === 'number' && Number.isFinite(raw.at)) {
    notice.at = Math.floor(raw.at);
  }

  return notice;
}

export interface RecentEntry {
  title: string;
  sub?: string;
  intent?: Record<string, unknown>;
}

export function cleanRecent(value: unknown): RecentEntry | null {
  if (!value || typeof value !== 'object') return null;

  const raw = value as Record<string, unknown>;
  const title = text(raw.title, 60);

  if (!title) return null;

  const entry: RecentEntry = { title };
  const sub = text(raw.sub, 60);

  if (sub) {
    entry.sub = sub;
  }

  if (raw.intent && typeof raw.intent === 'object' && !Array.isArray(raw.intent) && JSON.stringify(raw.intent).length <= 2048) {
    entry.intent = raw.intent as Record<string, unknown>;
  }

  return entry;
}

export function isAppMessage(data: unknown, token: string): data is { __os: 1; type: AppType; token?: string } & Record<string, unknown> {
  if (!data || typeof data !== 'object') return false;

  const message = data as Record<string, unknown>;

  if (message.__os !== 1 || typeof message.type !== 'string' || !(APP_TYPES as readonly string[]).includes(message.type)) return false;
  if (message.type === 'hello') return true;

  return typeof message.token === 'string' && message.token === token;
}

export function originOf(url: string, base?: string): string {
  try {
    const origin = new URL(url, base).origin;

    return origin && origin !== 'null' ? origin : '';
  } catch {
    return '';
  }
}
