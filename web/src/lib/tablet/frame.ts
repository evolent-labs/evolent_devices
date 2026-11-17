import { hexToRgb } from '../hex';
import palette from './colours.json';

export interface TabletColour {
  id: string;
  hex: string;
}

export const COLOURS: TabletColour[] = palette;

export const SCREEN = { width: 1440, height: 900 };
export const BEZEL = 34;
export const OUTER = { width: SCREEN.width + BEZEL * 2, height: SCREEN.height + BEZEL * 2 };
export const STATUS_BAR = 44;
const MARGIN = 48;

export function colourIndex(value: unknown) {
  const index = Number(value);

  return Number.isInteger(index) && index >= 0 && index < COLOURS.length ? index : 0;
}

function mix(rgb: number[], to: number, amount: number) {
  return 'rgb(' + rgb.map((c) => Math.round(c + (to - c) * amount)).join(',') + ')';
}

export function frameTones(hex: string) {
  const c = hexToRgb(hex);

  return { border: mix(c, 255, 0.22), rim: mix(c, 0, 0.08), btnTop: mix(c, 255, 0.24), btnBot: mix(c, 0, 0.18) };
}

export function frameScale(width: number, height: number, framed: boolean) {
  const w = framed ? OUTER.width : SCREEN.width;
  const h = framed ? OUTER.height : SCREEN.height;

  return Math.max(0.1, Math.min(height / 1080, (width - MARGIN) / w, (height - MARGIN) / h));
}

export function appScale(canvas?: { width: number; height: number }) {
  const area = { width: SCREEN.width, height: SCREEN.height - STATUS_BAR };

  return canvas ? Math.min(area.width / canvas.width, area.height / canvas.height) : 1;
}

export function fillScale(width: number, height: number) {
  return Math.max(0.1, Math.min(width / SCREEN.width, height / SCREEN.height));
}

function luminance([r, g, b]: number[]) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

export function tileOf(ink: string) {
  const c = hexToRgb(ink);

  return {
    tile: mix(c, 14, 0.84),
    onTile: luminance(c) > 0.12 ? `rgb(${c.join(',')})` : '#f4f4f5',
  };
}
