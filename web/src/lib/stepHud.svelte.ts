import { t } from './state.svelte';

export type Adjust = 'rotate' | 'radius' | 'size' | 'height';
export type Tone = 'ok' | 'warn' | 'bad' | 'wait';
export type HeightMode = 'offset' | 'floor' | 'feet';
export type SlotState = 'done' | 'active' | 'todo' | 'add';

export interface Hint {
  keys: string[];
  label: string;
  go?: boolean;
  off?: boolean;
}

export interface Readout {
  value: string;
  unit: string;
  caption: string;
}

export interface RailGroup {
  title: string;
  rows: { label: string; keys: string[] }[];
}

export interface Slot {
  label: string;
  state: SlotState;
  optional?: boolean;
  count?: number;
  max?: number;
}

export interface Slots {
  title: string;
  items: Slot[];
  placed?: number;
  max?: number;
  least?: number;
  at?: number;
  total?: number;
  plural?: string;
  from?: number;
}

export interface Pill {
  key: string;
  label: string;
  state: SlotState;
  num: string;
  tag: string;
  optional: boolean;
}

export interface SlotBar {
  title: string;
  count: string;
  pills: Pill[];
}

const ADJUST: Adjust[] = ['rotate', 'radius', 'size', 'height'];
const SLOT_STATES: SlotState[] = ['done', 'active', 'todo', 'add'];
const MAX_PILLS = 6;
const KEEP_DONE = 2;

const KEYS = {
  snap: false,
  walk: false,
  click: false,
  zone: false,
  skip: '' as '' | 'skip' | 'done',
};

const SIZES = {
  turn: 5,
  turnFine: 1,
  radius: 1,
  radiusFine: 0.25,
  size: 0.05,
  sizeFine: 0.01,
  lift: 0.05,
  liftFine: 0.01,
};

const live = () => ({
  adjust: [] as Adjust[],
  keys: { ...KEYS },
  sizes: { ...SIZES },
  walking: false,
  loading: false,
  valid: false,
  reason: '',
  notes: [] as string[],
  edge: false,
  snap: true,
  zone: false,
  help: false,
  d: 0,
  h: 0,
  y: 0,
  ymode: 'offset' as HeightMode,
  r: 0,
  size: 0,
  table: 0,
  left: -1,
});

export const ph = $state({
  active: false,
  mode: 'camera' as 'camera' | 'walkup',
  kind: '',
  title: '',
  context: '',
  cue: '',
  placed: '',
  slots: null as Slots | null,
  ...live(),
});

const NUMBERS = ['d', 'h', 'y', 'r', 'size', 'table', 'left'] as const;
const FLAGS = ['walking', 'loading', 'valid', 'edge', 'snap', 'zone', 'help'] as const;
const TEXTS = ['kind', 'title', 'context', 'cue', 'reason'] as const;

const whole = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : undefined);

export function readSlots(value: unknown): Slots | null {
  if (!value || typeof value !== 'object') return null;

  const input = value as Record<string, unknown>;
  const items = Array.isArray(input.items) ? input.items : [];
  const list: Slot[] = [];

  for (const entry of items) {
    if (!entry || typeof entry !== 'object') continue;

    const item = entry as Record<string, unknown>;
    const state = SLOT_STATES.includes(item.state as SlotState) ? (item.state as SlotState) : 'todo';

    if (typeof item.label !== 'string') continue;

    list.push({ label: item.label, state, optional: item.optional === true, count: whole(item.count), max: whole(item.max) });
  }

  return {
    title: typeof input.title === 'string' ? input.title : '',
    items: list,
    placed: whole(input.placed),
    max: whole(input.max),
    least: whole(input.least),
    at: whole(input.at),
    total: whole(input.total),
    plural: typeof input.plural === 'string' ? input.plural : undefined,
    from: whole(input.from),
  };
}

