import { DEFAULT_WALL, type OwnWall } from './wallIds';

export const WALLPAPER = 'wallpapers/evolent.webp';
export const WALLPAPER_PICTURE = 'web/build/' + WALLPAPER;
export const IDLE_PREVIEWS: Record<string, string> = { laptop: 'idle/laptop.webp', pc: 'idle/pc.webp', terminal: 'idle/terminal.webp' };

export interface WallSource {
  id: string;
  src: string;
  own: boolean;
}

export function wallSource(id: string, own: readonly OwnWall[]): WallSource {
  const entry = own.find((wall) => wall.id === id);

  return entry ? { id: entry.id, src: entry.src, own: true } : { id: DEFAULT_WALL, src: WALLPAPER, own: false };
}

const probes = new Map<string, Promise<boolean>>();
const known = new Map<string, boolean>();

export function shows(src: string) {
  return known.get(src);
}

export function probe(src: string): Promise<boolean> {
  let job = probes.get(src);

  if (!job) {
    job = new Promise<boolean>((resolve) => {
      const image = new Image();

      image.decoding = 'async';
      image.onload = () => resolve(image.naturalWidth > 0);
      image.onerror = () => resolve(false);
      image.src = src;
    }).then((ok) => {
      known.set(src, ok);

      return ok;
    });
    probes.set(src, job);
  }

  return job;
}

export { cleanIdle, cleanWalls, DEFAULT_WALL, deviceWall, IDLE_KINDS, idlePick, isIdleKind, ownId, SCREEN_SIZES, wallChoices, wallId, wallOr, wallShape, type IdleKind, type IdlePictures, type OwnWall } from './wallIds';
