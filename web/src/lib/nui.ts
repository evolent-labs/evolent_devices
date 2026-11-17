declare global {
  function GetParentResourceName(): string;
}

const host = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;

export const browserPreview = !host;

export function previewParam(key: string) {
  if (!import.meta.env.DEV || !browserPreview) {
    return '';
  }

  return new URLSearchParams(location.search).get(key) ?? '';
}
export const resource = host || 'evolent_devices';

export interface Result<T = any> {
  ok: boolean;
  reason?: string;
  data?: T;
}

let token = '';
let ended: ((reason: string) => void) | null = null;
const ENDING = new Set(['bad_token', 'not_admin', 'panel_closed']);

export function setToken(value: string) {
  token = value;
}

export function currentToken() {
  return token;
}

export function onSessionEnd(handler: (reason: string) => void) {
  ended = handler;
}

export async function post<T = any>(name: string, data: Record<string, unknown> = {}, timeout = 15000): Promise<T> {
  if (browserPreview) {
    if (import.meta.env.DEV) {
      return (await import('./preview')).previewPost(name, data) as T;
    }

    return { ok: false, reason: 'no_response' } as T;
  }

  const controller = new AbortController();
  const timer = timeout > 0 ? setTimeout(() => controller.abort(), timeout) : 0;

  try {
    const response = await fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
      signal: controller.signal,
    });

    return (await response.json()) as T;
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

export async function call<T = any>(name: string, ...args: unknown[]): Promise<Result<T>> {
  let result: Result<T>;

  if (import.meta.env.DEV && browserPreview) {
    result = (await import('./preview')).previewCall(name, args) as Result<T>;
  } else {
    try {
      const answer = await post<Result<T>>('call', {
        name,
        args: args.map((value) => (value === undefined ? null : value)),
        __t: token,
      });

      result = answer && typeof answer === 'object' ? answer : { ok: false, reason: 'no_response' };
    } catch {
      result = { ok: false, reason: 'no_response' };
    }
  }

  if (!result.ok && ENDING.has(String(result.reason)) && ended) {
    ended(String(result.reason));
  }

  return result;
}