function merge(m: Record<string, unknown>) {
  for (const key of NUMBERS) {
    const value = m[key];
    if (typeof value === 'number' && Number.isFinite(value)) ph[key] = value;
  }
  for (const key of FLAGS) {
    const value = m[key];
    if (typeof value === 'boolean') ph[key] = value;
  }
  for (const key of TEXTS) {
    const value = m[key];
    if (typeof value === 'string') ph[key] = value;
  }
  if (m.ymode === 'offset' || m.ymode === 'floor' || m.ymode === 'feet') ph.ymode = m.ymode;
  if (typeof m.notes === 'string') ph.notes = m.notes === '' ? [] : m.notes.split('\n');
  if (Array.isArray(m.adjust)) ph.adjust = ADJUST.filter((id) => (m.adjust as unknown[]).includes(id));
  if (m.keys && typeof m.keys === 'object') ph.keys = { ...KEYS, ...(m.keys as Partial<typeof KEYS>) };
  if (m.sizes && typeof m.sizes === 'object') ph.sizes = { ...SIZES, ...(m.sizes as Partial<typeof SIZES>) };
  if (m.slots !== undefined) ph.slots = readSlots(m.slots);
}

export function placementMessage(m: Record<string, unknown>) {
  switch (m.state) {
    case 'start':
      Object.assign(ph, live(), { active: true, mode: m.mode === 'walkup' ? 'walkup' : 'camera' });
      merge(m);
      break;
    case 'tick':
      merge(m);
      break;
    case 'walk':
      ph.walking = true;
      break;
    case 'resume':
      ph.walking = false;
      break;
    case 'end':
      Object.assign(ph, { active: false, walking: false, title: '', context: '', cue: '', placed: '', slots: null });
      break;
  }
}

function countText(s: Slots) {
  if (s.total && s.at) return t('ui_placement_of', s.at, s.total);

  const placed = s.placed ?? s.items.filter((item) => item.state === 'done').length;

  if (s.max) return t('ui_placement_of', placed, s.max);
  if (s.least) return t('ui_placement_least', placed, s.least);
  if (s.placed !== undefined) return t('ui_placement_no_limit', placed);

  return '';
}

function pillOf(item: Slot, index: number, from: number): Pill {
  const tag = item.state === 'active' && item.count !== undefined && item.max ? t('ui_placement_of', item.count, item.max) : '';

  return {
    key: `${index}:${item.label}`,
    label: item.label,
    state: item.state,
    num: String(from + index),
    tag,
    optional: item.optional === true,
  };
}

function folded(pills: Pill[], plural: string, state: SlotState, label?: string): Pill {
  const first = pills[0];
  const last = pills[pills.length - 1];

  return {
    key: `fold:${first.key}`,
    label: label ?? t('ui_placement_span', plural, first.num, last.num),
    state,
    num: first.num,
    tag: '',
    optional: false,
  };
}

export const multiPoint = (s: typeof ph) => {
  const slots = s.slots;

  return !!slots && slots.items.length > 0 && (slots.items.length > 1 || !!slots.total || !!slots.max || slots.placed !== undefined);
};

export function slotBar(s: typeof ph): SlotBar {
  const slots = s.slots;

  if (!slots || !multiPoint(s)) {
    const name = slots?.items[0]?.label || s.title;
    const pills: Pill[] = name ? [{ key: 'one', label: name, state: 'active', num: '1', tag: '', optional: false }] : [];

    return { title: '', count: '', pills };
  }

  const first = Math.max(1, slots.from ?? 1);
  const all = slots.items.map((item, index) => pillOf(item, index, first));
  const add = all.filter((pill) => pill.state === 'add');
  let points = all.filter((pill) => pill.state !== 'add');
  const plural = slots.plural || t('ui_placement_points');

  if (points.length > MAX_PILLS) {
    const done = points.filter((pill) => pill.state === 'done');

    if (done.length > KEEP_DONE + 1) {
      const fold = done.slice(0, done.length - KEEP_DONE);
      const start = points.indexOf(fold[0]);

      points = [...points.slice(0, start), folded(fold, plural, 'done'), ...points.slice(start + fold.length)];
    }
  }

  const from = Math.max(MAX_PILLS - 1, points.findIndex((pill) => pill.state === 'active') + 1);

  if (points.length > MAX_PILLS && points.length - from > 1) {
    const tail = points.slice(from);

    points = [...points.slice(0, from), folded(tail, plural, 'todo', t('ui_placement_more', tail.length))];
  }

  return { title: slots.title, count: countText(slots), pills: [...points, ...add] };
}

