import type { GameCard } from './notices';

export type NoticeClip = 'notice' | 'notice_stack' | 'notice_pocket';

export interface NoticeSound {
  clip: NoticeClip;
  delayMs: number;
  rate: number;
}

export const NOTICE_CLIPS: NoticeClip[] = ['notice', 'notice_stack', 'notice_pocket'];
export const POP_MS = 90;
export const SLOT_MS = 110;
export const SHAKE_MS = 560;
export const BUZZ_LEAD_MS = 470;
export const QUIET_MS = 1000;
export const STACK_RATES = [1, 2 ** (2 / 12), 2 ** (4 / 12)];

export function noticeSounds(cards: GameCard[], now: number, lastMain: number): NoticeSound[] {
  const shown = cards.filter((card) => card.mode !== 'more');

  if (!shown.length) return [];

  if (shown[0].mode === 'pocket') return [{ clip: 'notice_pocket', delayMs: SHAKE_MS - BUZZ_LEAD_MS, rate: 1 }];

  let stacked = 0;

  return shown.map((card) => {
    const delayMs = POP_MS + card.slot * SLOT_MS;

    if (card.slot === 0 && now + delayMs - lastMain >= QUIET_MS) return { clip: 'notice', delayMs, rate: 1 };

    return { clip: 'notice_stack', delayMs, rate: STACK_RATES[Math.min(stacked++, STACK_RATES.length - 1)] };
  });
}

export function lastMainOf(plan: NoticeSound[], now: number, lastMain: number) {
  const main = plan.find((entry) => entry.clip === 'notice');

  return main ? now + main.delayMs : lastMain;
}
