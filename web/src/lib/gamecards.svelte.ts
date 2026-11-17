import { GROW_MS } from './island';
import { lastMainOf, noticeSounds } from './noticesound';
import { cardsFrom, cornerOf, OUT_MS, overflow, type Corner, type GameCard } from './notices';
import { playNotice } from './sound';

export const cards = $state({
  list: [] as GameCard[],
  corner: 'top_right' as Corner,
  lead: 0,
  grown: 0,
});

const timers = new Map<number, ReturnType<typeof setTimeout>[]>();
let growTimer: ReturnType<typeof setTimeout> | undefined;
let serial = 0;
let lastMain = -Infinity;

function forget(id: number) {
  for (const timer of timers.get(id) ?? []) {
    clearTimeout(timer);
  }

  timers.delete(id);
}

function remove(id: number) {
  forget(id);
  cards.list = cards.list.filter((card) => card.id !== id);

  if (cards.lead === id) {
    cards.lead = 0;
    cards.grown = 0;
  }
}

function fade(id: number) {
  const card = cards.list.find((entry) => entry.id === id);

  if (!card || card.out) return;

  forget(id);
  card.out = true;
  timers.set(id, [setTimeout(() => remove(id), OUT_MS)]);
}

export function showCards(message: Record<string, unknown>) {
  const fresh = cardsFrom(message, () => ++serial);

  if (!fresh.length) return;

  const head = fresh.find((card) => card.mode !== 'more');
  const older = fresh.some((card) => card.mode === 'more') ? cards.list.filter((card) => card.mode === 'more' && !card.out) : [];

  cards.corner = cornerOf(message.position);
  cards.list = [...fresh, ...cards.list].sort((a, b) => Number(a.mode === 'more') - Number(b.mode === 'more'));

  for (const card of fresh) {
    timers.set(card.id, [setTimeout(() => fade(card.id), card.ms)]);
  }

  for (const card of older) {
    fade(card.id);
  }

  for (const id of overflow(cards.list)) {
    fade(id);
  }

  if (Number(message.gain) > 0) {
    const now = performance.now();
    const plan = noticeSounds(fresh, now, lastMain);

    lastMain = lastMainOf(plan, now, lastMain);
    playNotice(plan, Number(message.gain));
  }

  if (head) {
    clearTimeout(growTimer);
    cards.lead = head.id;
    cards.grown = 0;
    growTimer = setTimeout(() => (cards.grown = head.id), head.mode === 'pocket' ? GROW_MS.pocket : GROW_MS.popup);
  }
}
