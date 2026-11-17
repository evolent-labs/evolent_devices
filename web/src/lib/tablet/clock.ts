import { untilNextMinute, type Clock } from '../clock.ts';

export { cleanClock, clockText, initials, wallParts, type WallParts } from '../clock.ts';

export function clockShift(clock: Clock | null, nowMs = Date.now()) {
  if (clock) {
    return (clock.now + clock.offset) * 1000 - nowMs;
  }

  return -new Date(nowMs).getTimezoneOffset() * 60000;
}

export function untilChange(wall: number, seconds: boolean, ages: number[]) {
  if (seconds) {
    return 1000 - (((wall % 1000) + 1000) % 1000);
  }

  return Math.min(untilNextMinute(wall), ...ages.filter(Number.isFinite).map(untilNextMinute));
}
