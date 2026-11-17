export const DEFAULT_WALL = 'evolent';

export const WALLS_MAX = 24;

export const IDLE_KINDS = ['laptop', 'pc', 'terminal'] as const;

export type IdleKind = (typeof IDLE_KINDS)[number];
export type IdlePictures = Record<IdleKind, string>;

export const SCREEN_SIZES: Record<IdleKind, { width: number; height: number }> = {
  laptop: { width: 1440, height: 900 },
  pc: { width: 1920, height: 1080 },
  terminal: { width: 1920, height: 720 },
};

export interface OwnWall {
  id: string;
  name: string;
  src: string;
}

const ID = /^[a-z][a-z0-9_]{0,31}$/;
const FILE = /^web\/build\/wallpapers\/[\w-]+\.(webp|jpe?g|png)$/i;

export const wallShape = (value: unknown): value is string => typeof value === 'string' && ID.test(value);

export function cleanWalls(raw: unknown): OwnWall[] {
  const list: OwnWall[] = [];

  if (!Array.isArray(raw)) return list;

  const seen = new Set([DEFAULT_WALL]);

  for (const entry of raw) {
    if (list.length >= WALLS_MAX) break;
    if (!entry || typeof entry !== 'object') continue;

    const { id, name, file } = entry as Record<string, unknown>;

    if (!wallShape(id) || seen.has(id) || typeof file !== 'string' || !FILE.test(file)) continue;

    seen.add(id);
    list.push({ id, name: typeof name === 'string' && name.trim() ? name.trim().slice(0, 40) : id, src: file.slice('web/build/'.length) });
  }

  return list;
}

export function wallId(value: unknown, own: readonly OwnWall[] = []): string | null {
  if (typeof value !== 'string') return null;

  return value === DEFAULT_WALL || own.some((entry) => entry.id === value) ? value : null;
}

export function wallOr(value: unknown, own: readonly OwnWall[] = []): string {
  return wallId(value, own) ?? (wallShape(value) ? DEFAULT_WALL : '');
}

export const wallChoices = (own: readonly OwnWall[]) => [DEFAULT_WALL, ...own.map((entry) => entry.id)];

export const isIdleKind = (kind: unknown): kind is IdleKind => IDLE_KINDS.includes(kind as IdleKind);

export function ownId(value: unknown, own: readonly OwnWall[] = []): string {
  return typeof value === 'string' && own.some((entry) => entry.id === value) ? value : '';
}

export function cleanIdle(raw: unknown, own: readonly OwnWall[] = []): IdlePictures {
  const input = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};

  return { laptop: ownId(input.laptop, own), pc: ownId(input.pc, own), terminal: ownId(input.terminal, own) };
}

export function deviceWall(desktop: boolean, pictures: boolean, wall: unknown, own: readonly OwnWall[] = []): string {
  if (desktop) return wallOr(wall ?? '', own);

  return pictures ? ownId(wall, own) : '';
}

export interface IdlePick {
  id: string;
  shared: boolean;
}

export function idlePick(link: boolean, wall: string, shared: string): IdlePick | null {
  if (link) return null;
  if (wall) return { id: wall, shared: false };

  return shared ? { id: shared, shared: true } : null;
}
