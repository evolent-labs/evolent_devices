import { tick } from 'svelte';
import { createHost } from '$lib/apphost';
import { cleanIds, isFixed, sizeOf, type StoreApp } from '$lib/appstore';
import { reasonText, t } from '$lib/state.svelte';
import * as game from './bridge';
import { builtinApp, builtinApps, builtinStore, isBuiltin } from './builtin';
import { page, watching } from './params';
import {
  addNotice,
  clampWindow,
  cleanAlerts,
  cleanApps,
  cleanClock,
  cleanNotice,
  clockBase,
  initials,
  layoutOf,
  MAX_BARS,
  maxBox,
  onlyAllows,
  onlyClose,
  online,
  pushRecent,
  raise,
  topOf,
  untilNextMinute,
  windowBox,
  type Alerts,
  type AppInfo,
  type OnlyApp,
  type OsNotice,
  type OsRecent,
  type Phase,
  type Signal,
} from './shell';
import { cleanPrefs, cleanSystem, DEFAULT_PREFS, type Prefs } from './system';

export type WinState = 'asking' | 'loading' | 'ready' | 'failed' | 'nosignal' | 'update' | 'refused' | 'cover' | 'state';

export interface Win {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  scale: number;
  min: boolean;
  max: boolean;
  snap: boolean;
  closing: boolean;
  state: WinState;
  reason: string;
  url: string;
  token: string;
  context: Record<string, unknown>;
  intent: Record<string, unknown> | null;
  load: number;
}

export interface Toast {
  id: number;
  text: string;
  bad: boolean;
  out: boolean;
}

export type Banner = OsNotice & { out: boolean };

export const layout = layoutOf(page.kind);
export const MAX_WINDOWS = 4;

const BOOT_MS = 1900;
const OPEN_MS = 480;
const CLOSE_MS = 380;
const MINIMIZE_MS = 340;
const POP_OUT_MS = 150;
const MAX_MS = 260;
const TOAST_MS = 2400;
const TOAST_FOLD_MS = 2000;
const HELLO_MS = 8000;
const BANNER_MS = 5200;
const BANNER_OUT_MS = 260;

export const os = $state({
  phase: 'off' as Phase,
  waiting: false,
  scale: 1,
  user: null as { name: string; initials: string } | null,
  device: '',
  apps: [] as AppInfo[],
  installed: null as string[] | null,
  wins: [] as Win[],
  order: [] as string[],
  launcher: false,
  launcherOut: false,
  notif: false,
  notifOut: false,
  menu: null as { x: number; y: number; app: string } | null,
  soundPop: null as { x: number } | null,
  secret: false,
  selected: '',
  query: '',
  toggles: { wifi: true, sound: true, dnd: false },
  notices: [] as OsNotice[],
  recent: [] as OsRecent[],
  badges: {} as Record<string, number>,
  states: {} as Record<string, Record<string, string | number | boolean>>,
  signal: { bars: MAX_BARS, wired: page.kind !== 'laptop' } as Signal,
  limit: MAX_WINDOWS,
  lockMinutes: 0,
  brightness: 100,
  lockName: '',
  toasts: [] as Toast[],
  wall: 0,
  remote: { notices: 0, recent: 0, icons: 0 },
  pointer: null as { u: number; v: number } | null,
  live: {} as Record<string, number>,
  maxed: {} as Record<string, boolean>,
  system: cleanSystem(null),
  prefs: { ...DEFAULT_PREFS } as Prefs,
  only: null as OnlyApp | null,
  alerts: cleanAlerts(null) as Alerts,
  banner: null as Banner | null,
});

let root: HTMLElement | null = null;
let base = clockBase(null, Date.now(), performance.now(), new Date().getTimezoneOffset());
let minuteTimer: ReturnType<typeof setTimeout> | null = null;
let clockOn = false;
let bootTimer: ReturnType<typeof setTimeout> | null = null;
let popTimer: ReturnType<typeof setTimeout> | null = null;
let toastTimers: ReturnType<typeof setTimeout>[] = [];
let bannerTimers: ReturnType<typeof setTimeout>[] = [];
let toastId = 0;
let loads = 0;
const helloTimers = new Map<string, ReturnType<typeof setTimeout>>();

const builtinLabel = (id: string) => t('os_app_' + id);

