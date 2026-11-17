import { editKey, insertText, numberText, numberValue, type TextState } from './textedit.ts';
import {
  cleanFlatState,
  cleanNotice,
  cleanRecent,
  HOST_ORIGIN,
  PROTOCOL,
  SDK_VERSION,
  type FlatState,
  type Notice,
  type RecentEntry,
} from './protocol.ts';

export { PROTOCOL, SDK_VERSION, cleanFlatState };
export type { FlatState, Notice, RecentEntry };

export type Transport = 'frame' | 'direct' | 'none';
export type Mode = 'use' | 'watch' | '';
export type InputMode = 'dui' | 'native';

export interface OsUser {
  name: string;
  initials: string;
}

export interface StudioInfo {
  yaw: number;
  pitch: number;
  zoom: number;
  zoomMin: number;
  zoomMax: number;
  spin: number;
}

export interface OpenInfo {
  context: Record<string, any>;
  intent: Record<string, any> | null;
  user: OsUser | null;
  kind: string;
  mode: Mode;
  scale: number;
  locale: Record<string, string>;
  brand: string;
  studio: StudioInfo | null;
}

export interface PostOptions {
  readOnly?: boolean;
  timeout?: number;
}

export interface ConnectOptions {
  manualReady?: boolean;
  window?: Window;
  fetch?: typeof fetch;
}

export interface OsApp {
  readonly hosted: boolean;
  readonly mode: Mode;
  readonly kind: string;
  readonly app: string;
  readonly transport: Transport;
  readonly input: InputMode;
  readonly token: string;
  readonly context: Record<string, any>;
  readonly user: OsUser | null;
  readonly locale: Record<string, string>;
  readonly brand: string;
  readonly scale: number;
  readonly opened: boolean;
  readonly relayed: boolean;
  readonly studio: StudioInfo | null;
  on(action: string, handler: (data: any, message: any) => void): () => void;
  onMessage(handler: (message: any) => void): () => void;
  onOpen(handler: (info: OpenInfo) => void): () => void;
  onClose(handler: (reason: string) => void): () => void;
  onIntent(handler: (intent: Record<string, any>) => void): () => void;
  onVisibility(handler: (visible: boolean) => void): () => void;
  onState(handler: (state: FlatState) => void): () => void;
  post<T = any>(name: string, data?: Record<string, unknown>, options?: PostOptions): Promise<T>;
  publish(state: FlatState): boolean;
  close(): void;
  leave(): void;
  notify(notice: Notice): boolean;
  recent(entry: RecentEntry): boolean;
  badge(count: number): void;
  privatePointer(on: boolean): void;
  studioSend(action: Record<string, unknown>): boolean;
  ready(): void;
  disconnect(): void;
}

type Field = HTMLInputElement | HTMLTextAreaElement;

const HELLO_TRIES = 8;
const HELLO_MS = 1000;
const READY_TRIES = 5;
const READY_MS = 500;
const ACTIVITY_MS = 250;
const PUBLISH_MS = 500;
const DOUBLE_GUARD_MS = 400;
const POST_MS = 15000;
const SHIM_ROW = 34;
const SHIM_MAX = 320;
const TEXT_TYPES = ['text', 'search', 'url', 'tel', 'password', 'email', 'number'];
const FOCUSABLE = 'input:not([type=hidden]):not([disabled]),textarea:not([disabled]),select:not([disabled]),button:not([disabled]),[tabindex]:not([tabindex="-1"])';

const DIRECT_TYPES = new Set([
  'init',
  'open',
  'shown',
  'close',
  'watch',
  'state',
  'clock',
  'pointer',
  'idle',
  'deviceKey',
  'deviceDblClick',
  'osReply',
]);

const word = (value: string | null, pattern: RegExp, limit: number) => (value ?? '').replace(pattern, '').slice(
  0,
  limit
);

function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => Array.from(part)[0].toUpperCase())
    .join('');
}

