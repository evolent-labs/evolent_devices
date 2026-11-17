import { createHost } from '$lib/apphost';
import { cleanIds, isFixed, sizeOf, storeInfo, type StoreApp } from '$lib/appstore';
import { wrongText } from '$lib/password';
import { press, startSession } from '$lib/sound';
import type { SessionSound } from '$lib/soundplan';
import { osName } from '$lib/brand.svelte';
import { iconOf } from '$lib/icon';
import { has, reasonText, t } from '$lib/state.svelte';
import { builtinApp, builtinStore } from '../../os/builtin';
import { cleanSystem, isBuiltin } from '../../os/system';
import { agoMinutes } from '../../os/text';
import { cleanClock, clockShift, untilChange } from './clock';
import { appScale, colourIndex, COLOURS, SCREEN, STATUS_BAR } from './frame';
import { host, setTabletToken } from './host';
import { cleanTabletSettings, DEFAULT_SET } from './settings';
import type { AppFrame, Phase, Pop, TabletApp, TabletGame, TabletNotice, TabletSettings, TabletSignal, TabletUser } from './types';

export const BOOT_MS = 1900;
export const POP_OUT_MS = 150;
export const TOAST_MS = 2000;
export const TOAST_GONE_MS = 2400;
const MAX_NOTICES = 50;
const HELLO_MS = 8000;
const ID = /^[a-z][a-z0-9_]{1,31}$/;
const KEY = /^[nm]\d{1,12}$/;

export { LOCK_CHOICES, SLEEP_CHOICES } from './settings';

export const tablet = $state({
  visible: false,
  serial: '',
  framed: true,
  phase: 'boot' as Phase,
  cur: null as string | null,
  open: [] as string[],
  nOpen: 0,
  pop: '' as Pop,
  popOut: false,
  entry: '',
  pinErr: false,
  shakeN: 0,
  loginMsg: '',
  checking: false,
  waitUntil: 0,
  pinNeeded: true,
  recolour: false,
  colour: 0,
  user: { name: '', role: '', org: '' } as TabletUser,
  apps: [] as TabletApp[],
  installed: null as string[] | null,
  system: cleanSystem(null),
  sound: null as SessionSound | null,
  notices: [] as TabletNotice[],
  frames: {} as Record<string, AppFrame>,
  live: {} as Record<string, number>,
  badges: {} as Record<string, number>,
  signal: { bars: 4, wired: false } as TabletSignal,
  limit: 4,
  battery: 100,
  shift: 0,
  skew: 0,
  now: Date.now(),
  set: { ...DEFAULT_SET } as TabletSettings,
  toast: null as { id: number; text: string; bad: boolean; out: boolean } | null,
  asleep: false,
  touchedAt: 0,
  rest: { after: 3, dim: 50 },
  game: { popup: true, sound: true, canPopup: true, canSound: true } as TabletGame,
});

let bootTimer: ReturnType<typeof setTimeout> | null = null;
let popTimer: ReturnType<typeof setTimeout> | null = null;
let toastTimers: ReturnType<typeof setTimeout>[] = [];
let toastId = 0;
let loads = 0;
const frameLoads = new Map<string, number>();
let colourPick = 0;
let colourPush = 0;
let colourSaved = 0;
let waitTimer: ReturnType<typeof setInterval> | null = null;

const storeKey = () => 'evdev:tablet:' + (tablet.serial || 'default');

function readSettings(): TabletSettings {
  try {
    return cleanTabletSettings(JSON.parse(localStorage.getItem(storeKey()) || '{}'));
  } catch {
    return { ...DEFAULT_SET, muted: {} };
  }
}

export function setSetting<K extends keyof TabletSettings>(key: K, value: TabletSettings[K]) {
  const before = online();

  tablet.set[key] = value;

  if (key === 'wifi' && before !== online()) {
    signalChanged();
  }

  try {
    localStorage.setItem(storeKey(), JSON.stringify(tablet.set));
  } catch {
  }
}

const text = (value: unknown, max: number) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

