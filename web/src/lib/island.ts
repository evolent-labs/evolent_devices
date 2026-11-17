import type { Corner } from './notices';

export interface Shape {
  x: number;
  y: number;
  w: number;
  h: number;
  r: number;
}

export interface Anchor {
  x: number;
  bottom: boolean;
}

export interface Piece {
  round: boolean;
  t: string;
}

export interface Stacked {
  spots: Map<number, number>;
  rank: Map<number, number>;
  end: number;
}

export const FACE = 392;
export const PILL = 44;
export const GAP = 8;
export const ICON = 48;
export const SMALL = 0.75;
export const PAD = 16;
export const TEXT_GAP = 12;
export const PILL_TEXT = 48;
export const CARD_R = 28;
export const POCKET_H = 68;
export const MORE_H = 32;
export const ROWS = { label: 16, title: 20, body: 20 };
export const UNDER_TITLE = 16;
export const SIZES = { label: 11, seed: 12, title: 15, pocketTitle: 14, short: 13 };
export const GROW_MS = { popup: 480, pocket: 420 };

const n = (value: number) => Math.round(value * 1000) / 1000;

export const move = (x: number, y: number, scale = 1) => `translate(${n(x)}px, ${n(y)}px) scale(${n(scale)}, ${n(scale)})`;

const circle = (cx: number, cy: number, r: number) => move(cx - r, cy - r, (2 * r) / 100);

const rect = (x: number, y: number, w: number, h: number) => `translate(${n(x)}px, ${n(y)}px) scale(${n(Math.max(0, w) / 100)}, ${n(Math.max(0, h) / 100)})`;

export function anchorOf(corner: Corner): Anchor {
  return { x: corner === 'top_left' ? 0 : corner === 'top_center' ? 0.5 : 1, bottom: corner === 'bottom_right' };
}

export const inset = (s: Shape, by = 1): Shape => ({ x: s.x + by, y: s.y + by, w: s.w - 2 * by, h: s.h - 2 * by, r: Math.max(0, s.r - by) });

export function pieces(s: Shape): Piece[] {
  const { x, y, w, h, r } = s;

  return [
    { round: false, t: rect(x, y + r, w, h - 2 * r) },
    { round: false, t: rect(x + r, y, w - 2 * r, h) },
    { round: true, t: circle(x + r, y + r, r) },
    { round: true, t: circle(x + w - r, y + r, r) },
    { round: true, t: circle(x + r, y + h - r, r) },
    { round: true, t: circle(x + w - r, y + h - r, r) },
  ];
}

export const cardHeight = (body: number) => PAD + ROWS.label + (body > 0 ? UNDER_TITLE + body : ROWS.title) + PAD;

export const pillWidth = (text: number, scale: number) => Math.round(PILL_TEXT + Math.max(0, text) * scale + PILL / 2);

export function pillShape(width: number, anchor: Anchor): Shape {
  return { x: anchor.x * (FACE - width), y: anchor.bottom ? -PILL : 0, w: width, h: PILL, r: PILL / 2 };
}

export function cardShape(pocket: boolean, height: number, anchor: Anchor): Shape {
  const h = pocket ? POCKET_H : height;

  return { x: 0, y: anchor.bottom ? -h : 0, w: FACE, h, r: pocket ? POCKET_H / 2 : CARD_R };
}

const edgeOf = (pocket: boolean) => (pocket ? (POCKET_H - ICON) / 2 : PAD);

export function iconSpot(s: Shape, open: boolean, pocket: boolean) {
  if (!open) return move(s.x + (PILL - ICON * SMALL) / 2, s.y + (PILL - ICON * SMALL) / 2, SMALL);

  return move(s.x + edgeOf(pocket), s.y + edgeOf(pocket));
}

export function textSpot(s: Shape, pocket: boolean) {
  return { x: s.x + edgeOf(pocket) + ICON + TEXT_GAP, y: s.y + (pocket ? (POCKET_H - ROWS.label - ROWS.title) / 2 : PAD) };
}

export function inPill(s: Shape, row: number, scale: number) {
  return move(s.x + PILL_TEXT, s.y + (PILL - row * scale) / 2, scale);
}

export function seedColumn(s: Shape) {
  const scale = SIZES.seed / SIZES.label;
  const x = s.x + PILL_TEXT;
  const label = s.y + (PILL - ROWS.label * scale) / 2;
  const title = label + ROWS.label * scale;

  return { label: move(x, label, scale), title: move(x, title), body: move(x, title + UNDER_TITLE) };
}

export const appSpot = (s: Shape) => move(s.x + s.w - s.h / 2 - 10, s.y + s.h / 2 - 10);

export const centreOf = (s: Shape) => `${n(s.x + s.w / 2)}px ${n(s.y + s.h / 2)}px`;

export function stack<T extends { id: number; out: boolean }>(list: T[], size: (card: T) => number, gap = GAP): Stacked {
  const spots = new Map<number, number>();
  const rank = new Map<number, number>();
  let y = 0;
  let tail = 0;

  for (const card of list) {
    spots.set(card.id, y);

    if (card.out) {
      tail = Math.max(tail, y + size(card) + gap);
      continue;
    }

    rank.set(card.id, rank.size);
    y += size(card) + gap;
  }

  return { spots, rank, end: Math.max(y, tail) };
}

export function scaleFor(width: number, height: number) {
  return Math.max(0.875, Math.min(width, height) / 1080);
}
