import type { Result } from './nui';
import type { Boot, Counts, Kind, KindInfo, Level } from './types';

export interface DialogField {
  key: string;
  type: 'text' | 'password' | 'number' | 'select' | 'checkbox';
  label: string;
  value?: unknown;
  options?: { value: string | number; label: string }[];
  min?: number;
  max?: number;
  help?: string;
  required?: boolean;
  placeholder?: string;
}

export interface Dialog {
  title: string;
  message?: string;
  fields?: DialogField[];
  confirm: string;
  danger?: boolean;
  resolve: (values: Record<string, unknown> | null) => void;
}

export interface Toast {
  id: number;
  text: string;
  kind: 'success' | 'error' | 'inform' | 'warning';
  unfolded?: boolean;
  out?: boolean;
  fold?: { height: string; width: string };
}

export const app = $state({
  ready: false,
  visible: false,
  locale: {} as Record<string, string>,
  command: 'evdevices',
  level: 'admin' as Level,
  focus: null as number | null,
  openTick: 0,
  boot: null as Boot | null,
  skew: 0,
  kinds: [] as KindInfo[],
  counts: null as Counts | null,
  waiting: 0,
  dialog: null as Dialog | null,
  toasts: [] as Toast[],
  placing: false,
  dirty: false,
  ended: '',
  drawerClose: null as (() => void) | null,
  popoverClose: null as (() => void) | null,
});

let toastId = 0;

const TOAST_LIMIT = 4;
const TOAST_FOLD_MS = 400;

function foldToast(id: number) {
  const entry = app.toasts.find((item) => item.id === id);

  if (!entry || entry.out) {
    return;
  }

  entry.out = true;

  setTimeout(() => {
    app.toasts = app.toasts.filter((item) => item.id !== id);
  }, TOAST_FOLD_MS);
}

export function clearToasts() {
  app.toasts = [];
}

export function toast(text: string, kind: Toast['kind'] = 'inform') {
  const id = ++toastId;

  app.toasts = [...app.toasts, { id, text, kind }];

  const shown = app.toasts.filter((entry) => !entry.out);

  if (shown.length > TOAST_LIMIT) {
    foldToast(shown[0].id);
  }

  setTimeout(() => foldToast(id), kind === 'error' ? 6500 : 4500);
}

export function ask(dialog: Omit<Dialog, 'resolve'>): Promise<Record<string, unknown> | null> {
  return new Promise((resolve) => {
    app.dialog?.resolve(null);
    app.dialog = { ...dialog, resolve };
  });
}

export function format(text: string, args: unknown[]): string {
  let index = 0;

  return text.replace(/%(%|-?\d*(?:\.(\d+))?([sdf]))/g, (_match, spec: string, precision?: string, type?: string) => {
    if (spec === '%') {
      return '%';
    }

    const value = args[index++];

    if (type === 'd') {
      return String(Math.trunc(Number(value) || 0));
    }

    if (type === 'f') {
      return (Number(value) || 0).toFixed(precision !== undefined ? Number(precision) : 6);
    }

    return value === undefined || value === null ? '' : String(value);
  });
}

export function t(key: string, ...args: unknown[]): string {
  const text = app.locale[key];

  if (typeof text !== 'string') {
    return key;
  }

  return format(text, args);
}

export function has(key: string) {
  return typeof app.locale[key] === 'string';
}

export function plural(key: string, count: number, ...args: unknown[]) {
  return count === 1 && has(key + '_one') ? t(key + '_one', ...args) : t(key, count, ...args);
}

export function filled(value: unknown) {
  return value !== null && value !== undefined && value !== '' && Number.isFinite(Number(value));
}

export function number(value: unknown, digits = 0) {
  const parsed = Number(value) || 0;

  return parsed.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function serverNow() {
  return Date.now() / 1000 + app.skew;
}

export function ago(seconds: unknown) {
  const at = Number(seconds);

  if (!at) {
    return t('ui_never');
  }

  const minutes = Math.max(0, Math.floor((serverNow() - at) / 60));

  if (minutes < 1) {
    return t('ui_ago_now');
  }

  if (minutes < 60) {
    return t('ui_ago_minutes', minutes);
  }

  if (minutes < 60 * 24) {
    return t('ui_ago_hours', Math.floor(minutes / 60));
  }

  return plural('ui_ago_days', Math.floor(minutes / (60 * 24)));
}

export function stamp(seconds: unknown) {
  const at = Number(seconds);

  if (!at) {
    return '-';
  }

  const date = new Date(at * 1000);
  const pad = (value: number) => String(value).padStart(2, '0');

  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function kindName(kind: string | undefined) {
  return kind ? t('kind_' + kind) : '-';
}

export function spaceText(space: string | undefined) {
  const match = /^([bp])(\d+)$/.exec(space ?? '');

  if (!match) {
    return space ?? '-';
  }

  const value = Number(match[2]);

  if (match[1] === 'p') {
    return t('space_home', value);
  }

  return value === 0 ? t('space_world') : t('space_bucket', value);
}

export function coord(value: unknown) {
  return (Number(value) || 0).toFixed(2);
}

export function deviceName(device: { label?: string; kind: string; id: number }) {
  return device.label ? device.label : t('ui_device_unnamed', kindName(device.kind), device.id);
}

export function appLabel(id: string) {
  const known = labels.get(id);

  if (known) {
    return known;
  }

  const words = id.replace(/_/g, ' ');

  return words.charAt(0).toUpperCase() + words.slice(1);
}

const labels = new Map<string, string>();

export function rememberApps(list: { id: string; label: string }[]) {
  for (const entry of list) {
    labels.set(entry.id, entry.label);
  }
}

export function reasonText(result: Result | { reason?: string; data?: any }) {
  const reason = String(result.reason ?? 'unknown');
  const key = 'reason_' + reason;

  if (!has(key)) {
    return t('reason_generic', reason);
  }

  const text = app.locale[key];

  return /%[-\d.]*[sdf]/.test(text) ? text.replace(/%[-\d.]*[sdf]/g, '?') : text;
}

export function where(result: Result) {
  const data = result.data ?? {};
  const parts: string[] = [];

  if (typeof data.rule === 'number') {
    parts.push(t('ui_problem_rule', data.rule));
  }

  if (typeof data.app === 'string') {
    parts.push(t('ui_problem_app', appLabel(data.app)));
  }

  if (typeof data.zone === 'number') {
    parts.push(t('ui_problem_zone', data.zone));
  }

  return parts.length ? reasonText(result) + ' (' + parts.join(', ') + ')' : reasonText(result);
}

export function explain(result: Result) {
  toast(where(result), 'error');
}

export function done(result: Result, message?: string) {
  if (!result.ok) {
    explain(result);

    return false;
  }

  if (message) {
    toast(message, 'success');
  }

  return true;
}

export function same(a: unknown, b: unknown) {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function clone<T>(value: T): T {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

export function record<T>(value: unknown): Record<string, T> {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, T>) : {};
}

export function list<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export const KIND_ICONS: Record<string, string> = {
  laptop: 'laptop',
  pc: 'monitor',
  terminal: 'kiosk',
  tablet: 'tablet',
};

export const OS_KINDS: Kind[] = ['laptop', 'pc', 'tablet'];