export function cleanApps(value: unknown): TabletApp[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const seen = new Set<string>();
  const list: TabletApp[] = [];

  for (const raw of value) {
    if (!raw || typeof raw !== 'object' || !ID.test(raw.id) || seen.has(raw.id)) continue;

    seen.add(raw.id);

    const width = Number(raw.canvas?.width);
    const height = Number(raw.canvas?.height);

    list.push({
      id: raw.id,
      label: text(raw.label, 32) || raw.id,
      icon: iconOf(raw.icon),
      tile: text(raw.tile, 200) || undefined,
      onTile: /^#[0-9a-f]{6}$/i.test(raw.onTile) ? raw.onTile : undefined,
      canvas: width >= 160 && height >= 120 ? { width, height } : undefined,
      network: raw.network !== false,
      description: text(raw.description, 120),
      size: Number(raw.size) > 0 ? Math.round(Number(raw.size)) : undefined,
      version: text(raw.version, 32),
      ...storeInfo(raw),
    });
  }

  return list;
}

export function cleanNotices(value: unknown): TabletNotice[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const list: TabletNotice[] = [];

  for (const raw of value) {
    if (!raw || typeof raw !== 'object' || !ID.test(raw.app)) continue;

    const id = text(String(raw.id ?? ''), 64);
    const title = text(raw.title, 80);

    if (!id || !title) continue;

    const intent = raw.intent && typeof raw.intent === 'object' && !Array.isArray(raw.intent) ? raw.intent : undefined;

    list.push({
      id,
      app: raw.app,
      title,
      body: text(raw.body, 240),
      at: Number(raw.at) || 0,
      action: text(raw.action, 32) || undefined,
      intent,
      key: typeof raw.key === 'string' && KEY.test(raw.key) ? raw.key : undefined,
      label: text(raw.label, 32) || undefined,
      icon: iconOf(raw.icon),
      quiet: raw.quiet === true || undefined,
      silent: raw.silent === true || undefined,
    });
  }

  return list.slice(0, MAX_NOTICES);
}

export function appOf(id: string | null) {
  return id ? tablet.apps.find((entry) => entry.id === id) ?? null : null;
}

export const isInstalled = (id: string) => tablet.installed === null || tablet.installed.includes(id);
export const homeApps = () => tablet.apps.filter((entry) => isInstalled(entry.id));

function withBuiltins(list: TabletApp[]) {
  const own = tablet.system.apps.filter((id) => isBuiltin(id)).map((id) => {
    const app = builtinApp(id, 'tablet', t('os_app_' + id));

    return { id, label: app.label, icon: app.icon, network: app.network, size: app.size, builtin: true };
  });

  return [...list.filter((entry) => !isBuiltin(entry.id)), ...own];
}

export function setInstalled(value: unknown) {
  tablet.installed = cleanIds(value) ?? tablet.installed;
}

export function storeApps(): StoreApp[] {
  return tablet.apps.map((app) => ({
    id: app.id,
    label: app.label,
    icon: app.icon,
    description: app.description || (app.builtin ? t('os_app_about_' + app.id) : t('os_store_no_about')),
    size: sizeOf(app.id, app.size),
    version: app.version ?? '',
    builtin: app.builtin === true,
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
    ...(app.builtin ? builtinStore(app.id, 'tablet') : {}),
  }));
}

export async function installApp(id: string) {
  const answer = await host.os('store:install', id);

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
  const answer = await host.os('store:remove', id);

  if (answer.ok) {
    receiveFrameClosed(id, '');
    setInstalled(answer.data?.installed);
    say(t('os_store_removed_toast', label));
  } else {
    say(reasonText({ reason: answer.reason ?? 'no_response' }), true);
  }

  return answer.ok;
}

function chime() {
  if (tablet.sound && tablet.set.sound) {
    press('notice', tablet.sound.volume);
  }
}

export function setPasswordOn(on: boolean, owner: boolean) {
  tablet.system.password = on;
  tablet.pinNeeded = on;

  if (owner) {
    tablet.system.owner = true;
    tablet.system.ownerName = tablet.user.name;
  }
}

async function relock() {
  const answer = await host.os('lock');

  if (answer.ok) {
    tablet.pinNeeded = tablet.system.password = answer.data?.password === true;
  }
}

