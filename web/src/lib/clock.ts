const MAX_OFFSET = 14 * 3600;

export interface Clock {
  now: number;
  offset: number;
}

export function cleanClock(value: unknown): Clock | null {
  if (!value || typeof value !== 'object') return null;

  const { now, offset } = value as Record<string, unknown>;

  if (typeof now !== 'number' || !Number.isFinite(now) || now <= 0) return null;

  const shift = typeof offset === 'number' && Number.isFinite(offset) && Math.abs(offset) <= MAX_OFFSET
    ? Math.round(offset)
    : 0;

  return { now, offset: shift };
}

export interface WallParts {
  hours: number;
  minutes: number;
  seconds: number;
  weekday: number;
  day: number;
  month: number;
}

export function wallParts(ms: number): WallParts {
  const date = new Date(ms);

  return {
    hours: date.getUTCHours(),
    minutes: date.getUTCMinutes(),
    seconds: date.getUTCSeconds(),
    weekday: date.getUTCDay(),
    day: date.getUTCDate(),
    month: date.getUTCMonth(),
  };
}

export function untilNextMinute(ms: number) {
  return 60000 - (((ms % 60000) + 60000) % 60000);
}

const pad = (value: number) => String(value).padStart(2, '0');

export function clockText(parts: WallParts, h24: boolean, seconds = false) {
  const tail = seconds ? ':' + pad(parts.seconds) : '';

  if (h24) {
    return pad(parts.hours) + ':' + pad(parts.minutes) + tail;
  }

  return (parts.hours % 12 || 12) + ':' + pad(parts.minutes) + tail + (parts.hours < 12 ? ' AM' : ' PM');
}

export function initials(name: string) {
  return (
    name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => Array.from(part)[0].toLocaleUpperCase())
      .join('') || 'U'
  );
}
