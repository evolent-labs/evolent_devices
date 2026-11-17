import type { Kind } from '$lib/types';

export type FieldKind = 'number' | 'bool' | 'select' | 'set' | 'colour' | 'hours' | 'access' | 'text' | 'numbers' | 'hosts';
export type FieldSource = 'general' | 'kinds' | 'config';
export type FieldValue = number | boolean | string | (number | string)[] | Record<string, unknown> | null;

export interface FieldOption {
  value: string | number;
  text?: string;
}

export interface SettingField {
  id: string;
  path: string;
  source: FieldSource;
  group: string;
  section: string;
  kind: FieldKind;
  label: string;
  labelArgs?: unknown[];
  help?: string;
  min?: number;
  max?: number;
  step?: number;
  whole?: boolean;
  unit?: string;
  options?: FieldOption[];
  optional?: boolean;
  restart?: boolean;
  maxLength?: number;
  maxItems?: number;
  kindOf?: Kind;
  shipped: FieldValue;
}

export interface SettingGroup {
  id: string;
  picture: string;
}

export interface SettingLink {
  id: string;
  group: string;
  page?: 'items' | 'apps';
  map?: 'signal' | 'zones';
  dialog?: 'brand';
}

export const KINDS: Kind[] = ['laptop', 'pc', 'terminal', 'tablet'];

export const GROUPS: SettingGroup[] = [
  { id: 'devices', picture: 'pc' },
  { id: 'use', picture: 'laptop' },
  { id: 'sound', picture: 'laptop' },
  { id: 'screens', picture: 'terminal' },
  { id: 'os', picture: 'pc' },
  { id: 'tablet', picture: 'tablet' },
  { id: 'notifications', picture: 'laptop' },
  { id: 'nearby', picture: 'terminal' },
  { id: 'placing', picture: 'laptop' },
  { id: 'signal', picture: 'tablet' },
  { id: 'advanced', picture: '' },
  { id: 'tools', picture: '' },
];

export const LINKS: SettingLink[] = [
  { id: 'items', group: 'devices', page: 'items' },
  { id: 'brand', group: 'screens', dialog: 'brand' },
  { id: 'apps', group: 'os', page: 'apps' },
  { id: 'zones', group: 'placing', map: 'zones' },
  { id: 'signal', group: 'signal', map: 'signal' },
];

type Local = Omit<SettingField, 'shipped' | 'source'> & { source?: FieldSource };

const general = (path: string, group: string, section: string, kind: FieldKind, label: string, extra: Partial<Local> = {}): Local => ({
  id: path,
  path,
  group,
  section,
  kind,
  label,
  ...extra,
});

const kindRows = (): Local[] =>
  KINDS.flatMap((kind) => [
    { id: `kinds.${kind}.enabled`, path: `kinds.${kind}.enabled`, source: 'kinds', group: 'devices', section: 'kinds', kind: 'bool', label: 'kind_plural_' + kind, help: 'ui_cfg_kind_on_help', kindOf: kind },
    { id: `kinds.${kind}.max`, path: `kinds.${kind}.max`, source: 'kinds', group: 'devices', section: 'kinds', kind: 'number', label: 'ui_cfg_kind_max', labelArgs: ['kind_plural_' + kind], help: 'ui_cfg_kind_max_help', min: 0, max: 500, step: 1, whole: true, kindOf: kind },
  ] as Local[]);

const startRows = (): Local[] =>
  KINDS.filter((kind) => kind !== 'tablet').map((kind) => ({
    id: `kinds.${kind}.startAccess`,
    path: `kinds.${kind}.startAccess`,
    source: 'kinds',
    group: 'devices',
    section: 'start',
    kind: 'access',
    label: 'kind_plural_' + kind,
    kindOf: kind,
  }));

