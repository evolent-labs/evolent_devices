export type SoundName = 'click' | 'rclick' | 'tap' | 'notice';
export type Part = 'down' | 'up';

export interface SessionSound {
  volume: number;
  click: 'click' | 'tap';
}

export interface Hit {
  name: SoundName;
  variant: number;
  rate: number;
  level: number;
}

export interface Planned {
  clip: string;
  gain: number;
  pan: number;
  delayMs: number;
  rate: number;
}

export const SOUND_NAMES: SoundName[] = ['click', 'rclick', 'tap', 'notice'];
export const VARIANTS = 4;
export const PITCH = 0.03;
export const LEVEL_DB = 1.5;
export const RELEASE_MS = [60, 120] as const;
export const MIN_RELEASE_MS = 30;
export const MAX_COUNT = 8;
export const MAX_SPREAD_MS = 1000;

const isSound = (name: string): name is SoundName => (SOUND_NAMES as string[]).includes(name);

export const paired = (name: SoundName) => name === 'click' || name === 'rclick';

export const clamp = (value: number, low: number, high: number, fallback: number) => (Number.isFinite(value)
  ? Math.min(high, Math.max(low, value))
  : fallback);

export const clipOf = (name: SoundName, part: Part, variant: number) => (paired(name) ? `${name}_${part}_${variant + 1}` : name);

export const CLIP_NAMES = SOUND_NAMES.flatMap((name) => (paired(name)
  ? (['down', 'up'] as Part[]).flatMap((part) => Array.from({ length: VARIANTS }, (_, variant) => clipOf(name, part, variant)))
  : [name]));

export const clipsFor = (name: SoundName) => CLIP_NAMES.filter((clip) => clip === name || clip.startsWith(`${name}_`));

const spread = (amount: number, random: () => number) => (random() * 2 - 1) * amount;

export const levelJitter = (random: () => number = Math.random) => 10 ** (spread(LEVEL_DB, random) / 20);

export function hit(name: SoundName, random: () => number = Math.random, last = -1): Hit {
  if (!paired(name) && name !== 'tap') return { name, variant: 0, rate: 1, level: 1 };

  let variant = paired(name) ? Math.min(VARIANTS - 1, Math.floor(random() * VARIANTS)) : 0;

  if (paired(name) && variant === last) {
    variant = (variant + 1) % VARIANTS;
  }

  return { name, variant, rate: 1 + spread(PITCH, random), level: levelJitter(random) };
}

export const releaseGap = (random: () => number = Math.random) => Math.round(RELEASE_MS[0] + random() * (RELEASE_MS[1] - RELEASE_MS[0]));

export const releaseWait = (heldMs: number) => Math.max(0, Math.round(MIN_RELEASE_MS - (Number.isFinite(heldMs) ? heldMs : 0)));

export function delays(count: number, spreadMs: number, random: () => number = Math.random) {
  const list: number[] = [];

  for (let index = 0; index < count; index++) {
    list.push(Math.round((spreadMs * (index + random() * 0.6)) / count));
  }

  return list;
}

export function sessionSound(raw: unknown): SessionSound | null {
  if (!raw || typeof raw !== 'object') return null;

  const value = raw as Record<string, unknown>;
  const volume = clamp(Number(value.volume), 0, 1, 0);

  if (value.on !== true || volume <= 0) return null;

  return { volume, click: value.click === 'tap' ? 'tap' : 'click' };
}

export function planMessage(message: Record<string, unknown>, random: () => number = Math.random): Planned[] {
  const sounds = message.sounds;

  if (!sounds || typeof sounds !== 'object') return [];

  const gain = clamp(Number(message.gain), 0, 1, 0);
  const pan = clamp(Number(message.pan), -1, 1, 0);
  const spreadMs = clamp(Number(message.spread), 0, MAX_SPREAD_MS, 0);

  if (gain <= 0) return [];

  const plan: Planned[] = [];

  for (const [name, raw] of Object.entries(sounds)) {
    if (!isSound(name)) continue;

    const count = clamp(Math.floor(Number(raw)), 0, MAX_COUNT, 0);

    for (const delayMs of delays(count, spreadMs, random)) {
      const press = hit(name, random);

      plan.push({ clip: clipOf(name, 'down', press.variant), gain: gain * press.level, pan, delayMs, rate: press.rate });

      if (paired(name)) {
        plan.push({ clip: clipOf(name, 'up', press.variant), gain: gain * levelJitter(random), pan, delayMs: delayMs + releaseGap(random), rate: press.rate });
      }
    }
  }

  return plan;
}
