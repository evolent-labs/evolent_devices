import { storeInfo, type Ability, type Category } from '../lib/appstore.ts';
import type { Clock } from '../lib/clock.ts';
import { iconOf } from '../lib/icon.ts';

export { cleanClock, initials, untilNextMinute, wallParts, type Clock, type WallParts } from '../lib/clock.ts';

export type Phase = 'off' | 'boot' | 'lock' | 'login' | 'desktop';
export type Popover = '' | 'launcher' | 'notifications' | 'menu';

export interface Layout {
  width: number;
  height: number;
  taskbar: number;
}

export interface Size {
  width: number;
  height: number;
}

export interface AppInfo {
  id: string;
  label: string;
  icon?: { path: string; color: string };
  canvas: Size;
  window?: Size;
  network: boolean;
  watch: 'cover' | 'state';
  version: string;
  description?: string;
  size?: number;
  category?: Category;
  about?: string;
  can?: Ability[];
  pictures?: string[];
  cover?: string;
  accent?: string;
  publisher?: string;
  kinds?: string[];
}

export interface OnlyApp {
  id: string;
  label: string;
  icon?: { path: string; color: string };
  reason: string;
}

export type OnlyClose = 'close' | 'leave' | 'error';

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
  scale: number;
}

export const TITLE_BAR = 44;
export const RECENT_MAX = 6;
export const NOTICE_MAX = 50;
export const MAX_BARS = 4;

const LAYOUTS: Record<string, Layout> = {
  pc: { width: 1920, height: 1080, taskbar: 80 },
  laptop: { width: 1440, height: 900, taskbar: 80 },
};

const PHASES: Phase[] = ['off', 'boot', 'lock', 'login', 'desktop'];
const POPOVERS: Record<string, Popover> = { l: 'launcher', n: 'notifications', m: 'menu' };
const ID = /^[a-z][a-z0-9_]{1,31}$/;
const REASON = /^[a-z][a-z0-9_]{0,47}$/;
const MARGIN = 24;
const CASCADE = 28;
const EDGE = 120;
const MENU_ROW = 40;
const MENU_WIDTH = 264;
const MENU_GAP = 6;

export function layoutOf(kind: string): Layout {
  return LAYOUTS[kind] ?? LAYOUTS.pc;
}

const text = (value: unknown, max: number) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

const size = (value: any, min: number, max: number): Size | undefined => {
  const width = Number(value?.width);
  const height = Number(value?.height);

  return width >= min && height >= min && width <= max && height <= max
    ? { width: Math.round(width), height: Math.round(height) }
    : undefined;
};

export function cleanOnly(value: unknown): OnlyApp | null {
  const raw = value && typeof value === 'object' ? (value as Record<string, any>) : null;

  if (!raw || !ID.test(raw.id)) return null;

  return {
    id: raw.id,
    label: text(raw.label, 32),
    icon: iconOf(raw.icon),
    reason: typeof raw.reason === 'string' && REASON.test(raw.reason) ? raw.reason : '',
  };
}

export function onlyAllows(only: OnlyApp | null, id: string) {
  return !only || only.id === id;
}

export function onlyClose(only: OnlyApp | null, id: string, reason: string, byUser: boolean): OnlyClose {
  if (!only || only.id !== id) return 'close';

  if (byUser || !reason || reason === 'app_closed') return 'leave';

  return 'error';
}

export function cleanApps(value: unknown): AppInfo[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const seen = new Set<string>();
  const list: AppInfo[] = [];

  for (const raw of value) {
    if (!raw || typeof raw !== 'object' || !ID.test(raw.id) || seen.has(raw.id)) continue;

    seen.add(raw.id);

    const icon = iconOf(raw.icon);

    list.push({
      id: raw.id,
      label: text(raw.label, 32) || raw.id,
      icon,
      canvas: size(raw.canvas, 120, 3840) ?? { width: 960, height: 600 },
      window: size(raw.window, 160, 3840),
      network: raw.network !== false,
      watch: raw.watch === 'state' ? 'state' : 'cover',
      version: text(raw.version, 32),
      description: text(raw.description, 120),
      size: Number(raw.size) > 0 ? Math.round(Number(raw.size)) : undefined,
      ...storeInfo(raw),
    });
  }

  return list;
}

export function windowBox(layout: Layout, app: AppInfo, open: number): Box {
  let width: number;
  let height: number;
  let scale: number;
  const freeWidth = layout.width - MARGIN * 2;
  const freeHeight = layout.height - layout.taskbar - MARGIN * 2;

  if (app.window) {
    width = Math.min(app.window.width, layout.width);
    height = Math.min(app.window.height, layout.height - layout.taskbar);
    scale = (width - 2) / app.canvas.width;
  } else {
    scale = Math.min(1, (freeWidth - 2) / app.canvas.width, (freeHeight - TITLE_BAR - 2) / app.canvas.height);
    width = Math.round(app.canvas.width * scale) + 2;
    height = Math.round(app.canvas.height * scale) + TITLE_BAR + 2;
  }

  const shift = (open % 4) * CASCADE;
  const x = Math.round((layout.width - width) / 2) + shift;
  const y = Math.max(0, Math.round((layout.height - layout.taskbar - height) / 2)) + shift;

  return { ...clampWindow(layout, { width, height }, x, y), width, height, scale: Math.round(scale * 10000) / 10000 };
}