const amount = (v: number) => (v < 1 ? t('ui_placement_cm', Math.round(v * 100)) : t('ui_placement_m', v));
const deg = (v: number) => String(Math.round(((v % 360) + 360) % 360) % 360);
const signed = (v: number) => {
  const n = Math.round(v * 100) / 100;
  return (n > 0 ? '+' : '') + (n === 0 ? 0 : n).toFixed(2);
};

const has = (s: typeof ph, id: Adjust) => s.adjust.includes(id);

function wheelTarget(s: typeof ph): Adjust | null {
  if (has(s, 'rotate')) return 'rotate';
  if (has(s, 'radius')) return 'radius';
  if (has(s, 'size')) return 'size';
  return null;
}

function heightRead(s: typeof ph): Readout {
  if (s.ymode === 'floor') return { value: s.y.toFixed(2), unit: t('ui_placement_unit_m'), caption: t('ui_placement_above_floor') };
  return { value: signed(s.y), unit: t('ui_placement_unit_m'), caption: t(s.ymode === 'feet' ? 'ui_placement_above_feet' : 'ui_placement_height_offset') };
}

export function readouts(s: typeof ph): Readout[] {
  if (s.mode === 'walkup') {
    return [
      { value: s.table.toFixed(2), unit: t('ui_placement_unit_m'), caption: t('ui_placement_table_height') },
      { value: deg(s.h), unit: '°', caption: t('ui_placement_heading') },
    ];
  }
  if (s.walking) return [{ value: s.d.toFixed(1), unit: t('ui_placement_unit_m'), caption: t('ui_placement_to_spot') }];
  const out: Readout[] = [{ value: s.d.toFixed(1), unit: t('ui_placement_unit_m'), caption: t('ui_placement_distance') }];
  if (has(s, 'rotate')) out.push({ value: deg(s.h), unit: '°', caption: t('ui_placement_heading') });
  if (has(s, 'radius')) out.push({ value: s.r.toFixed(1), unit: t('ui_placement_unit_m'), caption: t('ui_placement_radius') });
  if (has(s, 'size')) out.push({ value: s.size.toFixed(2), unit: t('ui_placement_unit_m'), caption: t('ui_placement_zone_size') });
  if (has(s, 'height')) out.push(heightRead(s));
  return out;
}

const WHEEL_LABEL: Record<Adjust, string> = { rotate: 'ui_placement_rotate', radius: 'ui_placement_radius', size: 'ui_placement_size', height: 'ui_placement_height' };

export function hints(s: typeof ph): Hint[] {
  const k = s.keys;
  if (s.mode === 'walkup') {
    return [
      { keys: [t('ui_key_mouse')], label: t('ui_placement_look_table') },
      { keys: [t('ui_key_wheel')], label: t('ui_placement_turn') },
      { keys: [t('ui_key_enter')], label: t('ui_placement_place'), go: true, off: !s.valid },
    ];
  }
  if (s.walking) {
    return [
      { keys: [t('ui_key_enter')], label: t('ui_placement_back'), go: true },
      { keys: ['X'], label: t('ui_placement_stop') },
    ];
  }
  const out: Hint[] = [{ keys: ['W', 'A', 'S', 'D'], label: t('ui_placement_move') }];
  const wheel = wheelTarget(s);
  if (wheel) out.push({ keys: [t('ui_key_wheel')], label: t(WHEEL_LABEL[wheel]) });
  if (wheel === 'rotate' && has(s, 'radius')) out.push({ keys: [t('ui_key_ctrl_wheel')], label: t('ui_placement_radius') });
  if (has(s, 'height')) out.push({ keys: [t('ui_key_pgup'), t('ui_key_pgdn')], label: t('ui_placement_height') });
  if (k.snap) out.push({ keys: ['F'], label: t(s.snap ? 'ui_placement_free_height' : 'ui_placement_snap') });
  else if (has(s, 'height')) out.push({ keys: ['F'], label: t('ui_placement_to_surface') });
  if (k.zone) out.push({ keys: ['Z'], label: t(s.zone ? 'ui_placement_use_marker' : 'ui_placement_use_zone') });
  if (k.skip) out.push({ keys: [t('ui_key_backspace')], label: t(k.skip === 'done' ? 'ui_placement_done' : 'ui_placement_skip') });
  out.push({ keys: [t('ui_key_enter')], label: t('ui_placement_place'), go: true, off: !s.valid });
  return out;
}

