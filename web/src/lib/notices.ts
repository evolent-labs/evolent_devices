import { iconOf, type IconSpec } from './icon.ts';

export { iconOf };

export type CardMode = 'popup' | 'pocket' | 'more';
export type Corner = 'top_right' | 'top_center' | 'top_left' | 'bottom_right';

export type CardIcon = IconSpec;

export interface GameCard {
  id: number;
  mode: CardMode;
  app: string;
  label: string;
  icon?: CardIcon;
  title: string;
  body: string;
  more: number;
  ms: number;
  slot: number;
  out: boolean;
}

export const CORNERS: Corner[] = ['top_right', 'top_center', 'top_left', 'bottom_right'];
export const STACK_MAX = 4;
export const OUT_MS = 600;
export const STAGGER_MS = 450;
export const SECONDS = { low: 3, high: 20, base: 6 };

const ID = /^[a-z][a-z0-9_]{1,31}$/;
const CONTROL = /[\u0000-\u001f\u007f]/g;

const text = (value: unknown, max: number) => (typeof value === 'string' ? value.replace(CONTROL, ' ').trim().slice(0, max) : '');

export const cornerOf = (value: unknown): Corner => (CORNERS.includes(value as Corner) ? (value as Corner) : 'top_right');

export function secondsOf(value: unknown) {
  const seconds = Math.round(Number(value));

  return Number.isFinite(seconds) ? Math.min(SECONDS.high, Math.max(SECONDS.low, seconds)) : SECONDS.base;
}

export function cardsFrom(message: unknown, next: () => number): GameCard[] {
  const raw = message && typeof message === 'object' ? (message as Record<string, unknown>) : {};

  if (!Array.isArray(raw.notices)) return [];

  const mode: CardMode = raw.mode === 'pocket' ? 'pocket' : 'popup';
  const ms = secondsOf(raw.seconds) * 1000;
  const cards: GameCard[] = [];

  for (const entry of raw.notices.slice(0, STACK_MAX)) {
    const notice = entry && typeof entry === 'object' ? (entry as Record<string, unknown>) : null;
    const title = notice ? text(notice.title, 80) : '';

    if (!notice || typeof notice.app !== 'string' || !ID.test(notice.app) || !title) continue;

    cards.push({
      id: next(),
      mode,
      app: notice.app,
      label: text(notice.label, 32) || notice.app,
      icon: iconOf(notice.icon),
      title,
      body: mode === 'pocket' ? '' : text(notice.body, 240),
      more: 0,
      ms: ms + cards.length * STAGGER_MS,
      slot: cards.length,
      out: false,
    });
  }

  const more = Math.floor(Number(raw.more));

  if (cards.length && Number.isFinite(more) && more > 0) {
    cards.push({ id: next(), mode: 'more', app: '', label: '', title: '', body: '', more: Math.min(999, more), ms: ms + cards.length * STAGGER_MS, slot: cards.length, out: false });
  }

  return cards;
}

export function overflow(list: GameCard[], max = STACK_MAX) {
  return list.filter((card) => !card.out && card.mode !== 'more').slice(max).map((card) => card.id);
}
