export interface SignalSource {
  id?: number;
  x: number;
  y: number;
  radius: number;
  strength: number;
  on: boolean;
}

export const MAX_BARS = 4;

export function quality(antenna: SignalSource, point: { x: number; y: number }) {
  if (!antenna.on || !(antenna.radius > 0)) {
    return 0;
  }

  const dx = point.x - antenna.x;
  const dy = point.y - antenna.y;
  const share = (dx * dx + dy * dy) / (antenna.radius * antenna.radius);

  return share >= 1 ? 0 : antenna.strength * (1 - share);
}

export function barsFor(value: number, thresholds: number[]) {
  let bars = 0;

  for (let index = 0; index < MAX_BARS; index++) {
    if (value >= (thresholds[index] ?? Infinity)) {
      bars = index + 1;
    }
  }

  return bars;
}

export function reading(antennas: SignalSource[], point: { x: number; y: number }, space: string, thresholds: number[], homeLoss: number) {
  let best = 0;
  let from: number | undefined;

  for (const antenna of antennas) {
    const value = quality(antenna, point);

    if (value > best) {
      best = value;
      from = antenna.id;
    }
  }

  let bars = barsFor(best, thresholds);

  if (space.startsWith('p')) {
    bars = Math.max(0, bars - homeLoss);
  }

  return { bars, quality: Math.round(best), antenna: from };
}