function lastFree(s: typeof ph) {
  const slots = s.slots;

  if (!slots?.max || slots.total) return false;

  const placed = slots.placed ?? slots.items.filter((item) => item.state === 'done').length;

  return placed + 1 === slots.max;
}

export function status(s: typeof ph): { tone: Tone; text: string } {
  if (s.placed) return { tone: 'ok', text: s.placed };
  if (s.loading) return { tone: 'wait', text: t('ui_placement_loading') };
  if (s.walking) return { tone: 'wait', text: t('ui_placement_walk_enter') };
  if (!s.valid) return { tone: 'bad', text: s.reason };
  if (s.edge) return { tone: 'warn', text: t(s.keys.walk ? 'ui_placement_edge_walk' : 'ui_placement_edge') };
  if (s.notes.length) return { tone: 'warn', text: t('ui_placement_notes') };
  if (s.mode === 'walkup') {
    return { tone: 'ok', text: s.left >= 0 && s.left <= 15 ? t('ui_placement_put_left', s.left) : t('ui_placement_put') };
  }
  return { tone: 'ok', text: t(lastFree(s) ? 'ui_placement_last' : 'ui_placement_valid') };
}

export function rail(s: typeof ph): RailGroup[] {
  const { keys: k, sizes: z } = s;
  const wheel = wheelTarget(s);
  const object: RailGroup['rows'] = [];
  if (has(s, 'rotate')) object.push({ label: t('ui_placement_rail_rotate', z.turn + '°'), keys: [t('ui_key_wheel')] });
  if (has(s, 'radius')) object.push({ label: t('ui_placement_rail_radius', amount(z.radius)), keys: [t(wheel === 'radius' ? 'ui_key_wheel' : 'ui_key_ctrl_wheel')] });
  if (has(s, 'size')) object.push({ label: t('ui_placement_rail_size', amount(z.size)), keys: [t('ui_key_wheel')] });
  if (has(s, 'height')) object.push({ label: t('ui_placement_rail_height', amount(z.lift)), keys: [t('ui_key_pgup'), t('ui_key_pgdn')] });
  if (object.length) object.push({ label: t('ui_placement_fine'), keys: [t('ui_key_alt')] });
  if (k.snap) object.push({ label: t('ui_placement_snap_set'), keys: ['F'] });
  else if (has(s, 'height')) object.push({ label: t('ui_placement_to_surface'), keys: ['F'] });
  if (k.zone) object.push({ label: t('ui_placement_marker_zone'), keys: ['Z'] });
  const groups: RailGroup[] = [
    {
      title: t('ui_placement_group_camera'),
      rows: [
        { label: t('ui_placement_move'), keys: ['W', 'A', 'S', 'D'] },
        { label: t('ui_placement_look'), keys: [t('ui_key_mouse')] },
        { label: t('ui_placement_down_up'), keys: ['Q', 'E'] },
        { label: t('ui_placement_faster'), keys: [t('ui_key_shift')] },
      ],
    },
  ];
  if (object.length) groups.push({ title: t('ui_placement_group_object'), rows: object });
  if (k.skip) groups.push({ title: t('ui_placement_group_points'), rows: [{ label: t(k.skip === 'done' ? 'ui_placement_done' : 'ui_placement_skip'), keys: [t('ui_key_backspace')] }] });
  groups.push({
    title: t('ui_placement_group_actions'),
    rows: [
      { label: t('ui_placement_place'), keys: [t('ui_key_enter')] },
      ...(k.click ? [{ label: t('ui_placement_confirm'), keys: [t('ui_key_click')] }] : []),
      ...(k.walk ? [{ label: t('ui_placement_walk'), keys: ['G'] }] : []),
      { label: t('ui_placement_stop'), keys: [t('ui_key_esc')] },
    ],
  });
  return groups;
}