export function online() {
  return tablet.signal.wired || (tablet.set.wifi && tablet.signal.bars > 0);
}

export function cleanSignal(value: unknown): TabletSignal {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const bars = Number(raw.bars);

  return {
    bars: Number.isInteger(bars) ? Math.max(0, Math.min(4, bars)) : tablet.signal.bars,
    wired: raw.wired === true,
  };
}

export function colourHex() {
  return COLOURS[tablet.colour]?.hex ?? COLOURS[0].hex;
}

export function colourLabel(index: number) {
  const id = COLOURS[index]?.id ?? '';

  return has('tablet_colour_' + id) ? t('tablet_colour_' + id) : id;
}

export function firstName() {
  return tablet.user.name.split(/\s+/).filter(Boolean)[0] ?? '';
}

export function say(message: string, bad = false) {
  toastTimers.forEach(clearTimeout);
  tablet.toast = { id: ++toastId, text: message, bad, out: false };

  toastTimers = [
    setTimeout(() => tablet.toast && (tablet.toast.out = true), TOAST_MS),
    setTimeout(() => (tablet.toast = null), TOAST_GONE_MS),
  ];
}

function scheduleBoot() {
  if (bootTimer) {
    clearTimeout(bootTimer);
  }

  bootTimer = setTimeout(() => {
    bootTimer = null;

    if (tablet.phase === 'boot') {
      tablet.phase = 'lock';
    }
  }, BOOT_MS);
}

function takeFocus() {
  const active = document.activeElement;

  if (!(active instanceof HTMLIFrameElement)) return;

  active.blur();
  window.focus();
}

export function setPhase(phase: Phase) {
  takeFocus();
  tablet.phase = phase;
  tablet.pop = '';
  tablet.popOut = false;

  if (phase === 'boot') {
    scheduleBoot();
  }

  host.phase(phase === 'boot' || phase === 'login' ? 'lock' : phase);
  visibility();
}

function resetPin() {
  tablet.entry = '';
  tablet.pinErr = false;
  tablet.loginMsg = '';
  tablet.checking = false;
}

export function lock() {
  resetPin();
  setPhase('lock');
  relock();
}

export function unlock() {
  resetPin();
  setPhase('home');

  const name = firstName();

  say(name ? t('os_welcome', name) : t('os_welcome_plain'));
}

export function toLogin() {
  if (!tablet.pinNeeded) {
    return unlock();
  }

  resetPin();
  tablet.phase = 'login';
}

export function toLock() {
  resetPin();
  tablet.phase = 'lock';
}

export function restart() {
  setPhase('boot');
  relock();
}

export function powerOff() {
  setPhase('off');
  relock();
}

function loginWrong(message: string) {
  tablet.entry = '';
  tablet.pinErr = true;
  tablet.shakeN++;
  tablet.loginMsg = message;
}

function waitText() {
  const left = Math.max(0, Math.ceil((tablet.waitUntil - Date.now()) / 1000));

  if (left > 0) {
    tablet.loginMsg = t('os_password_wait', left);

    return;
  }

  if (waitTimer) {
    clearInterval(waitTimer);
  }

  waitTimer = null;
  tablet.waitUntil = 0;
  tablet.pinErr = false;
  tablet.loginMsg = '';
}

function startWait(seconds: number) {
  tablet.entry = '';
  tablet.pinErr = true;
  tablet.shakeN++;
  tablet.waitUntil = Date.now() + Math.max(1, seconds) * 1000;

  if (waitTimer) {
    clearInterval(waitTimer);
  }

  waitTimer = setInterval(waitText, 500);
  waitText();
}

export function typedPassword() {
  if (tablet.waitUntil > Date.now()) return;

  tablet.pinErr = false;
  tablet.loginMsg = '';
}

