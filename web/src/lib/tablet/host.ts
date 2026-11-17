import { browserPreview, post } from '$lib/nui';
import type { Answer } from './types';

let token = '';

export function setTabletToken(value: string) {
  token = value;
}

async function send(action: string, data: Record<string, unknown> = {}): Promise<Answer> {
  if (browserPreview) {
    if (import.meta.env.DEV) {
      return (await import('./preview')).previewTablet(action, data);
    }

    return { ok: false, reason: 'no_response' };
  }

  try {
    const answer = await post<Answer>('tablet', { ...data, action, __t: token });

    return answer && typeof answer === 'object' ? answer : { ok: false, reason: 'no_response' };
  } catch {
    return { ok: false, reason: 'no_response' };
  }
}

const quiet = (action: string, data?: Record<string, unknown>) => {
  send(action, data).catch(() => null);
};

const ACTIVITY_MS = 500;
let lastActivity = 0;

export const host = {
  os: (name: string, a?: unknown, b?: unknown) => send('os', { name, a, b }),
  sleep: (asleep: boolean) => quiet('sleep', { asleep }),
  openApp: (app: string, intent?: Record<string, unknown> | null) => send(
    'openApp',
    intent ? { app, intent } : { app }
  ),
  closeApp: (app: string) => quiet('closeApp', { app }),
  phase: (phase: 'off' | 'lock' | 'home') => quiet('phase', { phase }),
  colour: (colour: number) => send('colour', { colour }),
  game: (patch: { popup?: boolean; sound?: boolean }) => send('game', patch),
  appPost: (app: string, id: unknown, name: string, data: unknown) => quiet('appPost', { app, id, name, data }),
  appVisible: (app: string, visible: boolean) => quiet('appVisible', { app, visible }),
  close: () => quiet('close'),
  activity() {
    const now = Date.now();

    if (now - lastActivity < ACTIVITY_MS) return;

    lastActivity = now;
    quiet('activity');
  },
};
