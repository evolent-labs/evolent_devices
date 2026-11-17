import {
  clamp,
  clipOf,
  clipsFor,
  hit,
  levelJitter,
  paired,
  planMessage,
  releaseWait,
  sessionSound,
  type Hit,
  type SessionSound,
  type SoundName,
} from './soundplan';
import type { NoticeSound } from './noticesound';

const FILES: Record<string, string> = Object.fromEntries(
  Object.entries(import.meta.glob<string>('../sounds/*.{wav,ogg}', { eager: true, query: '?url', import: 'default' }))
    .map(([path, url]) => [path.slice(path.lastIndexOf('/') + 1, -4), url]),
);

let context: AudioContext | null = null;
const buffers = new Map<string, Promise<AudioBuffer | null>>();
const held = new Map<SoundName, Hit & { at: number }>();
const lastVariant = new Map<SoundName, number>();

function audio() {
  context ??= new AudioContext();

  if (context.state === 'suspended') {
    context.resume().catch(() => null);
  }

  return context;
}

function load(clip: string) {
  let pending = buffers.get(clip);

  if (!pending) {
    const url = FILES[clip];

    pending = url
      ? fetch(url)
        .then((response) => response.arrayBuffer())
        .then((data) => audio().decodeAudioData(data))
        .catch(() => null)
      : Promise.resolve(null);

    buffers.set(clip, pending);
  }

  return pending;
}

async function start(clip: string, gain: number, pan: number, delayMs: number, rate = 1) {
  const due = performance.now() + delayMs;
  const buffer = await load(clip);

  if (!buffer || gain <= 0) return;

  const output = audio();
  const source = output.createBufferSource();
  const level = output.createGain();
  const side = output.createStereoPanner();

  source.buffer = buffer;
  source.playbackRate.value = rate;
  level.gain.value = gain;
  side.pan.value = pan;
  source.connect(level).connect(side).connect(output.destination);
  source.start(output.currentTime + Math.max(0, due - performance.now()) / 1000);
}

export function startSession(raw: unknown): SessionSound | null {
  const session = sessionSound(raw);

  held.clear();

  if (!session) return null;

  for (const name of session.click === 'tap' ? ['tap'] as const : ['click', 'rclick'] as const) {
    clipsFor(name).forEach(load);
  }

  return session;
}

export function press(name: SoundName, gain: number) {
  const next = hit(name, Math.random, lastVariant.get(name));
  const level = clamp(gain, 0, 1, 0);

  lastVariant.set(name, next.variant);
  start(clipOf(name, 'down', next.variant), level * next.level, 0, 0, next.rate);

  if (paired(name)) {
    held.set(name, { ...next, at: performance.now() });
  }
}

export function release(name: SoundName, gain: number) {
  const pressed = held.get(name);

  if (!pressed) return;

  held.delete(name);
  start(clipOf(name, 'up', pressed.variant), clamp(gain, 0, 1, 0) * levelJitter(), 0, releaseWait(performance.now() - pressed.at), pressed.rate);
}

export function playMessage(message: Record<string, unknown>) {
  for (const entry of planMessage(message)) {
    start(entry.clip, entry.gain, entry.pan, entry.delayMs, entry.rate);
  }
}

export function playNotice(plan: NoticeSound[], gain: number) {
  const level = clamp(gain, 0, 1, 0);

  if (level <= 0) return;

  for (const entry of plan) {
    start(entry.clip, level, 0, entry.delayMs, entry.rate);
  }
}