export async function submitPassword() {
  if (tablet.phase !== 'login' || tablet.checking || tablet.waitUntil > Date.now()) return;

  if ([...tablet.entry].length < tablet.system.limits.passwordMin) {
    loginWrong(t('os_password_short', tablet.system.limits.passwordMin));

    return;
  }

  tablet.checking = true;

  const answer = await host.os('unlock', tablet.entry);

  if (tablet.phase !== 'login') return;

  tablet.checking = false;

  if (answer.ok) {
    if (answer.data?.notices) {
      tablet.notices = cleanNotices(answer.data.notices);
    }

    unlock();
  } else if (answer.reason === 'password_wait') {
    startWait(Number(answer.data?.seconds ?? 60));
  } else if (answer.reason === 'password_wrong') {
    loginWrong(wrongText(Number(answer.data?.left ?? 0)));
  } else {
    loginWrong(reasonText({ reason: answer.reason ?? 'no_response' }));
  }
}

export async function forgotPassword() {
  const answer = await host.os('forgot');

  if (answer.ok) {
    if (answer.data?.notices) {
      tablet.notices = cleanNotices(answer.data.notices);
    }

    setPasswordOn(false, false);
    unlock();
  } else {
    tablet.pinErr = true;
    tablet.loginMsg = reasonText({ reason: answer.reason ?? 'no_response' });
  }
}

export function closePops(then?: () => void) {
  if (!tablet.pop) {
    then?.();

    return;
  }

  if (popTimer) {
    clearTimeout(popTimer);
  }

  tablet.popOut = true;

  popTimer = setTimeout(() => {
    popTimer = null;
    tablet.pop = '';
    tablet.popOut = false;
    then?.();
  }, POP_OUT_MS);
}

export function togglePop(pop: Exclude<Pop, ''>) {
  if (tablet.pop === pop && !tablet.popOut) {
    return closePops();
  }

  closePops(() => {
    tablet.pop = pop;
  });
}

const helloTimers = new Map<string, ReturnType<typeof setTimeout>>();

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

      const frame = tablet.frames[id];

      if (frame && frame.load === load && frame.state === 'ready' && !appHost.seen(id)) {
        tablet.frames[id] = { ...frame, state: 'failed', reason: 'app_no_hello' };
      }
    }, HELLO_MS),
  );
}

function emptyFrame(state: AppFrame['state'], reason = ''): AppFrame {
  return { state, url: '', reason, token: '', context: {}, intent: null, load: 0 };
}

async function loadApp(id: string, intent?: Record<string, unknown> | null) {
  const load = ++loads;

  frameLoads.set(id, load);
  appHost.detach(id);

  if (appOf(id)?.builtin) {
    tablet.frames[id] = { ...emptyFrame('ready'), intent: intent ?? null, load };

    return;
  }

  if (appOf(id)?.network && !online()) {
    tablet.frames[id] = { ...emptyFrame('failed', 'no_signal'), intent: intent ?? null };

    return;
  }

  tablet.frames[id] = emptyFrame('loading');

  const answer = await host.openApp(id, intent);

  if (frameLoads.get(id) !== load || !tablet.open.includes(id)) return;

  if (answer.ok && typeof answer.url === 'string' && answer.url && typeof answer.token === 'string') {
    const context = answer.context && typeof answer.context === 'object' && !Array.isArray(answer.context)
      ? answer.context
      : {};

    tablet.frames[id] = {
      state: 'ready',
      url: answer.url,
      reason: '',
      token: answer.token,
      context,
      intent: answer.intent ?? intent ?? null,
      load,
    };
  } else {
    tablet.frames[id] = emptyFrame('failed', answer.reason || 'no_response');
  }
}

export function openApp(id: string, intent?: Record<string, unknown> | null) {
  if (!appOf(id)) return;

  closePops();

  if (!tablet.open.includes(id) && tablet.open.length >= tablet.limit) {
    say(t('os_window_limit', tablet.limit), true);

    return;
  }

  tablet.open = [...tablet.open.filter((entry) => entry !== id), id];

  if (tablet.cur !== id) {
    tablet.nOpen++;
  }

  tablet.cur = id;

  const frame = tablet.frames[id];

  if (!frame || frame.state === 'failed') loadApp(id, intent);
  else if (intent) {
    if (appHost.seen(id)) appHost.send(id, 'os:intent', { intent });
    else frame.intent = intent;
  }

  visibility();
}

export function retryApp(id: string) {
  delete tablet.frames[id];
  openApp(id);
}

const lastShown = new Map<string, boolean>();