function cleanUser(value: unknown): OsUser | null {
  if (!value || typeof value !== 'object') return null;

  const raw = value as Record<string, unknown>;
  const name = typeof raw.name === 'string' ? raw.name.slice(0, 64) : '';

  if (!name) return null;

  return {
    name,
    initials: typeof raw.initials === 'string' && raw.initials ? raw.initials.slice(0, 4) : initials(name),
  };
}

const object = (value: unknown): Record<string, any> => (value && typeof value === 'object' && !Array.isArray(value)
  ? (value as Record<string, any>)
  : {});

const finite = (value: unknown, fallback: number) => (typeof value === 'number' && Number.isFinite(value)
  ? value
  : fallback);

function cleanStudio(value: unknown): StudioInfo | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;

  const raw = value as Record<string, unknown>;
  const zoomMin = finite(raw.zoomMin, 0.8);
  const zoomMax = Math.max(zoomMin, finite(raw.zoomMax, 2));

  return {
    yaw: finite(raw.yaw, 0),
    pitch: finite(raw.pitch, 10),
    zoom: finite(raw.zoom, 1),
    zoomMin,
    zoomMax,
    spin: Math.max(0, finite(raw.spin, 0)),
  };
}

let instance: OsApp | null = null;

export function connectApp(options: ConnectOptions = {}): OsApp {
  if (instance) {
    return instance;
  }

  const win = options.window ?? window;
  const realm = win as Window & typeof globalThis;
  const doc = win.document;
  const send = options.fetch ?? win.fetch.bind(win);
  const params = new URLSearchParams(win.location.search);
  const hash = new URLSearchParams(win.location.hash.replace(/^#/, ''));
  const host = word(params.get('host'), /[^\w-]/g, 64);
  const harness = params.get('harness') === '1';
  const framed = win.parent !== win;
  const transport: Transport = framed ? 'frame' : host ? 'direct' : 'none';
  const hostOrigin = harness ? win.location.origin : HOST_ORIGIN;
  const mode: Mode = params.get('mode') === 'watch' ? 'watch' : transport === 'none' ? '' : 'use';
  const appId = word(params.get('app'), /[^a-z0-9_]/g, 32);
  const browser = word(params.get('browser'), /[^\w-]/g, 64);
  const secret = word(hash.get('s'), /[^0-9a-f]/gi, 64);
  const parentName = (win as any).GetParentResourceName;

  const resource = typeof parentName === 'function'
    ? String(parentName())
    : (/^cfx-nui-(.+)$/.exec(win.location.hostname)?.[1] ?? '');

  let kind = word(params.get('kind'), /[^a-z]/g, 16);
  let token = '';
  let context: Record<string, any> = {};
  let user: OsUser | null = null;
  let locale: Record<string, string> = {};
  let brand = 'Evolent OS';
  let scale = 1;
  let input: InputMode = transport === 'direct' ? 'dui' : 'native';
  let studio: StudioInfo | null = null;
  let opened = false;
  let readySent = false;
  let relay = transport !== 'none' && !resource;
  let helloTimer: ReturnType<typeof setTimeout> | null = null;
  let activityAt = 0;
  let pendingState: FlatState | null = null;
  let publishTimer: ReturnType<typeof setTimeout> | null = null;
  let replyId = 0;
  const replies = new Map<string, { resolve: (value: any) => void; timer: ReturnType<typeof setTimeout> }>();

  const handlers = {
    action: new Map<string, Set<(data: any, message: any) => void>>(),
    message: new Set<(message: any) => void>(),
    open: new Set<(info: OpenInfo) => void>(),
    close: new Set<(reason: string) => void>(),
    intent: new Set<(intent: Record<string, any>) => void>(),
    visibility: new Set<(visible: boolean) => void>(),
    state: new Set<(state: FlatState) => void>(),
  };

  const off: (() => void)[] = [];

  const listen = (target: EventTarget, type: string, handler: (event: any) => void, capture = false) => {
    target.addEventListener(type, handler, capture);
    off.push(() => target.removeEventListener(type, handler, capture));
  };

  const each = <T>(set: Set<(value: T) => void>, value: T) => {
    for (const handler of [...set]) {
      try {
        handler(value);
      } catch (error) {
        console.error('[evolent os app]', error);
      }
    }
  };

  const add = <T>(set: Set<T>, handler: T) => {
    set.add(handler);

    return () => {
      set.delete(handler);
    };
  };

  function toHost(type: string, extra: Record<string, unknown> = {}) {
    if (transport !== 'frame') return;

    win.parent.postMessage({ ...extra, __os: 1, type, token }, hostOrigin);
  }

  function toGame(name: string, extra: Record<string, unknown> = {}) {
    if (transport !== 'direct') {
      return Promise.resolve(null);
    }

    return send(`https://${host}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ ...extra, browser, s: secret }),
    }).catch(() => null);
  }

  let field: Field | null = null;
  let fieldValue = '';
  let shadow: string | null = null;
  let editing: boolean | null = null;
  let trustedDouble = -Infinity;
  let syntheticDouble = -Infinity;

  function fieldOf(target: EventTarget | null): Field | null {
    const element = target instanceof realm.Element ? target.closest('input,textarea') : null;

    if (element instanceof realm.HTMLTextAreaElement) {
      return element.disabled || element.readOnly ? null : element;
    }

    if (element instanceof realm.HTMLInputElement && TEXT_TYPES.includes(element.type) && !element.disabled && !element.readOnly) {
      return element;
    }

    return null;
  }

  function reportEditing() {
    const now = field !== null;

    if (editing === now) return;

    editing = now;

    if (mode !== 'use') return;

    if (transport === 'direct') toGame('device:state', { editing: now });
    else toHost('editing', { on: now });
  }

  function commit(target: Field) {
    if (target.value === fieldValue) return;

    fieldValue = target.value;
    target.dispatchEvent(new realm.Event('change', { bubbles: true }));
  }

  function activate(next: Field | null) {
    if (next === field) return;

    const previous = field;

    field = next;
    shadow = null;

    if (previous) {
      commit(previous);

      if (doc.activeElement === previous) {
        previous.blur();
      }
    }

    fieldValue = next ? next.value : '';

    if (next) {
      next.focus({ preventScroll: true });
    }

    reportEditing();
  }

  const onScreen = (element: Element) => element.isConnected && element.getClientRects().length > 0;

  function liveField() {
    if (field && !onScreen(field)) {
      activate(null);
    }

    return field;
  }

  const isNumber = (target: Field): target is HTMLInputElement => target instanceof realm.HTMLInputElement && target.type === 'number';

  function selectionOf(target: Field): TextState {
    if (isNumber(target) && shadow !== null && numberValue(shadow) !== target.value) {
      shadow = null;
    }

    const value = isNumber(target) ? (shadow ?? target.value) : target.value;
    let start: number | null = null;
    let end: number | null = null;

    try {
      start = target.selectionStart;
      end = target.selectionEnd;
    } catch {
      start = null;
    }

    if (start === null || end === null || isNumber(target)) {
      start = end = value.length;
    }

    return { value, start, end };
  }

  function apply(target: Field, next: TextState) {
    if (isNumber(target)) {
      if (!numberText(next.value)) return;

      shadow = next.value;

      const value = numberValue(next.value);

      if (target.value === value) return;

      target.value = value;
      target.dispatchEvent(new realm.Event('input', { bubbles: true }));

      return;
    }

    const changed = target.value !== next.value;

    if (changed) {
      target.value = next.value;
    }

    try {
      target.setSelectionRange(next.start, next.end);
    } catch {
    }

    if (changed) {
      target.dispatchEvent(new realm.Event('input', { bubbles: true }));
    }
  }

  function keyTarget(): EventTarget {
    const target = liveField();

    if (target) {
      return target;
    }

    const active = doc.activeElement;

    return active && active !== doc.body && active.isConnected ? active : doc.body;
  }

  function keyEvent(target: EventTarget, key: string, ctrl: boolean, shift: boolean) {
    const event = new realm.KeyboardEvent('keydown', {
      key,
      ctrlKey: ctrl,
      shiftKey: shift,
      bubbles: true,
      cancelable: true,
      composed: true,
    });

    target.dispatchEvent(event);

    return !event.defaultPrevented;
  }

  function moveFocus(from: Element | null, back: boolean) {
    const current = from ?? (doc.activeElement !== doc.body ? doc.activeElement : null);
    const scope: ParentNode = current?.closest('[role="dialog"]') ?? doc;
    const list = Array.from(scope.querySelectorAll<HTMLElement>(FOCUSABLE)).filter((element) => element.getClientRects().length > 0);

    if (!list.length) return;

    const index = current ? list.indexOf(current as HTMLElement) : -1;
    const next = list[index < 0 ? (back ? list.length - 1 : 0) : (index + (back ? -1 : 1) + list.length) % list.length];
    const nextField = fieldOf(next);

    activate(nextField);

    if (!nextField) {
      next.focus({ preventScroll: false });
    }
  }

  function typeText(text: string) {
    const target = liveField();

    if (!target) {
      const at = keyTarget();

      for (const character of Array.from(text)) {
        keyEvent(at, character, false, false);
      }

      return;
    }

    apply(target, insertText(selectionOf(target), text, target.maxLength));
  }

  function unhandled(key: string, ctrl: boolean) {
    toHost('unhandled', { key, ctrl });
  }

  function controlKey(key: string, ctrl: boolean, shift: boolean) {
    if (shim.open && shimKey(key)) return;

    const target = liveField();

    if (!keyEvent(target ?? keyTarget(), key, ctrl, shift)) return;

    if (ctrl && key.toLowerCase() === 'l') {
      unhandled('l', true);

      return;
    }

    if (key === 'Tab') {
      moveFocus(target, shift);

      return;
    }

    if (key === 'Escape') {
      if (target) activate(null);
      else unhandled('Escape', ctrl);

      return;
    }

    if (!target) return;

    const next = editKey(selectionOf(target), key, ctrl, shift, target instanceof realm.HTMLTextAreaElement);

    if (next) apply(target, next);
    else if (key === 'Enter') commit(target);
  }

  function keyIn(message: Record<string, any>) {
    if (input !== 'dui' || mode !== 'use') return;

    if (message.kind === 'text' && typeof message.text === 'string') typeText(message.text);
    else if (message.kind === 'key' && typeof message.key === 'string') controlKey(message.key, message.ctrl === true, message.shift === true);
  }

  function doubleClick(x: number, y: number) {
    if (!Number.isFinite(x) || !Number.isFinite(y) || win.performance.now() - trustedDouble < DOUBLE_GUARD_MS) return;

    const target = doc.elementFromPoint(x, y);

    if (!target) return;

    syntheticDouble = win.performance.now();

    target.dispatchEvent(new realm.MouseEvent('dblclick', {
      bubbles: true,
      cancelable: true,
      composed: true,
      clientX: x,
      clientY: y,
      detail: 2,
      view: win,
    }));
  }

  const shim = {
    open: false,
    index: -1,
    select: null as HTMLSelectElement | null,
    node: null as HTMLDivElement | null,
  };

  function closeShim() {
    shim.node?.remove();
    shim.open = false;
    shim.select = null;
    shim.node = null;
    shim.index = -1;
  }

  function markShim(index: number) {
    if (!shim.node) return;

    shim.index = index;

    Array.from(shim.node.children).forEach((child, position) => {
      const button = child as HTMLButtonElement;

      button.style.background = position === index ? '#17171f' : 'transparent';
      button.style.color = button.disabled ? '#52525b' : position === index ? '#C3FF00' : '#e4e4e7';
    });
  }

  function pickShim(index: number) {
    const target = shim.select;

    closeShim();

    if (!target || !target.isConnected) return;

    const option = target.options[index];

    if (!option || option.disabled || target.selectedIndex === index) return;

    target.selectedIndex = index;
    target.dispatchEvent(new realm.Event('input', { bubbles: true }));
    target.dispatchEvent(new realm.Event('change', { bubbles: true }));
  }

  function stepShim(from: number, step: number) {
    const options = shim.select ? Array.from(shim.select.options) : [];

    for (let index = from + step; index >= 0 && index < options.length; index += step) {
      if (!options[index].disabled) {
        return index;
      }
    }

    return from;
  }

  function shimKey(key: string) {
    const count = shim.select ? shim.select.options.length : 0;

    if (key === 'Escape' || key === 'Tab') closeShim();
    else if (key === 'ArrowDown') markShim(stepShim(shim.index, 1));
    else if (key === 'ArrowUp') markShim(stepShim(shim.index, -1));
    else if (key === 'Home') markShim(stepShim(-1, 1));
    else if (key === 'End') markShim(stepShim(count, -1));
    else if (key === 'Enter') pickShim(shim.index);

    return true;
  }

  function openShim(target: HTMLSelectElement) {
    const rect = target.getBoundingClientRect();
    const node = doc.createElement('div');

    node.setAttribute('role', 'listbox');
    node.dataset.osShim = '1';

    const options = Array.from(target.options);
    const wanted = Math.min(options.length * SHIM_ROW + 12, SHIM_MAX);
    const below = win.innerHeight - rect.bottom;
    const above = below < wanted && rect.top > below;

    node.style.cssText = `position:fixed;z-index:2147483647;left:${rect.left}px;${above ? `bottom:${win.innerHeight - rect.top + 4}px` : `top:${rect.bottom + 4}px`};min-width:${rect.width}px;max-height:${SHIM_MAX}px;overflow-y:auto;display:flex;flex-direction:column;padding:6px;background:#0f0f15;border:1px solid #2a2a35;border-radius:8px;box-shadow:0 18px 50px rgba(0,0,0,.5);font:13px/1.3 Poppins,system-ui,sans-serif;box-sizing:border-box`;

    options.forEach((option, index) => {
      const button = doc.createElement('button');

      button.type = 'button';
      button.textContent = option.label || option.text;
      button.disabled = option.disabled;
      button.style.cssText = 'flex:0 0 auto;min-height:34px;padding:6px 12px;text-align:left;white-space:nowrap;border:0;border-radius:6px;cursor:pointer;font:inherit;background:transparent;color:#e4e4e7';
      button.addEventListener('pointerenter', () => !option.disabled && markShim(index));
      button.addEventListener('click', () => pickShim(index));
      node.appendChild(button);
    });

    doc.body.appendChild(node);
    shim.open = true;
    shim.select = target;
    shim.node = node;
    markShim(target.selectedIndex);
  }

  function pointerDown(event: PointerEvent) {
    const target = event.target instanceof realm.Element ? event.target : null;

    if (target?.closest('[data-os-shim]')) return;

    const element = target?.closest('select');
    const reopen = element instanceof realm.HTMLSelectElement && shim.select !== element;

    closeShim();

    if (element instanceof realm.HTMLSelectElement) {
      event.preventDefault();

      if (input === 'dui') {
        activate(null);
      }

      if (reopen && !element.disabled) {
        openShim(element);
      }

      return;
    }

    if (input === 'dui') {
      activate(fieldOf(target));
    }
  }

  function activity() {
    const now = win.performance.now();

    if (now - activityAt < ACTIVITY_MS) return;

    activityAt = now;
    toHost('activity');
  }

  function nativeKey(event: KeyboardEvent) {
    activity();

    if (input !== 'native') return;

    const ctrl = event.ctrlKey || event.metaKey;

    if (shim.open && ['Escape', 'Tab', 'ArrowDown', 'ArrowUp', 'Home', 'End', 'Enter'].includes(event.key)) {
      event.preventDefault();
      shimKey(event.key);

      return;
    }

    if (ctrl && event.key.toLowerCase() === 'l') {
      event.preventDefault();
      unhandled('l', true);
    } else if (event.key === 'Escape' && !event.defaultPrevented) {
      unhandled('Escape', ctrl);
    }
  }

  function installInput() {
    listen(doc, 'pointerdown', (event: PointerEvent) => {
      activity();
      pointerDown(event);
    }, true);

    listen(doc, 'mousedown', (event: MouseEvent) => {
      if (event.target instanceof realm.Element && event.target.closest('select')) {
        event.preventDefault();
      }
    }, true);

    listen(win, 'dblclick', (event: MouseEvent) => {
      if (!event.isTrusted) return;

      if (win.performance.now() - syntheticDouble < DOUBLE_GUARD_MS) {
        event.stopImmediatePropagation();
        event.preventDefault();

        return;
      }

      trustedDouble = win.performance.now();
    }, true);

    listen(win, 'contextmenu', (event: Event) => event.preventDefault());
    listen(win, 'wheel', activity, true);
    listen(win, 'keydown', nativeKey);
    listen(win, 'resize', closeShim);
  }


  function opening(raw: Record<string, any>, given: Record<string, any>) {
    context = object(given);
    user = cleanUser(raw.user) ?? user;

    if (raw.locale && typeof raw.locale === 'object') {
      locale = raw.locale;
    }

    if (typeof raw.brand === 'string') {
      brand = raw.brand.slice(0, 40);
    }

    if (typeof raw.kind === 'string') {
      kind = raw.kind.slice(0, 16);
    }

    if (typeof raw.scale === 'number' && raw.scale > 0) {
      scale = raw.scale;
    }

    if (raw.input === 'dui' || raw.input === 'native') {
      input = raw.input;
    }

    studio = transport === 'direct' && mode === 'use' ? cleanStudio(raw.studio) : null;
    opened = true;

    if (helloTimer) {
      clearTimeout(helloTimer);
    }

    helloTimer = null;
    doc.documentElement.dataset.osMode = mode || 'page';

    each(handlers.open, {
      context,
      intent: raw.intent && typeof raw.intent === 'object' ? raw.intent : null,
      user,
      kind,
      mode,
      scale,
      locale,
      brand,
      studio,
    });

    if (raw.intent && typeof raw.intent === 'object') {
      each(handlers.intent, raw.intent);
    }

    if (!options.manualReady) {
      app.ready();
    }
  }

  function own(message: any) {
    each(handlers.message, message);

    if (message && typeof message === 'object' && typeof message.action === 'string') {
      const set = handlers.action.get(message.action);

      if (set) {
        for (const handler of [...set]) {
          handler(message.data, message);
        }
      }
    }
  }

  function answer(id: unknown, data: unknown) {
    const key = String(id);
    const waiting = replies.get(key);

    if (!waiting) return;

    replies.delete(key);
    clearTimeout(waiting.timer);
    waiting.resolve(data ?? { ok: false, reason: 'no_response' });
  }

  function fromHost(message: Record<string, any>) {
    switch (message.type) {
      case 'os:open':
        if (typeof message.token !== 'string') return;

        token = message.token;

        if (message.protocol !== PROTOCOL) {
          console.warn('[evolent os app] the host speaks protocol', message.protocol);
        }

        opening(message, message.context);

        return;
      case 'os:intent':
        each(handlers.intent, object(message.intent));

        return;
      case 'os:visibility':
        each(handlers.visibility, message.visible === true);

        return;
      case 'os:key':
        keyIn(message);

        return;
      case 'os:dblclick':
        doubleClick(Number(message.x), Number(message.y));

        return;
      case 'os:state': {
        const state = cleanFlatState(message.state);

        if (state) {
          each(handlers.state, state);
        }

        return;
      }
      case 'os:close':
        closeShim();
        activate(null);
        each(handlers.close, typeof message.reason === 'string' ? message.reason : 'closed');

        return;
      case 'os:reply':
        answer(message.id, message.data);

        return;
    }
  }

  function frameMessage(event: MessageEvent) {
    if (event.source !== win.parent || event.origin !== hostOrigin) return;

    const message = event.data;

    if (!message || typeof message !== 'object') return;

    if (message.__os === 1) {
      if (!opened && message.type !== 'os:open') return;
      if (opened && message.token !== token) return;

      fromHost(message);

      return;
    }

    if (opened) {
      own(message);
    }
  }

  function directMessage(event: MessageEvent) {
    if (event.source && event.source !== win) return;

    const message = event.data;

    if (!message || typeof message !== 'object') return;
    if (secret && message.__s !== secret) return;

    if (DIRECT_TYPES.has(message.type)) {
      switch (message.type) {
        case 'init':
          if (message.locale && typeof message.locale === 'object') {
            locale = message.locale;
          }

          break;
        case 'open': {
          const given = object(message.app);

          token = typeof given.token === 'string' ? given.token : '';
          opening(message, given.context);
          break;
        }
        case 'watch':
          opening(message, object(object(message.extra).app).data);
          break;
        case 'state': {
          const state = cleanFlatState(message.state);

          if (state) {
            each(handlers.state, state);
          }

          break;
        }
        case 'close':
          closeShim();
          activate(null);
          each(handlers.close, 'closed');
          break;
        case 'deviceKey':
          keyIn(message);

          return;
        case 'deviceDblClick':
          doubleClick(Number(message.x), Number(message.y));

          return;
        case 'osReply':
          answer(message.id, message.data);

          return;
      }
    }

    own(message);
  }

  function hello(attempt = 0) {
    if (opened || transport !== 'frame') return;

    win.parent.postMessage({ __os: 1, type: 'hello', protocol: PROTOCOL, sdk: SDK_VERSION, app: appId }, hostOrigin);

    if (attempt + 1 < HELLO_TRIES) {
      helloTimer = setTimeout(() => hello(attempt + 1), HELLO_MS);
    }
  }

  function deviceReady(attempt = 0) {
    toGame('device:ready', { width: win.innerWidth, height: win.innerHeight }).then((result) => {
      if (result === null && attempt + 1 < READY_TRIES) {
        setTimeout(() => deviceReady(attempt + 1), READY_MS);
      }
    });
  }

  function flushState() {
    publishTimer = null;

    if (!pendingState) return;

    const state = pendingState;

    pendingState = null;

    if (transport === 'frame') toHost('publish', { state });
    else toGame('device:state', { state });

    publishTimer = setTimeout(flushState, PUBLISH_MS);
  }

  function relayPost(name: string, data: Record<string, unknown>, timeout: number) {
    return new Promise<any>((resolve) => {
      const id = 'p' + ++replyId;
      const timer = setTimeout(() => answer(id, { ok: false, reason: 'no_response' }), timeout);

      replies.set(id, { resolve, timer });

      if (transport === 'frame') toHost('post', { id, name, data: JSON.parse(JSON.stringify(data)) });
      else toGame('os:post', { id, name, data, app: appId });
    });
  }

  async function postDirect(name: string, body: Record<string, unknown>, timeout: number) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);

    try {
      const response = await send(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      const text = await response.text();

      return text ? JSON.parse(text) : {};
    } finally {
      clearTimeout(timer);
    }
  }

  const app: OsApp = {
    get hosted() {
      return transport !== 'none';
    },
    get mode() {
      return mode;
    },
    get kind() {
      return kind;
    },
    get app() {
      return appId;
    },
    get transport() {
      return transport;
    },
    get input() {
      return input;
    },
    get token() {
      return token;
    },
    get context() {
      return context;
    },
    get user() {
      return user;
    },
    get locale() {
      return locale;
    },
    get brand() {
      return brand;
    },
    get scale() {
      return scale;
    },
    get opened() {
      return opened;
    },
    get relayed() {
      return relay;
    },
    get studio() {
      return studio;
    },
    on(action, handler) {
      let set = handlers.action.get(action);

      if (!set) {
        handlers.action.set(action, (set = new Set()));
      }

      return add(set, handler);
    },
    onMessage: (handler) => add(handlers.message, handler),
    onOpen(handler) {
      const stop = add(handlers.open, handler);

      if (opened) {
        handler({ context, intent: null, user, kind, mode, scale, locale, brand, studio });
      }

      return stop;
    },
    onClose: (handler) => add(handlers.close, handler),
    onIntent: (handler) => add(handlers.intent, handler),
    onVisibility: (handler) => add(handlers.visibility, handler),
    onState: (handler) => add(handlers.state, handler),
    async post(name, data = {}, postOptions = {}) {
      if (!/^[\w:.-]{1,64}$/.test(name)) {
        return { ok: false, reason: 'bad_name' } as any;
      }

      if (mode === 'watch' && !postOptions.readOnly) {
        return { ok: false, reason: 'watch_mode' } as any;
      }

      const timeout = postOptions.timeout ?? POST_MS;
      const body = token ? { ...data, __os: token } : { ...data };

      if (transport === 'none' || !relay) {
        try {
          return await postDirect(name, body, timeout);
        } catch (error) {
          if (transport === 'none' || (error as Error)?.name === 'AbortError') {
            return { ok: false, reason: 'no_response' } as any;
          }

          relay = true;
        }
      }

      return relayPost(name, body, timeout);
    },
    publish(state) {
      if (mode !== 'use' || transport === 'none') return false;

      const clean = cleanFlatState(state);

      if (!clean) {
        console.warn('[evolent os app] publish takes at most 16 flat keys and 2 KB');

        return false;
      }

      pendingState = clean;

      if (!publishTimer) {
        flushState();
      }

      return true;
    },
    close() {
      if (mode !== 'use') return;

      if (transport === 'frame') toHost('close');
      else toGame('device:close');
    },
    leave() {
      if (mode !== 'use') return;

      if (transport === 'frame') toHost('leave');
      else toGame('device:close');
    },
    notify(notice) {
      const clean = cleanNotice(notice);

      if (!clean || mode !== 'use' || transport !== 'frame') return false;

      toHost('notify', { notice: clean });

      return true;
    },
    recent(entry) {
      const clean = cleanRecent(entry);

      if (!clean || mode !== 'use' || transport !== 'frame') return false;

      toHost('recent', { entry: clean });

      return true;
    },
    badge(count) {
      if (mode !== 'use') return;

      toHost('badge', { count: Math.max(0, Math.min(999, Math.floor(Number(count) || 0))) });
    },
    privatePointer(on) {
      if (mode !== 'use') return;

      if (transport === 'frame') toHost('privatePointer', { on: on === true });
      else toGame('device:state', { privatePointer: on === true });
    },
    studioSend(action) {
      if (mode !== 'use' || transport !== 'direct' || !studio || !action || typeof action.act !== 'string') return false;

      toGame('device:studio', { ...action });

      return true;
    },
    ready() {
      if (readySent || !opened) return;

      readySent = true;
      toHost('ready');
    },
    disconnect() {
      for (const stop of off.splice(0)) {
        stop();
      }

      if (helloTimer) {
        clearTimeout(helloTimer);
      }

      if (publishTimer) {
        clearTimeout(publishTimer);
      }

      for (const [id] of replies) {
        answer(id, { ok: false, reason: 'disconnected' });
      }

      closeShim();
      instance = null;
    },
  };

  if (transport === 'frame') {
    listen(win, 'message', frameMessage);
    installInput();
    hello();
  } else if (transport === 'direct') {
    listen(win, 'message', directMessage);
    installInput();
    win.requestAnimationFrame(() => win.requestAnimationFrame(() => deviceReady()));
  }

  instance = app;

  return app;
}