function onlyInfo(id: string): AppInfo | null {
  const only = os.only;

  if (!only || only.id !== id) return null;

  if (isBuiltin(id)) {
    return builtinApp(id, page.kind, builtinLabel(id));
  }

  return {
    id,
    label: only.label || id,
    icon: only.icon,
    canvas: { width: 960, height: 600 },
    network: false,
    watch: 'cover',
    version: '',
  };
}

export const appOf = (id: string) => os.apps.find((entry) => entry.id === id)
  ?? (watching && isBuiltin(id) ? builtinApp(id, page.kind, builtinLabel(id)) : null)
  ?? onlyInfo(id);

export const isOnly = (id: string) => os.only?.id === id;
export const isInstalled = (id: string) => os.installed === null || os.installed.includes(id) || isOnly(id);
export const homeApps = () => os.apps.filter((entry) => isInstalled(entry.id));
export const winOf = (id: string) => os.wins.find((entry) => entry.id === id) ?? null;
export const isOnline = () => online(os.signal, os.toggles.wifi);

export function setRoot(element: HTMLElement | null) {
  root = element;
}

export function setClock(value: unknown) {
  const clock = cleanClock(value);

  if (!clock) return;

  base = clockBase(clock, Date.now(), performance.now(), 0);

  if (clockOn) {
    scheduleMinute();
  }
}

function scheduleMinute() {
  if (minuteTimer) {
    clearTimeout(minuteTimer);
  }

  os.wall = base + performance.now();
  minuteTimer = setTimeout(scheduleMinute, os.prefs.seconds ? 1000 - (os.wall % 1000) + 5 : untilNextMinute(os.wall) + 20);
}

export function startClock() {
  clockOn = true;
  scheduleMinute();

  return () => {
    clockOn = false;

    if (minuteTimer) {
      clearTimeout(minuteTimer);
    }

    minuteTimer = null;
  };
}

export function chime(name: 'notice') {
  if (!os.prefs.sound) return;

  if (!watching && os.prefs.volume > 0) {
    game.playSound(name);
  }
}

let prefsTimer: ReturnType<typeof setTimeout> | null = null;
const PREFS_MS = 300;

export function applyPrefs(value: unknown) {
  const prefs = cleanPrefs(value);

  const ticking = os.prefs.seconds;

  os.prefs = prefs;
  os.toggles = { ...os.toggles, sound: prefs.volume > 0, dnd: prefs.dnd };

  if (ticking !== prefs.seconds && minuteTimer) scheduleMinute();
}

export function setPrefs(patch: Partial<Prefs>) {
  if (watching) return;

  applyPrefs({ ...os.prefs, ...patch });

  if (prefsTimer) {
    clearTimeout(prefsTimer);
  }

  prefsTimer = setTimeout(() => {
    prefsTimer = null;
    game.savePrefs({ ...os.prefs });
  }, PREFS_MS);
}

export function publish(id: string, state: Record<string, string | number | boolean>) {
  if (!watching) {
    os.states[id] = state;
  }
}

export function say(text: string, bad = false) {
  for (const timer of toastTimers) {
    clearTimeout(timer);
  }

  const id = ++toastId;

  os.toasts = [{ id, text, bad, out: false }];

  toastTimers = [
    setTimeout(() => {
      if (os.toasts[0]?.id === id) {
        os.toasts[0].out = true;
      }
    }, TOAST_FOLD_MS),
    setTimeout(() => {
      if (os.toasts[0]?.id === id) {
        os.toasts = [];
      }
    }, TOAST_MS),
  ];
}

export function setPhase(phase: Phase) {
  if (bootTimer) {
    clearTimeout(bootTimer);
  }

  bootTimer = null;

  const hidden = phase !== 'desktop' && os.phase === 'desktop';

  os.phase = phase;
  os.launcher = os.notif = os.launcherOut = os.notifOut = false;
  os.menu = null;

  if (phase === 'boot' && !watching) {
    bootTimer = setTimeout(() => setPhase('lock'), BOOT_MS);
  }

  if (hidden || phase === 'desktop') {
    visibility();
  }
}

const lastShown = new Map<string, boolean>();

function visibility() {
  for (const win of os.wins) {
    const covered = appOf(win.id)?.network === true && !isOnline();
    const shown = os.phase === 'desktop' && !win.min && !win.closing && win.state === 'ready' && !covered;

    if (lastShown.get(win.id) === shown || !host.seen(win.id)) continue;

    lastShown.set(win.id, shown);
    host.send(win.id, 'os:visibility', { visible: shown });

    if (!watching) {
      game.appVisible(win.id, shown);
    }
  }
}