export function visibility() {
  for (const id of Object.keys(tablet.frames)) {
    const frame = tablet.frames[id];
    const covered = appOf(id)?.network === true && !online();
    const shown = tablet.visible && tablet.phase === 'home' && tablet.cur === id && frame.state === 'ready' && !covered;

    if (lastShown.get(id) === shown || !appHost.seen(id)) continue;

    lastShown.set(id, shown);
    appHost.send(id, 'os:visibility', { visible: shown });
    host.appVisible(id, shown);
  }
}

function signalChanged() {
  for (const id of tablet.open) {
    const frame = tablet.frames[id];

    if (online() && frame?.state === 'failed' && frame.reason === 'no_signal') {
      loadApp(id, frame.intent);
    }
  }

  visibility();
}

export function setSignal(value: unknown) {
  const before = online();

  tablet.signal = cleanSignal(value);

  if (before !== online()) {
    signalChanged();
  }
}

function initialsOf(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => Array.from(part)[0].toUpperCase())
    .join('');
}

export function openPayload(id: string, frame: AppFrame) {
  const canvas = appOf(id)?.canvas ?? { width: SCREEN.width, height: SCREEN.height - STATUS_BAR };
  const scale = appScale(canvas);

  return {
    app: id,
    kind: 'tablet',
    mode: 'use' as const,
    input: 'native' as const,
    context: frame.context,
    user: tablet.user.name ? { name: tablet.user.name, initials: initialsOf(tablet.user.name) } : null,
    locale: {},
    brand: osName(),
    scale: Math.round(scale * 10000) / 10000,
    canvas,
    intent: frame.intent,
  };
}

export const appHost = createHost({
  hello(id) {
    stopHello(id);
    lastShown.delete(id);

    const frame = tablet.frames[id];

    if (frame) {
      tablet.live = { ...tablet.live, [id]: frame.load };
    }

    visibility();
  },
  mismatch(id) {
    const frame = tablet.frames[id];

    if (frame) {
      tablet.frames[id] = { ...frame, state: 'update' };
    }
  },
  activity(id) {
    if (!tablet.visible || tablet.phase !== 'home' || tablet.cur !== id) return;

    closePops();
    touched();
    host.activity();
  },
  unhandled(id, key, ctrl) {
    if (!tablet.visible || tablet.phase !== 'home' || tablet.cur !== id) return;

    host.activity();

    if (ctrl && key.toLowerCase() === 'l') lock();
    else if (key === 'Escape') goHome();
  },
  notify(id, notice) {
    const [entry] = cleanNotices([
      { ...notice, app: id, id: notice.id ?? id + ':' + notice.title, at: notice.at ?? Math.floor(Date.now() / 1000) },
    ]);

    if (entry) {
      notify(entry);
    }
  },
  badge(id, count) {
    tablet.badges = { ...tablet.badges, [id]: count };
  },
  close(id) {
    closeApp(id);
  },
  post(id, request) {
    if (tablet.frames[id]?.token) {
      host.appPost(id, request.id, request.name, request.data);
    }
  },
});

export function goHome() {
  takeFocus();
  closePops();
  tablet.cur = null;
  visibility();
}

function dropFrame(id: string) {
  stopHello(id);
  lastShown.delete(id);
  appHost.detach(id);
  frameLoads.delete(id);
  delete tablet.frames[id];
  delete tablet.live[id];
}

export function closeApp(id: string) {
  if (tablet.cur === id) {
    takeFocus();
  }

  const token = tablet.frames[id]?.token;

  if (appHost.seen(id)) {
    appHost.send(id, 'os:close', { reason: 'closed' });
  }

  tablet.open = tablet.open.filter((entry) => entry !== id);

  if (tablet.cur === id) {
    tablet.cur = null;
  }

  dropFrame(id);

  if (token) {
    host.closeApp(id);
  }
}

export function closeAll() {
  for (const id of [...tablet.open]) {
    closeApp(id);
  }

  closePops();
}

export const onTablet = (id: string) => !!appOf(id) && (isInstalled(id) || tablet.open.includes(id));