export const LOCAL_FIELDS: Local[] = [
  ...kindRows(),
  ...startRows(),
  general('general.session.idleMinutes', 'use', 'sessions', 'number', 'ui_set_idle_minutes', { help: 'ui_set_idle_minutes_help', min: 0, max: 240, step: 1, whole: true }),
  general('general.session.lockMinutes', 'use', 'sessions', 'number', 'ui_set_lock_minutes', { help: 'ui_set_lock_minutes_help', min: 0, max: 120, step: 1, whole: true }),
  general('general.adminsOpenAny', 'use', 'sessions', 'bool', 'ui_set_admins_open_any', { help: 'ui_set_admins_open_any_help' }),
  general('general.sound.enabled', 'sound', 'sound', 'bool', 'ui_set_sound_enabled', { help: 'ui_set_sound_enabled_help' }),
  general('general.sound.volume', 'sound', 'sound', 'number', 'ui_set_sound_volume', { help: 'ui_set_sound_volume_help', min: 0, max: 100, step: 5, whole: true }),
  general('general.sound.nearby', 'sound', 'sound', 'number', 'ui_set_sound_nearby', { help: 'ui_set_sound_nearby_help', min: 0, max: 100, step: 5, whole: true }),
  general('general.sound.range', 'sound', 'sound', 'number', 'ui_set_sound_range', { help: 'ui_set_sound_range_help', min: 3, max: 10, step: 0.5 }),
  general('general.display.brightness', 'screens', 'display', 'number', 'ui_screen_brightness', { help: 'ui_set_brightness_help', min: 20, max: 100, step: 5, whole: true, unit: 'percent' }),
  general('general.display.light', 'screens', 'display', 'number', 'ui_set_light_strength', { help: 'ui_set_light_strength_help', min: 0, max: 200, step: 10, whole: true, unit: 'percent' }),
  general('general.display.color', 'screens', 'display', 'colour', 'ui_screen_color', { help: 'ui_set_light_color_help', optional: true }),
  general('general.display.sleep', 'screens', 'sleep', 'number', 'ui_screen_sleep', { help: 'ui_cfg_sleep_help', min: 0, max: 240, step: 1, whole: true }),
  general('general.display.night', 'screens', 'sleep', 'bool', 'ui_screen_night', { help: 'ui_screen_night_info' }),
  general('general.display.nightFrom', 'screens', 'sleep', 'hours', 'ui_set_night_hours', { help: 'ui_set_night_hours_help' }),
  general('general.watchRange', 'nearby', 'nearby', 'number', 'ui_set_watch_range', { help: 'ui_set_watch_range_help', min: 4, max: 30, step: 0.5 }),
  general('general.twinRadius', 'nearby', 'nearby', 'number', 'ui_set_twin_radius', { help: 'ui_set_twin_radius_help', min: 5, max: 60, step: 0.5 }),
  general('general.forceCover', 'nearby', 'nearby', 'bool', 'ui_set_force_cover', { help: 'ui_set_force_cover_help' }),
  general('general.session.leaseSeconds', 'advanced', 'connection', 'number', 'ui_set_lease_seconds', { help: 'ui_set_lease_seconds_help', min: 5, max: 120, step: 1, whole: true }),
  general('general.session.heartbeatSeconds', 'advanced', 'connection', 'number', 'ui_set_heartbeat_seconds', { help: 'ui_set_heartbeat_seconds_help', min: 2, max: 30, step: 1, whole: true }),
  general('general.auditDays', 'advanced', 'history', 'number', 'ui_set_audit_days', { help: 'ui_set_audit_days_help', min: 7, max: 365, step: 1, whole: true }),
  general('general.removedDays', 'advanced', 'history', 'number', 'ui_set_removed_days', { help: 'ui_set_removed_days_help', min: 1, max: 365, step: 1, whole: true }),
];

export const NIGHT_TO = 'general.display.nightTo';

export const snake = (id: string) =>
  id
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .replace(/[^A-Za-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();

export function valueAt(source: unknown, path: string): unknown {
  let value: any = source;

  for (const part of path.split('.')) value = value?.[part];

  return value;
}

export function setAt(target: Record<string, any>, path: string, value: unknown) {
  const parts = path.split('.');
  let node = target;

  for (const part of parts.slice(0, -1)) {
    if (!node[part] || typeof node[part] !== 'object') node[part] = {};
    node = node[part];
  }

  node[parts[parts.length - 1]] = value;
}