function toCanvas(rect: DOMRect) {
  if (!root) return null;

  const box = root.getBoundingClientRect();

  return {
    x: (rect.left + rect.width / 2 - box.left) / os.scale,
    y: (rect.top + rect.height / 2 - box.top) / os.scale,
  };
}

export function originOf(element: Element | null | undefined) {
  return element ? toCanvas(element.getBoundingClientRect()) : null;
}

function centreOf(selector: string) {
  const node = root?.querySelector(selector);

  if (!node) return null;

  const rect = node.getBoundingClientRect();

  return rect.width > 0 ? toCanvas(rect) : null;
}

const fallback = () => ({ x: 56, y: layout.height - 40 });
const windowElement = (id: string) => root?.querySelector<HTMLElement>(`[data-win="${id}"]`) ?? null;

export const shownBox = (win: Win) => (isOnly(win.id) ? maxBox(layout, true) : win.max ? maxBox(layout) : win);

function offset(point: { x: number; y: number }, win: Win) {
  const box = shownBox(win);

  return { dx: point.x - (box.x + box.width / 2), dy: point.y - (box.y + box.height / 2) };
}

function playIn(id: string, from: { x: number; y: number } | null) {
  const element = windowElement(id);
  const win = winOf(id);

  if (!element || !win || typeof element.animate !== 'function') return;

  const { dx, dy } = offset(from ?? fallback(), win);

  element.animate(
    [
      { transform: `translate(${dx}px,${dy}px) scale(.08)`, opacity: 0 },
      { opacity: 1, offset: 0.35 },
      { transform: 'none', opacity: 1 },
    ],
    { duration: OPEN_MS, easing: 'cubic-bezier(.16,1,.3,1)', fill: 'backwards' },
  );
}

export function closePopovers(after?: () => void) {
  if (popTimer) {
    clearTimeout(popTimer);
  }

  popTimer = null;
  os.menu = null;
  os.soundPop = null;

  if (!os.launcher && !os.notif) {
    after?.();

    return;
  }

  os.launcherOut = os.launcher;
  os.notifOut = os.notif;

  popTimer = setTimeout(() => {
    popTimer = null;
    os.launcher = os.notif = os.launcherOut = os.notifOut = false;
    after?.();
  }, POP_OUT_MS);
}

export function toggleLauncher() {
  if (os.launcher) {
    return closePopovers();
  }

  closePopovers(() => {
    os.query = '';
    os.launcher = true;
  });
}

export function toggleNotifications() {
  if (os.notif) {
    return closePopovers();
  }

  closeBanner();
  closePopovers(() => (os.notif = true));
}

export function topWindow() {
  return topOf(os.order, (id) => {
    const win = winOf(id);

    return !win || win.min || win.closing;
  });
}

export function focusWindow(id: string) {
  if (os.order[os.order.length - 1] !== id) {
    os.order = raise(os.order, id);
  }
}

function stopHello(id: string) {
  const timer = helloTimers.get(id);

  if (timer) {
    clearTimeout(timer);
  }

  helloTimers.delete(id);
}

export function watchHello(id: string, load: number) {
  stopHello(id);

  helloTimers.set(
    id,
    setTimeout(() => {
      helloTimers.delete(id);

      const win = winOf(id);

      if (win && win.load === load && win.state === 'ready' && !host.seen(id)) {
        win.state = 'failed';
        win.reason = 'app_no_hello';
      }
    }, HELLO_MS),
  );
}

function ask(win: Win) {
  const app = appOf(win.id);

  if (!app) return;

  if (isBuiltin(win.id)) {
    win.state = 'ready';
    win.load = ++loads;

    return;
  }

  if (app.network && !isOnline()) {
    win.state = 'nosignal';

    return;
  }

  win.state = 'asking';
  win.load = ++loads;
  game.openApp(win.id, win.intent);
}