export function dismissNotice(id: string) {
  const gone = tablet.notices.find((entry) => entry.id === id);

  tablet.notices = tablet.notices.filter((entry) => entry.id !== id);

  if (gone?.key) {
    host.os('notice', 'dismiss', gone.key);
  }
}

export function clearNotices() {
  const kept = tablet.notices.some((entry) => entry.key);

  tablet.notices = [];

  if (kept) {
    host.os('notice', 'clear');
  }
}

export function noticeAction(notice: TabletNotice) {
  dismissNotice(notice.id);

  if (onTablet(notice.app)) {
    openApp(notice.app, notice.intent ?? { notice: notice.id });
  }
}

export function notify(notice: TabletNotice) {
  if (!onTablet(notice.app) && !notice.label) return;

  tablet.notices = [notice, ...tablet.notices.filter((entry) => entry.id !== notice.id)].slice(0, MAX_NOTICES);

  if (!notice.quiet && tablet.visible && tablet.phase === 'home' && !tablet.set.dnd && tablet.set.muted[notice.app] !== true) {
    say(notice.title);

    if (!notice.silent) {
      chime();
    }
  }
}

export function cleanGame(value: unknown): TabletGame {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};

  return { popup: raw.popup !== false, sound: raw.sound !== false, canPopup: raw.canPopup !== false, canSound: raw.canSound !== false };
}

export async function setGame(patch: { popup?: boolean; sound?: boolean }) {
  const before = { ...tablet.game };

  tablet.game = { ...tablet.game, ...patch };

  const answer = (await host.game(patch)) as unknown as Record<string, unknown>;

  if (answer.ok !== true) {
    tablet.game = before;

    return;
  }

  tablet.game = { ...tablet.game, popup: answer.popup !== false, sound: answer.sound !== false };
}

export function setColour(value: unknown) {
  colourPick++;
  colourPush++;
  tablet.colour = colourSaved = colourIndex(value);
}

export async function pickColour(index: number) {
  const wanted = colourIndex(index);

  if (wanted === tablet.colour) return;

  const pick = ++colourPick;
  const push = colourPush;

  tablet.colour = wanted;

  const answer = await host.colour(wanted);

  if (push !== colourPush) return;

  if (answer.colour !== undefined) colourSaved = colourIndex(answer.colour);
  else if (answer.ok) colourSaved = wanted;

  if (pick !== colourPick) return;

  tablet.colour = colourSaved;

  if (!answer.ok) {
    say(reasonText({ reason: answer.reason }), true);
  }
}

export function receiveFrameClosed(id: string, reason: string) {
  if (!tablet.open.includes(id)) return;

  if (tablet.cur === id) {
    takeFocus();
  }

  if (appHost.seen(id)) {
    appHost.send(id, 'os:close', { reason: reason || 'closed' });
  }

  tablet.open = tablet.open.filter((entry) => entry !== id);

  if (tablet.cur === id) {
    tablet.cur = null;
  }

  dropFrame(id);

  if (reason && reason !== 'app_closed') {
    say(reasonText({ reason }), true);
  }
}

export function setClock(value: unknown) {
  const clock = cleanClock(value);

  tablet.now = Date.now();
  tablet.shift = clockShift(clock, tablet.now);
  tablet.skew = clock ? clock.now - tablet.now / 1000 : 0;
}

export const untilTick = (now: number) => untilChange(
  now + tablet.shift,
  tablet.set.seconds,
  tablet.notices.filter((notice) => notice.at).map((notice) => now + (tablet.skew - notice.at) * 1000)
);

export function agoText(at: number) {
  if (!at) {
    return '';
  }

  return agoMinutes(Math.max(0, Math.floor((tablet.now / 1000 + tablet.skew - at) / 60)));
}

export const sleepMinutes = () => (tablet.set.sleep < 0 ? tablet.rest.after : tablet.set.sleep);

export function touched() {
  tablet.touchedAt = Date.now();
}

export function sleepNow() {
  if (tablet.asleep || !tablet.visible) return;

  closePops();
  tablet.asleep = true;
  host.sleep(true);
}

export function wake() {
  touched();

  if (!tablet.asleep) return false;

  tablet.asleep = false;
  host.sleep(false);

  return true;
}