export function maxBox(layout: Layout, full = false) {
  return { x: 0, y: 0, width: layout.width, height: layout.height - (full ? 0 : layout.taskbar) };
}

export function fillFrame(area: Size, scale: number): Size {
  const zoom = Number.isFinite(scale) && scale > 0 ? scale : 1;

  return { width: Math.ceil(area.width / zoom), height: Math.ceil(area.height / zoom) };
}

export function maxFrame(layout: Layout, scale: number, full = false): Size {
  return fillFrame({ width: layout.width, height: layout.height - (full ? 0 : layout.taskbar) - TITLE_BAR }, scale);
}

export function windowFrame(box: Size, scale: number, canvas: Size): Size {
  const fill = fillFrame({ width: box.width - 2, height: box.height - TITLE_BAR - 2 }, scale);

  return { width: Math.max(canvas.width, fill.width), height: Math.max(canvas.height, fill.height) };
}

export function detailBlur(page: Size, w: unknown, h: unknown): number | null {
  const shownW = Math.round(Number(w));
  const shownH = Math.round(Number(h));

  if (!(shownW >= 16 && shownH >= 16 && shownW <= page.width && shownH <= page.height)) return null;

  const ratio = Math.min(page.width / shownW, page.height / shownH);

  return ratio > 1 ? Math.round(50 * (ratio - 1)) / 100 : 0;
}

export function grabPoint(box: Size, share: number, pointer: { x: number; y: number }, grab: number) {
  return {
    x: pointer.x - Math.max(0, Math.min(1, share)) * box.width,
    y: pointer.y - Math.max(0, Math.min(TITLE_BAR, grab)),
  };
}

export function clampWindow(layout: Layout, box: Size, x: number, y: number) {
  return {
    x: Math.round(Math.min(layout.width - EDGE, Math.max(EDGE - box.width, x))),
    y: Math.round(Math.min(layout.height - layout.taskbar - TITLE_BAR, Math.max(0, y))),
  };
}

export function menuSpot(layout: Layout, x: number, y: number, rows: number) {
  const height = rows * MENU_ROW + 14;

  return {
    x: Math.round(Math.max(0, Math.min(layout.width - MENU_WIDTH - MENU_GAP, x))),
    y: Math.round(Math.max(0, Math.min(layout.height - layout.taskbar - MENU_GAP - height, y))),
  };
}

export function raise(order: string[], id: string) {
  return [...order.filter((entry) => entry !== id), id];
}

export function topOf(order: string[], hidden: (id: string) => boolean) {
  for (let index = order.length - 1; index >= 0; index--) {
    if (!hidden(order[index])) {
      return order[index];
    }
  }

  return null;
}

export function clockBase(clock: Clock | null, nowMs: number, perfNow: number, browserOffsetMinutes: number) {
  if (clock) {
    return (clock.now + clock.offset) * 1000 - perfNow;
  }

  return nowMs - browserOffsetMinutes * 60000 - perfNow;
}

export interface Signal {
  bars: number;
  wired: boolean;
}

export function cleanSignal(value: unknown, fallback: Signal = { bars: 0, wired: false }): Signal {
  if (!value || typeof value !== 'object') {
    return fallback;
  }

  const raw = value as Record<string, unknown>;
  const bars = Number(raw.bars);

  return {
    bars: Number.isInteger(bars) ? Math.max(0, Math.min(MAX_BARS, bars)) : fallback.bars,
    wired: raw.wired === true,
  };
}

export function online(signal: Signal, wifi: boolean) {
  return signal.wired || (wifi && signal.bars > 0);
}

export interface WinView {
  id: string;
  x: number;
  y: number;
  min: boolean;
  max?: boolean;
}

export interface ShellState {
  phase: Phase;
  waiting: boolean;
  wins: WinView[];
  popover: Popover;
  menu: { x: number; y: number; app: string } | null;
  selected: string;
  notices: number;
  recent: number;
  toggles: { wifi: boolean; sound: boolean; dnd: boolean };
  signal: Signal;
  icons: number;
  error?: string;
}

const whole = (value: number) => Math.round(Math.max(-9999, Math.min(9999, value)));

export function encodeShell(state: ShellState): Record<string, string | number | boolean> {
  const { wifi, sound, dnd } = state.toggles;

  return {
    ph: state.phase,
    wt: state.phase === 'boot' && state.waiting,
    ws: state.wins
      .filter((win) => ID.test(win.id))
      .slice(-4)
      .map((win) => `${win.id}:${whole(win.x)},${whole(win.y)},${(win.min ? 1 : 0) + (win.max ? 2 : 0)}`)
      .join(';'),
    po: Object.keys(POPOVERS).find((key) => POPOVERS[key] === state.popover) ?? '',
    mu: state.menu
      ? `${whole(state.menu.x)},${whole(state.menu.y)},${ID.test(state.menu.app) ? state.menu.app : ''}`
      : '',
    se: ID.test(state.selected) ? state.selected : '',
    nt: Math.max(0, Math.min(99, Math.floor(state.notices))),
    rc: Math.max(0, Math.min(RECENT_MAX, Math.floor(state.recent))),
    tg: [wifi, sound, dnd].map((on) => (on ? '1' : '0')).join(''),
    sg: state.signal.wired ? 9 : Math.max(0, Math.min(MAX_BARS, Math.floor(state.signal.bars))),
    ic: Math.max(0, Math.min(48, Math.floor(state.icons))),
    oe: state.error && REASON.test(state.error) ? state.error : '',
  };
}