export function openApp(id: string, from: { x: number; y: number } | null = null, intent: Record<string, unknown> | null = null) {
  closePopovers();

  if (!onlyAllows(os.only, id)) {
    say(t('reason_single_app'), true);

    return;
  }

  const app = appOf(id);

  if (!app || watching) return;

  const existing = winOf(id);

  if (existing && !existing.closing) {
    if (existing.min) {
      restoreWindow(id, from);
    }

    focusWindow(id);

    if (intent) {
      if (isBuiltin(id)) existing.intent = intent;
      else if (existing.state === 'ready') host.send(id, 'os:intent', { intent });
      else existing.intent = intent;
    }

    return;
  }

  if (os.wins.filter((win) => !win.closing).length >= os.limit) {
    say(t('os_window_limit', os.limit), true);

    return;
  }

  const box = windowBox(layout, app, os.wins.length);

  const win: Win = {
    id,
    ...box,
    min: false,
    max: os.maxed[id] === true,
    snap: false,
    closing: false,
    state: 'asking',
    reason: '',
    url: '',
    token: '',
    context: {},
    intent,
    load: 0,
  };

  os.wins = [...os.wins.filter((entry) => entry.id !== id), win];
  focusWindow(id);
  pushOpened(id);

  if (!os.only) {
    tick().then(() => playIn(id, from));
  }

  ask(winOf(id)!);
}

export function markError(win: Win, reason: string) {
  stopHello(win.id);
  host.detach(win.id);
  lastShown.delete(win.id);
  delete os.live[win.id];
  win.state = reason === 'no_signal' ? 'nosignal' : 'refused';
  win.reason = reason;
  win.url = '';
  win.token = '';
}

export function openOnly() {
  const only = os.only;

  if (!only || watching) return;

  const existing = winOf(only.id);

  if (existing && !existing.closing) {
    focusWindow(only.id);

    return;
  }

  if (!only.reason) {
    openApp(only.id);

    return;
  }

  const app = appOf(only.id);

  if (!app) return;

  const win: Win = {
    id: only.id,
    ...windowBox(layout, app, 0),
    min: false,
    max: false,
    snap: false,
    closing: false,
    state: 'refused',
    reason: only.reason,
    url: '',
    token: '',
    context: {},
    intent: null,
    load: 0,
  };

  os.wins = [win];
  os.order = [only.id];
}

export function onlyError(win: Win | null) {
  if (!win || !isOnly(win.id) || win.closing) return '';

  if (win.state === 'nosignal' || (appOf(win.id)?.network === true && !isOnline())) return 'no_signal';

  if (win.state === 'refused' || win.state === 'failed' || win.state === 'update') {
    return win.reason || (win.state === 'update' ? 'app_update' : 'app_failed');
  }

  return '';
}

function pushOpened(id: string) {
  const app = appOf(id);

  if (app) {
    os.recent = pushRecent(os.recent, { app: id, title: app.label, sub: '', intent: null, at: Date.now() });
  }
}

export function retry(id: string) {
  const win = winOf(id);

  if (!win) return;

  host.detach(id);
  lastShown.delete(id);
  win.url = '';
  ask(win);
}

export function appOpened(message: any) {
  const id = String(message.app ?? '');
  const app = appOf(id);

  if (!app) return;

  let win = winOf(id);

  if (!win || win.closing) {
    if (os.wins.filter((entry) => !entry.closing).length >= os.limit) return;

    const box = windowBox(layout, app, os.wins.length);

    win = {
      id,
      ...box,
      min: false,
      max: os.maxed[id] === true,
      snap: false,
      closing: false,
      state: 'asking',
      reason: '',
      url: '',
      token: '',
      context: {},
      intent: null,
      load: ++loads,
    };

    os.wins = [...os.wins.filter((entry) => entry.id !== id), win];
    focusWindow(id);
    tick().then(() => playIn(id, null));
    win = winOf(id)!;
  }

  if (typeof message.token !== 'string' || typeof message.url !== 'string') return;

  win.token = message.token;
  win.url = message.url;

  win.context = message.context && typeof message.context === 'object' && !Array.isArray(message.context)
    ? message.context
    : {};

  if (message.intent && typeof message.intent === 'object') {
    win.intent = message.intent;
  }

  win.state = 'ready';
  win.reason = '';
  win.load = ++loads;
}

export function appRefused(id: string, reason: string) {
  const win = winOf(id);

  if (!win || win.closing) return;

  win.state = reason === 'no_signal' ? 'nosignal' : 'refused';
  win.reason = reason;
}

export function openPayload(win: Win) {
  return {
    app: win.id,
    kind: page.kind,
    mode: watching ? ('watch' as const) : ('use' as const),
    input: 'dui' as const,
    context: win.context,
    user: os.user,
    locale: {},
    brand: t('os_name'),
    scale: win.scale,
    canvas: appOf(win.id)?.canvas ?? { width: 960, height: 600 },
    intent: win.intent,
  };
}