export function openTablet(data: any) {
  const value = data && typeof data === 'object' ? data : {};

  tablet.asleep = false;
  touched();

  const rest = value.sleep && typeof value.sleep === 'object' ? value.sleep : {};
  const after = Number(rest.after);
  const dim = Number(rest.dim);

  tablet.rest = {
    after: Number.isFinite(after) ? Math.max(0, Math.min(240, after)) : 3,
    dim: Number.isFinite(dim) ? Math.max(10, Math.min(90, dim)) : 50,
  };

  tablet.serial = text(value.serial, 32);
  tablet.framed = value.frame !== false;
  setTabletToken(text(value.token, 64));
  setColour(value.colour);
  tablet.recolour = value.recolour === true;
  tablet.pinNeeded = value.pin === true;
  tablet.system = cleanSystem(value.os);
  tablet.installed = cleanIds(value.installed);
  tablet.sound = startSession(value.sound);
  tablet.user = { name: text(value.user?.name, 40), role: text(value.user?.role, 32), org: text(value.user?.org, 48) };
  tablet.apps = withBuiltins(cleanApps(value.apps));
  tablet.notices = cleanNotices(value.notices);
  tablet.game = cleanGame(value.game);
  tablet.signal = cleanSignal(value.signal);
  tablet.badges = {};

  const limit = Number(value.windows);

  tablet.limit = Number.isInteger(limit) && limit > 0 ? Math.min(8, limit) : 4;

  const battery = Number(value.battery);

  tablet.battery = Number.isFinite(battery) ? Math.max(0, Math.min(100, Math.round(battery))) : 100;
  tablet.set = readSettings();
  setClock(value.clock);

  const known = new Set(tablet.apps.map((entry) => entry.id));

  for (const id of [...tablet.open]) {
    if (!known.has(id)) {
      closeApp(id);
    }
  }

  tablet.pop = '';
  tablet.popOut = false;
  resetPin();

  const phase = value.phase === 'off' || value.phase === 'lock' || value.phase === 'home' ? value.phase : 'boot';

  tablet.phase = phase;

  if (phase === 'boot') {
    scheduleBoot();
  }

  tablet.visible = true;
}

export function hideTablet() {
  takeFocus();
  setTabletToken('');
  frameLoads.clear();
  tablet.visible = false;
  tablet.asleep = false;
  tablet.pop = '';
  tablet.popOut = false;

  for (const id of Object.keys(tablet.frames)) {
    dropFrame(id);
  }

  tablet.open = [];
  tablet.cur = null;
  tablet.frames = {};
  tablet.live = {};

  if (bootTimer) {
    clearTimeout(bootTimer);
  }

  bootTimer = null;

  if (tablet.phase === 'boot' || tablet.phase === 'login') {
    tablet.phase = 'lock';
  }
}

export function tabletMessage(message: any) {
  switch (message.action) {
    case 'colour':
      setColour(message.colour);
      break;
    case 'apps': {
      setInstalled(message.installed);
      tablet.apps = withBuiltins(cleanApps(message.apps));

      const known = new Set(tablet.apps.map((entry) => entry.id));

      for (const id of [...tablet.open]) {
        if (!known.has(id)) {
          receiveFrameClosed(id, '');
        }
      }

      break;
    }
    case 'notify': {
      const [notice] = cleanNotices([message.notice]);

      if (notice) {
        notify(notice);
      }

      break;
    }
    case 'appClosed':
      if (typeof message.app === 'string') {
        receiveFrameClosed(message.app, typeof message.reason === 'string' ? message.reason : '');
      }

      break;
    case 'toApp':
      if (typeof message.app === 'string') {
        appHost.sendOwn(message.app, message.message, true);
      }

      break;
    case 'appReply':
      if (typeof message.app === 'string') {
        appHost.send(message.app, 'os:reply', { id: message.id, data: message.data });
      }

      break;
    case 'appIntent':
    case 'openApp':
      if (typeof message.app === 'string') {
        openApp(message.app, message.intent && typeof message.intent === 'object' ? message.intent : null);
      }

      break;
    case 'signal':
      setSignal(message.signal);
      break;
  }
}
