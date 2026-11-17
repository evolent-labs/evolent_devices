import { page } from './params';

let preview: ((name: string, data: Record<string, unknown>) => unknown) | null = null;

export function onPreview(handler: (name: string, data: Record<string, unknown>) => unknown) {
  preview = handler;
}

export function toGame(name: string, data: Record<string, unknown> = {}) {
  if (page.preview) {
    return Promise.resolve(preview?.(name, data) ?? null);
  }

  return fetch(`https://${page.resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ ...data, browser: page.browser, s: page.secret }),
  })
    .then((response) => response.json())
    .catch(() => null);
}

export const fromHost = (message: Record<string, unknown>) => page.preview || (page.secret.length >= 16 && message.__s === page.secret);

const READY_TRIES = 5;
const READY_MS = 500;

export function ready(attempt = 0) {
  if (page.preview) return;

  toGame('device:ready', { width: innerWidth, height: innerHeight }).then((answer) => {
    if (answer === null && attempt + 1 < READY_TRIES) {
      setTimeout(() => ready(attempt + 1), READY_MS);
    }
  });
}

export const leaveDevice = () => toGame('device:close');

export const openApp = (app: string, intent?: Record<string, unknown> | null) => toGame(
  'os:app',
  intent ? { act: 'open', app, intent } : { act: 'open', app }
);

export const closeApp = (app: string) => toGame('os:app', { act: 'close', app });
export const appVisible = (app: string, visible: boolean) => toGame('os:app', { act: 'visible', app, visible });

export const relayPost = (app: string, id: unknown, name: unknown, data: unknown) => toGame('os:post', {
  app,
  id,
  name,
  data,
});

let pending: Record<string, unknown> | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;
const STATE_MS = 500;

function flush() {
  timer = null;

  if (!pending) return;

  const state = pending;

  pending = null;
  toGame('device:state', { state });
  timer = setTimeout(flush, STATE_MS);
}

export function shareState(state: Record<string, unknown>) {
  if (page.mode !== 'use') return;

  pending = state;

  if (!timer) {
    flush();
  }
}

export interface OsResult<T> {
  ok: boolean;
  data?: T;
  reason?: string;
}

export function osCall<T>(name: string, a?: unknown, b?: unknown): Promise<OsResult<T>> {
  if (page.mode !== 'use') {
    return Promise.resolve({ ok: false, reason: 'device_closed' });
  }

  return toGame('os:call', { name, a, b }).then((answer) => (answer && typeof answer === 'object' && typeof (answer as OsResult<T>).ok === 'boolean'
    ? (answer as OsResult<T>)
    : { ok: false, reason: 'no_response' }));
}

export const savePrefs = (prefs: Record<string, unknown>) => page.mode === 'use' && toGame('os:prefs', { prefs });

export const playSound = (name: string) => page.mode === 'use' && toGame('device:sound', { sound: name });
export const reportEditing = (editing: boolean) => page.mode === 'use' && toGame('device:state', { editing });
export const privatePointer = (on: boolean) => page.mode === 'use' && toGame('device:state', { privatePointer: on });
