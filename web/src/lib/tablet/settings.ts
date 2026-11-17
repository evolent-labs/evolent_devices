import { wallId, wallShape } from '../wallIds.ts';
import type { TabletSettings } from './types';

export const SLEEP_CHOICES = [-1, 0, 1, 2, 5, 10];
export const LOCK_CHOICES = [0, 1, 2, 5, 10, 30];

export const DEFAULT_SET: TabletSettings = {
  wall: '',
  clock24: true,
  seconds: false,
  date: 'dm',
  still: false,
  dnd: false,
  sound: true,
  wifi: true,
  bright: 100,
  sleep: -1,
  lock: 0,
  muted: {},
};

const FLAGS = ['clock24', 'seconds', 'still', 'dnd', 'sound', 'wifi'] as const;

export function cleanTabletSettings(raw: unknown): TabletSettings {
  const saved = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {};
  const set = { ...DEFAULT_SET, ...saved } as TabletSettings & Record<string, unknown>;

  set.bright = Math.max(30, Math.min(100, Math.round(Number(set.bright) || 100)));

  const wall = set.wall;

  set.wall = wall === '' ? '' : wallShape(wall) ? (wallId(wall) ?? wall) : DEFAULT_SET.wall;

  if (!('sleep' in saved) && set.wall === 'evolent') {
    set.wall = '';
  }

  for (const key of FLAGS) {
    if (typeof set[key] !== 'boolean') set[key] = DEFAULT_SET[key];
  }

  set.date = set.date === 'md' ? 'md' : 'dm';
  set.sleep = SLEEP_CHOICES.includes(set.sleep) ? set.sleep : DEFAULT_SET.sleep;
  set.lock = LOCK_CHOICES.includes(set.lock) ? set.lock : DEFAULT_SET.lock;
  set.muted = set.muted && typeof set.muted === 'object' && !Array.isArray(set.muted) ? { ...set.muted } : {};
  delete set.night;

  return set;
}