function forget(id: string) {
  stopHello(id);
  lastShown.delete(id);
  host.detach(id);
  delete os.live[id];
  os.wins = os.wins.filter((entry) => entry.id !== id);
  os.order = os.order.filter((entry) => entry !== id);
  delete os.states[id];
}

export function closeWindow(id: string, animate = true, tell = true) {
  const win = winOf(id);

  if (!win || win.closing) return;

  if (tell && !watching) {
    host.send(id, 'os:close', { reason: 'closed' });

    if (win.token) {
      game.closeApp(id);
    }
  }

  if (tell && !watching && onlyClose(os.only, id, '', true) === 'leave') {
    forget(id);
    game.leaveDevice();

    return;
  }

  const element = windowElement(id);

  if (!animate || win.min || !element || typeof element.animate !== 'function') {
    forget(id);

    return;
  }

  win.closing = true;

  const target = (os.launcher && !os.launcherOut && centreOf(`[data-pop="l"] [data-app="${id}"]`)) || centreOf(`[data-app-icon="${id}"]`) || centreOf(`[data-task="${id}"]`) || fallback();
  const { dx, dy } = offset(target, win);

  const animation = element.animate(
    [
      { transform: 'none', opacity: 1 },
      { opacity: 1, offset: 0.55 },
      { transform: `translate(${dx}px,${dy}px) scale(.08)`, opacity: 0 },
    ],
    { duration: CLOSE_MS, easing: 'cubic-bezier(.55,0,.3,1)', fill: 'forwards' },
  );

  animation.onfinish = () => forget(id);
}

export function appClosed(id: string, reason: string) {
  const win = winOf(id);

  if (!win) return;

  const next = onlyClose(os.only, id, reason, false);

  if (next === 'error') {
    markError(win, reason);

    return;
  }

  closeWindow(id, next !== 'leave', false);

  if (next === 'leave') {
    game.leaveDevice();

    return;
  }

  if (reason && reason !== 'app_closed') {
    say(t('os_app_closed', appOf(id)?.label ?? id), true);
  }
}