function count(value: unknown, max: number) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.min(max, Math.floor(value))) : 0;
}

export function decodeShell(raw: unknown): ShellState {
  const state = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  const wins: WinView[] = [];

  if (typeof state.ws === 'string' && state.ws) {
    for (const part of state.ws.split(';').slice(0, 4)) {
      const match = /^([a-z][a-z0-9_]{1,31}):(-?\d{1,4}),(-?\d{1,4}),([0-3])$/.exec(part);

      if (match) {
        const flags = Number(match[4]);
        const view: WinView = { id: match[1], x: Number(match[2]), y: Number(match[3]), min: (flags & 1) === 1 };

        if (flags & 2) {
          view.max = true;
        }

        wins.push(view);
      }
    }
  }

  const menu = typeof state.mu === 'string' ? /^(-?\d{1,4}),(-?\d{1,4}),([a-z0-9_]*)$/.exec(state.mu) : null;
  const flags = typeof state.tg === 'string' && /^[01]{3}$/.test(state.tg) ? state.tg : '110';
  const signal = Number(state.sg);

  return {
    phase: PHASES.includes(state.ph as Phase) ? (state.ph as Phase) : 'lock',
    waiting: state.ph === 'boot' && state.wt === true,
    wins,
    popover: POPOVERS[String(state.po)] ?? '',
    menu: menu ? { x: Number(menu[1]), y: Number(menu[2]), app: menu[3] } : null,
    selected: typeof state.se === 'string' && ID.test(state.se) ? state.se : '',
    notices: count(state.nt, 99),
    recent: count(state.rc, RECENT_MAX),
    toggles: { wifi: flags[0] === '1', sound: flags[1] === '1', dnd: flags[2] === '1' },
    signal: signal === 9 ? { bars: MAX_BARS, wired: true } : { bars: count(signal, MAX_BARS), wired: false },
    icons: count(state.ic, 48),
    error: typeof state.oe === 'string' && REASON.test(state.oe) ? state.oe : '',
  };
}

export interface OsNotice {
  id: string;
  app: string;
  title: string;
  body: string;
  action: string;
  intent: Record<string, unknown> | null;
  at: number;
  key: string;
  label: string;
  icon?: { path: string; color: string };
  quiet: boolean;
  silent: boolean;
}

export interface Alerts {
  popup: boolean;
  sound: boolean;
}

export function cleanAlerts(value: unknown): Alerts {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};

  return { popup: raw.popup !== false, sound: raw.sound !== false };
}

export function cleanNotices(value: unknown, now: number): OsNotice[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const list: OsNotice[] = [];

  for (const raw of value) {
    const notice = cleanNotice(raw, now);

    if (notice) {
      list.push(notice);
    }
  }

  return list.slice(0, NOTICE_MAX);
}

export function cleanNotice(raw: any, now: number, app?: string): OsNotice | null {
  if (!raw || typeof raw !== 'object') return null;

  const owner = app ?? raw.app;
  const title = text(raw.title, 80);

  if (!ID.test(owner) || !title) return null;

  const id = text(typeof raw.id === 'number' ? String(raw.id) : raw.id, 64) || owner + ':' + title;
  const at = Number(raw.at);

  const key = typeof raw.key === 'string' && /^[nm]\d{1,12}$/.test(raw.key) ? raw.key : '';

  return {
    id,
    app: owner,
    title,
    body: text(raw.body, 240),
    action: text(raw.action, 32),
    intent: raw.intent && typeof raw.intent === 'object' && !Array.isArray(raw.intent) ? raw.intent : null,
    at: Number.isFinite(at) && at > 0 ? at * 1000 : now,
    key,
    label: text(raw.label, 32),
    icon: iconOf(raw.icon),
    quiet: raw.quiet === true,
    silent: raw.silent === true,
  };
}

export function mergeNotices(list: OsNotice[], value: unknown, now: number) {
  let merged = list;

  for (const notice of cleanNotices(value, now).reverse()) {
    merged = addNotice(merged, notice);
  }

  return merged;
}

export function addNotice(list: OsNotice[], notice: OsNotice) {
  return [notice, ...list.filter((entry) => entry.id !== notice.id)].slice(0, NOTICE_MAX);
}

export interface OsRecent {
  app: string;
  title: string;
  sub: string;
  intent: Record<string, unknown> | null;
  at: number;
}

export function pushRecent(list: OsRecent[], entry: OsRecent) {
  return [entry, ...list.filter((item) => item.app !== entry.app || item.title !== entry.title)].slice(0, RECENT_MAX);
}