export function minimizeWindow(id: string) {
  const win = winOf(id);

  if (!win || win.min || win.closing) return;

  const element = windowElement(id);
  const pill = centreOf(`[data-task="${id}"]`);

  const done = () => {
    win.min = true;
    visibility();
  };

  if (!element || !pill || typeof element.animate !== 'function') {
    done();

    return;
  }

  const { dx, dy } = offset(pill, win);

  const animation = element.animate(
    [
      { transform: 'none', opacity: 1 },
      { transform: `translate(${dx * 0.45}px,${dy * 0.45}px) scale(.5,.32)`, opacity: 0.95, offset: 0.55 },
      { transform: `translate(${dx}px,${dy}px) scale(.05,.02)`, opacity: 0 },
    ],
    { duration: MINIMIZE_MS, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' },
  );

  animation.onfinish = () => {
    done();
    animation.cancel();
  };
}

export function restoreWindow(id: string, from: { x: number; y: number } | null = null) {
  const win = winOf(id);

  if (!win || !win.min) return;

  win.min = false;
  focusWindow(id);
  visibility();
  tick().then(() => playIn(id, from ?? centreOf(`[data-task="${id}"]`)));
}

export function setMaximized(id: string, on: boolean, animate = true) {
  const win = winOf(id);

  if (!win || win.closing || win.max === on) return;

  const element = windowElement(id);
  const from = element && !win.min ? element.getBoundingClientRect() : null;

  win.max = on;

  if (!watching) {
    os.maxed = { ...os.maxed, [id]: on };
  }

  if (!animate || !element || !from || !from.width || typeof element.animate !== 'function') return;

  win.snap = true;

  tick().then(() => {
    const to = element.getBoundingClientRect();

    if (!to.width || !to.height) {
      win.snap = false;

      return;
    }

    const scale = os.scale || 1;

    const animation = element.animate(
      [
        {
          transformOrigin: '0 0',
          transform: `translate(${(from.left - to.left) / scale}px,${(from.top - to.top) / scale}px) scale(${from.width / to.width},${from.height / to.height})`,
        },
        { transformOrigin: '0 0', transform: 'none' },
      ],
      { duration: MAX_MS, easing: 'cubic-bezier(.2,.8,.2,1)' },
    );

    const done = () => {
      win.snap = false;
    };

    animation.onfinish = done;
    animation.oncancel = done;
  });
}

export function toggleMaximize(id: string) {
  const win = winOf(id);

  if (!win || watching) return;

  focusWindow(id);
  setMaximized(id, !win.max);
}

export function moveWindow(id: string, x: number, y: number) {
  const win = winOf(id);

  if (!win) return;

  const next = clampWindow(layout, win, x, y);

  win.x = next.x;
  win.y = next.y;
}

export function setSignal(signal: Signal) {
  const before = isOnline();

  os.signal = signal;

  const now = isOnline();

  if (before === now) return;

  for (const win of os.wins) {
    const app = appOf(win.id);

    if (!app?.network || win.closing) continue;

    if (now && win.state === 'nosignal') {
      ask(win);
    }
  }

  visibility();
}

export function toggleWifi() {
  if (os.signal.wired) return;

  os.toggles.wifi = !os.toggles.wifi;

  const signal = os.signal;

  os.signal = { ...signal };

  for (const win of os.wins) {
    if (isOnline() && win.state === 'nosignal') {
      ask(win);
    }
  }

  visibility();
}

export function setSystem(value: unknown) {
  os.system = cleanSystem(value);
}

export function setInstalled(value: unknown) {
  os.installed = cleanIds(value) ?? os.installed;
}

export function storeApps(): StoreApp[] {
  return os.apps.map((app) => ({
    id: app.id,
    label: app.label,
    icon: app.icon,
    description: app.description || (isBuiltin(app.id) ? t('os_app_about_' + app.id) : t('os_store_no_about')),
    size: sizeOf(app.id, app.size),
    version: app.version,
    builtin: isBuiltin(app.id),
    fixed: isFixed(app.id),
    installed: isInstalled(app.id),
    category: app.category,
    about: app.about,
    can: app.can,
    pictures: app.pictures,
    cover: app.cover,
    accent: app.accent,
    publisher: app.publisher,
    kinds: app.kinds,
    network: app.network,
    watch: app.watch,
    ...builtinStore(app.id, page.kind),
  }));
}

export async function installApp(id: string) {
  const answer = await game.osCall<{ installed: unknown }>('store:install', id);

  if (answer.ok) {
    setInstalled(answer.data?.installed);
    say(t('os_store_installed_toast', appOf(id)?.label ?? id));
  } else {
    say(reasonText({ reason: answer.reason ?? 'no_response' }), true);
  }

  return answer.ok;
}

export async function removeApp(id: string) {
  const label = appOf(id)?.label ?? id;
  const answer = await game.osCall<{ installed: unknown }>('store:remove', id);

  if (answer.ok) {
    closeWindow(id, true, false);
    setInstalled(answer.data?.installed);
    say(t('os_store_removed_toast', label));
  } else {
    say(reasonText({ reason: answer.reason ?? 'no_response' }), true);
  }

  return answer.ok;
}

export function setApps(list: unknown) {
  os.apps = [
    ...cleanApps(list).filter((entry) => !isBuiltin(entry.id)),
    ...builtinApps(os.system.apps, page.kind, builtinLabel),
  ].filter((entry) => onlyAllows(os.only, entry.id));

  const known = new Set(os.apps.map((entry) => entry.id));

  for (const win of [...os.wins]) {
    if (!known.has(win.id) && !isOnly(win.id)) {
      closeWindow(win.id, true, false);
    }
  }

  if (os.selected && !known.has(os.selected)) {
    os.selected = '';
  }
}

export const onDevice = (id: string) => !!appOf(id) && (isInstalled(id) || !!winOf(id));

function showBanner(entry: OsNotice) {
  for (const timer of bannerTimers) {
    clearTimeout(timer);
  }

  os.banner = { ...entry, out: false };

  bannerTimers = [
    setTimeout(() => {
      if (os.banner?.id === entry.id) {
        os.banner.out = true;
      }
    }, BANNER_MS),
    setTimeout(() => {
      if (os.banner?.id === entry.id) {
        os.banner = null;
      }
    }, BANNER_MS + BANNER_OUT_MS),
  ];
}

export function closeBanner() {
  for (const timer of bannerTimers) {
    clearTimeout(timer);
  }

  bannerTimers = [];
  os.banner = null;
}

export function notice(raw: unknown, app?: string) {
  const entry = cleanNotice(raw, Date.now(), app);

  if (!entry || (!onDevice(entry.app) && !entry.label)) return;

  os.notices = addNotice(os.notices, entry);

  if (entry.quiet || os.phase !== 'desktop' || os.only || os.prefs.dnd || os.prefs.quiet.includes(entry.app)) return;

  if (!os.notif) {
    showBanner(entry);
  }

  if (!entry.silent) {
    chime('notice');
  }
}

export function dismissNotice(id: string) {
  const gone = os.notices.find((entry) => entry.id === id);

  os.notices = os.notices.filter((entry) => entry.id !== id);

  if (os.banner?.id === id) {
    closeBanner();
  }

  if (gone?.key && !watching) {
    game.osCall('notice', 'dismiss', gone.key);
  }
}

export function clearNotices() {
  const kept = os.notices.some((entry) => entry.key);

  os.notices = [];
  closeBanner();

  if (kept && !watching) {
    game.osCall('notice', 'clear');
  }
}

export function actOnNotice(entry: OsNotice, from: { x: number; y: number } | null) {
  if (onDevice(entry.app)) {
    openApp(entry.app, from, entry.intent ?? { notice: entry.id });
  }

  dismissNotice(entry.id);
}

export function resetShell() {
  if (bootTimer) {
    clearTimeout(bootTimer);
  }

  if (popTimer) {
    clearTimeout(popTimer);
  }

  bootTimer = popTimer = null;

  for (const timer of toastTimers) {
    clearTimeout(timer);
  }

  closeBanner();

  for (const id of [...helloTimers.keys()]) {
    stopHello(id);
  }

  for (const win of os.wins) {
    host.detach(win.id);
  }

  os.toasts = [];
  os.wins = [];
  os.order = [];
  os.launcher = os.notif = os.launcherOut = os.notifOut = false;
  os.menu = null;
  os.soundPop = null;
  os.selected = '';
  os.query = '';
  os.notices = [];
  os.recent = [];
  os.badges = {};
  os.states = {};
  os.live = {};
  os.maxed = {};
  os.user = null;
  os.only = null;
  os.installed = null;
  os.system = cleanSystem(null);
  os.toggles = { wifi: true, sound: os.prefs.volume > 0, dnd: os.prefs.dnd };
}

export function cleanUser(value: unknown) {
  if (!value || typeof value !== 'object') return null;

  const raw = value as Record<string, unknown>;
  const name = typeof raw.name === 'string' ? raw.name.slice(0, 64) : '';

  return name
    ? { name, initials: typeof raw.initials === 'string' && raw.initials ? raw.initials.slice(0, 4) : initials(name) }
    : null;
}

export const host = createHost({
  hello(id) {
    stopHello(id);
    lastShown.delete(id);

    const win = winOf(id);

    if (win) {
      os.live = { ...os.live, [id]: win.load };
    }

    visibility();

    if (watching && os.states[id]) {
      host.send(id, 'os:state', { state: os.states[id] });
    }
  },
  mismatch(id) {
    const win = winOf(id);

    if (win) {
      win.state = 'update';
    }
  },
  activity(id) {
    if (watching) return;

    const win = winOf(id);

    if (win && !win.min) {
      focusWindow(id);
    }

    closePopovers();
  },
  editing(_id, on) {
    if (!watching) {
      game.reportEditing(on);
    }
  },
  unhandled(id, key, ctrl) {
    if (watching) return;

    if (ctrl && key.toLowerCase() === 'l') {
      setPhase('lock');

      return;
    }

    if (key === 'Escape') {
      closeWindow(id);
    }
  },
  publish(id, state) {
    if (!watching) {
      os.states[id] = state;
    }
  },
  privatePointer(_id, on) {
    if (!watching) {
      game.privatePointer(on);
    }
  },
  notify(id, raw) {
    if (!watching) {
      notice(raw, id);
    }
  },
  recent(id, entry) {
    if (!watching && appOf(id)) {
      os.recent = pushRecent(os.recent, {
        app: id,
        title: entry.title,
        sub: entry.sub ?? '',
        intent: entry.intent ?? null,
        at: Date.now(),
      });
    }
  },
  badge(id, count) {
    if (!watching) {
      os.badges = { ...os.badges, [id]: count };
    }
  },
  close(id) {
    if (!watching) {
      closeWindow(id);
    }
  },
  post(id, request) {
    if (!watching && winOf(id)?.token) {
      game.relayPost(id, request.id, request.name, request.data);
    }
  },
});
